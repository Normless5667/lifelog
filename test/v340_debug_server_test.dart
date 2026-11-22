import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/debug/debug_server.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/theme/app_theme.dart';
import 'package:lifelog/widgets/debug_server_banner.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  group('v3.4.0 Wi-Fi DebugServer HTTP + WebSocket + Security', () {
    test('defaults to OFF and regenerates a fresh random token on every start', () async {
      final srv = DebugServer.forTest();
      expect(srv.isRunning, isFalse);
      expect(srv.token, isNull);
      expect(srv.connectUrl, isNull);

      await srv.start(port: 0);
      final token1 = srv.token;
      expect(srv.isRunning, isTrue);
      expect(token1, isNotNull);
      expect(token1!.length, greaterThanOrEqualTo(16));
      expect(srv.connectUrl, contains('?token=$token1'));

      await srv.stop();
      expect(srv.isRunning, isFalse);
      expect(srv.token, isNull);

      await srv.start(port: 0);
      final token2 = srv.token;
      expect(token2, isNotNull);
      expect(token2, isNot(equals(token1)));

      await srv.stop();
    });

    test('enforces 403 Forbidden without valid token and serves dark HTML console with valid token',
        () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final srv = DebugServer.forTest();
        await srv.start(port: 0);
        final port = srv.port;
        final token = srv.token!;
        final client = HttpClient();

        try {
          // 1) Missing token -> 403
          final reqNoToken = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
          final resNoToken = await reqNoToken.close();
          expect(resNoToken.statusCode, HttpStatus.forbidden);
          await resNoToken.drain<void>();

          // 2) Wrong token -> 403
          final reqBadToken =
              await client.getUrl(Uri.parse('http://127.0.0.1:$port/?token=wrongtoken123'));
          final resBadToken = await reqBadToken.close();
          expect(resBadToken.statusCode, HttpStatus.forbidden);
          await resBadToken.drain<void>();

          // 3) WS without token -> 403
          final reqWsNoToken = await client.getUrl(Uri.parse('http://127.0.0.1:$port/ws'));
          final resWsNoToken = await reqWsNoToken.close();
          expect(resWsNoToken.statusCode, HttpStatus.forbidden);
          await resWsNoToken.drain<void>();

          // 4) Valid token -> 200 HTML console with copy button & config panel
          final reqOk = await client.getUrl(Uri.parse('http://127.0.0.1:$port/?token=$token'));
          final resOk = await reqOk.close();
          expect(resOk.statusCode, HttpStatus.ok);
          final body = await utf8.decodeStream(resOk);
          expect(body, contains('LifeLog 调试台'));
          expect(body, contains('一键复制全部日志'));
          expect(body, contains('只看错误'));
          expect(body, contains('update_config'));
        } finally {
          client.close(force: true);
          await srv.stop();
        }
      }, _RealHttpOverrides());
    });

    test('streams PlatformException full details uplink and applies update_config downlink live',
        () async {
      final srv = DebugServer.forTest();
      srv.log('boot log before connect', tag: 'App');
      await srv.start(port: 0);
      final port = srv.port;
      final token = srv.token!;

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws?token=$token');
      final incoming = <Map<String, dynamic>>[];
      final gotError = Completer<Map<String, dynamic>>();
      final gotConfig = Completer<Map<String, dynamic>>();
      final gotHello = Completer<Map<String, dynamic>>();

      final sub = ws.listen((dynamic raw) {
        final j = jsonDecode(raw as String) as Map<String, dynamic>;
        incoming.add(j);
        if (j['type'] == 'hello' && !gotHello.isCompleted) {
          gotHello.complete(j);
        } else if (j['type'] == 'log' && j['level'] == 'error' && !gotError.isCompleted) {
          gotError.complete(j);
        } else if (j['type'] == 'config' && !gotConfig.isCompleted) {
          gotConfig.complete(j);
        }
      });

      try {
        final hello = await gotHello.future.timeout(const Duration(seconds: 3));
        expect(hello['history'], isA<List<dynamic>>());
        expect(
          (hello['history'] as List<dynamic>).any(
            (e) => (e as Map)['message'] == 'boot log before connect',
          ),
          isTrue,
        );

        // Uplink: push full PlatformException (like ML Kit InputImageConverterError)
        srv.logError(
          'OCR',
          PlatformException(
            code: 'InputImageConverterError',
            message: 'java.io.IOException: The image Uri could not be resolved.',
            details: 'mock_details',
            stacktrace: 'com.google_mlkit_commons.InputImageConverter.handleFileImage:54',
          ),
          StackTrace.current,
          'HD capture OCR failed (path=/cache/CAP1.jpg, exists=true, bytes=12345)',
        );

        final errMsg = await gotError.future.timeout(const Duration(seconds: 3));
        expect(errMsg['tag'], 'OCR');
        expect(errMsg['message'], contains('InputImageConverterError'));
        expect(errMsg['message'], contains('The image Uri could not be resolved.'));
        expect(errMsg['message'], contains('exists=true, bytes=12345'));
        expect(errMsg['message'], contains('handleFileImage:54'));
        expect(errMsg['stack'], isNotEmpty);

        // Downlink: update runtime config from PC console
        ws.add(jsonEncode({
          'cmd': 'update_config',
          'fx_rate': 0.00029,
          'threshold': 0.72,
        }));

        final cfgReply = await gotConfig.future.timeout(const Duration(seconds: 3));
        expect(cfgReply['fx_rate'], closeTo(0.00029, 1e-9));
        expect(cfgReply['threshold'], closeTo(0.72, 1e-9));
        expect(srv.config.fxRate, closeTo(0.00029, 1e-9));
        expect(srv.config.threshold, closeTo(0.72, 1e-9));
        expect(srv.config.fxRateOverridden, isTrue);
      } finally {
        await sub.cancel();
        await ws.close();
        await srv.stop();
      }
    });

    test('auto-stops after idle timeout with no clients', () async {
      final srv = DebugServer.forTest();
      await srv.start(port: 0, idleTimeout: const Duration(milliseconds: 120));
      expect(srv.isRunning, isTrue);
      expect(srv.idleShutdownAt, isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(srv.isRunning, isFalse);
      expect(srv.token, isNull);
    });

    test('auto-stops immediately when AppLifecycleState.detached fires', () async {
      final srv = DebugServer.forTest();
      await srv.start(port: 0);
      expect(srv.isRunning, isTrue);

      srv.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(srv.isRunning, isFalse);
    });
  });

  group('v3.4.0 DebugServerBannerHost persistent red header indicator', () {
    testWidgets('shows persistent red top banner when running and stops server on tap',
        (tester) async {
      final srv = DebugServer.forTest();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DebugServerBannerHost(
            server: srv,
            child: const Scaffold(body: Center(child: Text('Body'))),
          ),
        ),
      );
      await tester.pump();

      // Default OFF -> no red banner
      expect(find.byKey(const ValueKey('debug_server_top_banner')), findsNothing);

      // Start server -> persistent red banner appears
      await tester.runAsync(() => srv.start(port: 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('debug_server_top_banner')), findsOneWidget);
      expect(find.textContaining('调试服务运行中'), findsOneWidget);

      // Tap banner -> stops server immediately & hides banner
      await tester.tap(find.byKey(const ValueKey('debug_server_top_banner')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(srv.isRunning, isFalse);
      expect(find.byKey(const ValueKey('debug_server_top_banner')), findsNothing);
    });
  });
}

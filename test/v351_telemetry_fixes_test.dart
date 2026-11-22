import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/debug/debug_server.dart';
import 'package:lifelog/services/usage_telemetry_service.dart';

void main() {
  group('v3.5.1 Telemetry fixes (bus_board / log_weight / ai_plan_import)', () {
    test('trackFeature forwards stage & 100-char truncated error to DebugServer log stream', () {
      final longErr = 'E' * 160;
      UsageTelemetryService.instance.trackFeature(
        'ai_plan_import',
        'fail',
        durationMs: 42,
        stage: 'parse',
        errorMsg: longErr,
      );

      final last = DebugServer.instance.history.last;
      expect(last.level, 'error');
      expect(last.tag, 'Feature');
      expect(last.message, contains('feature="ai_plan_import"'));
      expect(last.message, contains('action=fail'));
      expect(last.message, contains('stage=parse'));
      expect(last.message, contains('42ms'));
      // 限制错误长度 <= 100 字符
      final errMatch = RegExp(r'error="([^"]+)"').firstMatch(last.message);
      expect(errMatch, isNotNull);
      expect(errMatch!.group(1)!.length, 100);
    });

    test('source audit: bus_board removed from trackFeature, log_weight & ai_plan_import have stage fail hooks', () {
      final homeSrc = File('lib/screens/home_screen.dart').readAsStringSync();
      expect(homeSrc.contains("trackFeature('bus_board'"), isFalse);
      expect(homeSrc.contains("enterPage('bus_board'"), isTrue);

      final bodySrc = File('lib/screens/body/body_screen.dart').readAsStringSync();
      expect(bodySrc.contains("stage: 'validate'"), isTrue);
      expect(bodySrc.contains("stage: 'save'"), isTrue);
      expect(bodySrc.contains("trackFeature(\n          'log_weight',\n          'fail'"), isTrue);

      final aiSrc = File('lib/screens/ai/ai_chat_screen.dart').readAsStringSync();
      expect(aiSrc.contains("stage: 'parse'"), isTrue);
      expect(aiSrc.contains("stage: 'save'"), isTrue);
    });
  });
}

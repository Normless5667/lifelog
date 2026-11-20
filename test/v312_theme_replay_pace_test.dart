import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/run_models.dart';
import 'package:lifelog/screens/running/run_detail_screen.dart';
import 'package:lifelog/services/running_tracker.dart';
import 'package:lifelog/theme/app_theme.dart';
import 'package:lifelog/widgets/common.dart';

/// 构造一条 600 米渐变配速轨迹（前 300m 约 5'00"/km，后 300m 约 7'00"/km）
List<RoutePoint> _buildVariablePaceRoute() {
  const baseLat = 20.9628;
  const baseLng = 105.9410;
  // 纬度 0.00018 度 ≈ 20 米
  const stepLat = 0.00018;
  final pts = <RoutePoint>[];
  var t = 1700000000000;
  for (var i = 0; i <= 30; i++) {
    pts.add(RoutePoint(
      lat: baseLat + i * stepLat,
      lng: baseLng,
      t: t,
      accuracy: 6.0,
    ));
    // 前 15 步每 20m 用 6 秒（3.33 m/s = 5'00"/km），后 15 步每 20m 用 8.4 秒（2.38 m/s = 7'00"/km）
    t += (i < 15 ? 6000 : 8400);
  }
  return pts;
}

void main() {
  group('v3.1.2 Gemini Midnight Black skin tokens', () {
    test('AppTheme.midnight() attaches exact Gemini palette & borderless radii', () {
      final theme = AppTheme.midnight();
      final ext = theme.extension<AppSkinExtension>();

      expect(ext, isNotNull);
      expect(ext!.isMidnight, isTrue);
      expect(ext.borderlessCards, isTrue);
      expect(ext.cardRadius, 24.0);
      expect(ext.heroCardRadius, 28.0);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.appBarTheme.backgroundColor, Colors.transparent);

      expect(GeminiDarkColors.bgTop, const Color(0xFF000000));
      expect(GeminiDarkColors.bgBottom, const Color(0xFF0A0E27));
      expect(GeminiDarkColors.surface, const Color(0xFF15161A));
      expect(GeminiDarkColors.surfaceAlt, const Color(0xFF1E1F24));
      expect(GeminiDarkColors.textPrimary, const Color(0xFFE8EAED));
      expect(GeminiDarkColors.textSecondary, const Color(0xFF9AA0A6));
      expect(GeminiDarkColors.accent, const Color(0xFF4285F4));
    });

    testWidgets('MidnightBackdropLayer uses RepaintBoundary & SurfaceCard is borderless 24/28dp', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.midnight(),
          builder: (context, child) => MidnightBackdropLayer(
            enabled: true,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const Scaffold(
            body: Column(
              children: [
                SurfaceCard(
                  key: ValueKey('normal_card'),
                  child: Text('Normal'),
                ),
                SurfaceCard(
                  key: ValueKey('hero_card'),
                  isHero: true,
                  child: Text('Hero'),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(MidnightBackdropLayer), findsOneWidget);
      expect(find.byType(RepaintBoundary), findsWidgets);

      final normalBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('normal_card')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final normalDeco = normalBox.decoration as BoxDecoration;
      expect(normalDeco.border, isNull);
      expect(normalDeco.borderRadius, BorderRadius.circular(24));

      final heroBox = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(const ValueKey('hero_card')),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      final heroDeco = heroBox.decoration as BoxDecoration;
      expect(heroDeco.border, isNull);
      expect(heroDeco.borderRadius, BorderRadius.circular(28));
    });
  });

  group('v3.1.2 Pace Curve calculation', () {
    test('returns empty for insufficient points or tiny distance', () {
      expect(computePaceCurveSamples(const []), isEmpty);
      expect(
        computePaceCurveSamples([
          const RoutePoint(lat: 20.96, lng: 105.94, t: 1000),
          const RoutePoint(lat: 20.96001, lng: 105.94, t: 5000),
        ]),
        isEmpty,
      );
    });

    test('computes accurate min/km pace curve distinguishing fast vs slow segments', () {
      final pts = _buildVariablePaceRoute();
      final samples = computePaceCurveSamples(pts);

      expect(samples.length, greaterThanOrEqualTo(4));
      // 前段配速约 5.0 min/km，后段约 7.0 min/km
      final firstPace = samples.first.paceMinPerKm;
      final lastPace = samples.last.paceMinPerKm;
      expect(firstPace, inInclusiveRange(4.2, 5.8));
      expect(lastPace, inInclusiveRange(6.2, 7.8));
      expect(firstPace, lessThan(lastPace));
      // 距离单调递增
      for (var i = 1; i < samples.length; i++) {
        expect(samples[i].km, greaterThan(samples[i - 1].km));
      }
    });
  });

  group('v3.1.2 RunDetailScreen Replay & Pace Chart', () {
    testWidgets('renders Replay button & fl_chart LineChart and honors disableAnimations', (tester) async {
      final pts = _buildVariablePaceRoute();
      final run = RunRecord(
        id: 1,
        date: '2026-11-20',
        startTime: pts.first.t,
        endTime: pts.last.t,
        durationSecs: 216,
        totalSecs: 216,
        distanceM: 600,
        avgPaceSecsPerKm: 360,
        caloriesKcal: 42,
        routeJson: RoutePoint.encodeList(pts),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.midnight(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunDetailScreen(
            run: run,
            initialSegments: const [],
            disableMapTilesForTest: true,
          ),
        ),
      );

      // 动画进行中应能看到回放按钮与配速曲线卡
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('run_detail_replay_btn')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('run_detail_pace_chart_card')),
        200,
      );
      expect(find.byKey(const ValueKey('run_detail_pace_chart_card')), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);

      // 等待回放动画结束并可再次触发回放
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('run_detail_replay_btn')),
        -300,
      );
      await tester.tap(find.byKey(const ValueKey('run_detail_replay_btn')));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      // 验证 disableAnimations=true 时无异常且立即完整显示
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.midnight(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: RunDetailScreen(
              run: run,
              initialSegments: const [],
              disableMapTilesForTest: true,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('run_detail_replay_btn')), findsOneWidget);
    });
  });
}

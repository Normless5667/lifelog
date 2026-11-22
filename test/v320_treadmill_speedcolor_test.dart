import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/models.dart';
import 'package:lifelog/models/run_models.dart';
import 'package:lifelog/screens/running/run_detail_screen.dart';
import 'package:lifelog/screens/running/running_active_screen.dart';
import 'package:lifelog/screens/running/treadmill_scan_screen.dart';
import 'package:lifelog/services/ai_service.dart';
import 'package:lifelog/services/app_prefs.dart';
import 'package:lifelog/services/nutrition.dart';
import 'package:lifelog/services/running_tracker.dart';
import 'package:lifelog/theme/app_theme.dart';
import 'package:lifelog/utils/route_speed_coloring.dart';

/// 构造多配速轨迹（前段慢走 >7:00，中段正常 5:30，后段快跑 4:20）
List<RoutePoint> _buildMultiPaceRoute() {
  const baseLat = 20.9628;
  const baseLng = 105.9410;
  const degPerMeterLat = 1.0 / 111195.0;
  final pts = <RoutePoint>[];
  var lat = baseLat;
  var t = 1760000000000;

  // 段 1: 慢走 ~8:00/km (2.08 m/s), 12 点，每 3 秒前进 6.25m
  for (var i = 0; i < 12; i++) {
    pts.add(RoutePoint(lat: lat, lng: baseLng, t: t, accuracy: 5.0));
    lat += 6.25 * degPerMeterLat;
    t += 3000;
  }
  // 段 2: 正常 ~5:30/km (3.03 m/s), 12 点，每 3 秒前进 9.1m
  for (var i = 0; i < 12; i++) {
    pts.add(RoutePoint(lat: lat, lng: baseLng, t: t, accuracy: 5.0));
    lat += 9.1 * degPerMeterLat;
    t += 3000;
  }
  // 段 3: 快跑 ~4:20/km (3.85 m/s), 12 点，每 3 秒前进 11.5m
  for (var i = 0; i < 12; i++) {
    pts.add(RoutePoint(lat: lat, lng: baseLng, t: t, accuracy: 5.0));
    lat += 11.5 * degPerMeterLat;
    t += 3000;
  }
  return pts;
}

void main() {
  group('v3.2.0 Treadmill Vision Parser & MET fallback', () {
    test('parses valid treadmill JSON and preserves null for unreadable fields', () {
      final res = AiService.parseTreadmillResponse('''
```json
{
  "distance_km": 5.2,
  "duration_secs": 1935,
  "calories": null,
  "pace": "6'12\\"/km",
  "machine_type": "treadmill"
}
```
''');
      expect(res.distanceKm, 5.2);
      expect(res.durationSecs, 1935);
      expect(res.calories, isNull); // 反光看不清绝不瞎猜
      expect(res.paceNote, '6\'12"/km');
      expect(res.machineType, CardioType.treadmill);
    });

    test('converts miles to km, notes conversion in raw, and parses MM:SS / HH:MM:SS', () {
      final res = AiService.parseTreadmillResponse('''
{
  "distance_mile": 3.10,
  "duration_secs": "32:15",
  "calories": 380,
  "pace": null,
  "machine_type": "elliptical"
}
''');
      expect(res.distanceKm, closeTo(4.99, 0.02));
      expect(res.raw, contains('Mile converted'));
      expect(res.durationSecs, 1935);
      expect(res.calories, 380);
      expect(res.paceNote, isNull);
      expect(res.machineType, CardioType.elliptical);

      expect(parseTreadmillDurationInput('1:05:20'), 3920);
      expect(parseTreadmillDurationInput('32:15'), 1935);
      expect(parseTreadmillDurationInput('30'), 1800);
    });

    test('Nutrition.estimateMachineCalories applies exact MET fallback values', () {
      // treadmill MET 8.0 * 65kg * 0.5h = 260
      expect(
        Nutrition.estimateMachineCalories(
          machineType: CardioType.treadmill,
          weightKg: 65,
          durationMinutes: 30,
        ),
        260.0,
      );
      // treadmill_fast MET 11.0 * 65kg * 0.5h = 357.5 -> 358
      expect(
        Nutrition.estimateMachineCalories(
          machineType: CardioType.treadmillFast,
          weightKg: 65,
          durationMinutes: 30,
        ),
        358.0,
      );
      // elliptical MET 5.0 * 65kg * 0.5h = 162.5 -> 163
      expect(
        Nutrition.estimateMachineCalories(
          machineType: CardioType.elliptical,
          weightKg: 65,
          durationMinutes: 30,
        ),
        163.0,
      );
      // bike MET 7.0 * 65kg * 0.5h = 227.5 -> 228
      expect(
        Nutrition.estimateMachineCalories(
          machineType: CardioType.bike,
          weightKg: 65,
          durationMinutes: 30,
        ),
        228.0,
      );
    });

    testWidgets('TreadmillScanScreen requires user confirmation/edit & saves as type treadmill with MET fallback',
        (tester) async {
      CardioRecord? saved;
      const scanRes = TreadmillScanResult(
        distanceKm: 5.20,
        durationSecs: 1935, // 32:15
        calories: null, // 模拟反光没读到热量 -> 触发 MET 兜底
        machineType: CardioType.treadmill,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: TreadmillScanScreen(
            weightKg: 65.0,
            initialResultForTest: scanRes,
            onSaveForTest: (rec) async => saved = rec,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('treadmill_confirm_form')), findsOneWidget);
      expect(find.byKey(const ValueKey('treadmill_met_fallback_note')), findsOneWidget);

      // 用户手动修正距离为 5.50 km、热量为 410 kcal 后保存
      await tester.enterText(find.byKey(const ValueKey('treadmill_dist_input')), '5.50');
      await tester.enterText(find.byKey(const ValueKey('treadmill_kcal_input')), '410');
      await tester.pump();

      await tester.ensureVisible(find.byKey(const ValueKey('treadmill_save_btn')));
      await tester.tap(find.byKey(const ValueKey('treadmill_save_btn')));
      await tester.pump();

      expect(saved, isNotNull);
      expect(saved!.type, CardioType.treadmill);
      expect(saved!.distanceKm, closeTo(5.50, 0.01));
      expect(saved!.durationMinutes, closeTo(32.25, 0.05));
      expect(saved!.calories, 410.0);
    });
  });

  group('v3.2.0 Route Speed Coloring Engine', () {
    test('5 pace zones match exact specification colors & thresholds', () {
      expect(PaceZoneStyle.fromPaceSecsPerKm(450), PaceZone.slowWalk);
      expect(PaceZone.slowWalk.color, const Color(0xFF90A4AE));
      expect(PaceZoneStyle.fromPaceSecsPerKm(390), PaceZone.jog);
      expect(PaceZone.jog.color, const Color(0xFF4DD0E1));
      expect(PaceZoneStyle.fromPaceSecsPerKm(330), PaceZone.normal);
      expect(PaceZone.normal.color, const Color(0xFF66BB6A));
      expect(PaceZoneStyle.fromPaceSecsPerKm(270), PaceZone.fast);
      expect(PaceZone.fast.color, const Color(0xFFFFA726));
      expect(PaceZoneStyle.fromPaceSecsPerKm(220), PaceZone.sprint);
      expect(PaceZone.sprint.color, const Color(0xFFEF5350));
    });

    test('30-min 3000-point run stays well under 400 segments & filters >200m GPS jumps without turning red', () {
      const baseLat = 20.9628;
      const baseLng = 105.9410;
      const degPerMeterLat = 1.0 / 111195.0;
      final pts = <RoutePoint>[];
      var lat = baseLat;
      var t = 1760000000000;

      // 3000 个点（模拟 30 分钟每 0.6s 一个点），正常配速 ~5:30/km（3.0 m/s）
      for (var i = 0; i < 3000; i++) {
        // 第 1000 个点注入一次 500 米 GPS 瞬移跳点
        if (i == 1000) {
          lat += 500.0 * degPerMeterLat;
        } else {
          lat += 1.8 * degPerMeterLat;
        }
        pts.add(RoutePoint(lat: lat, lng: baseLng, t: t, accuracy: 5.0));
        t += 600;
      }

      final segments = RouteSpeedColoring.buildSegments(pts);
      expect(segments, isNotEmpty);
      expect(segments.length, lessThanOrEqualTo(400));
      // 绝不能因为单次跳点出现冲刺红段
      expect(segments.any((s) => s.zone == PaceZone.sprint), isFalse);
    });

    test('multi-pace route produces distinct zones & sliceByProgress works cleanly', () {
      final pts = _buildMultiPaceRoute();
      final segments = RouteSpeedColoring.buildSegments(pts);
      final zones = segments.map((s) => s.zone).toSet();

      expect(zones.contains(PaceZone.slowWalk), isTrue);
      expect(zones.contains(PaceZone.normal), isTrue);
      expect(zones.contains(PaceZone.fast), isTrue);

      final half = RouteSpeedColoring.sliceByProgress(segments, 0.5);
      expect(half, isNotEmpty);
      expect(half.length, lessThanOrEqualTo(segments.length));
    });
  });

  group('v3.2.0 Speed-colored Map UI (Replay + Live Active)', () {
    testWidgets('RunDetailScreen shows 5-tier legend & toggles between speed-colored and monochrome',
        (tester) async {
      await AppPrefsController.instance.setRouteColorBySpeed(true);
      final pts = _buildMultiPaceRoute();
      final run = RunRecord(
        id: 2,
        date: '2026-11-22',
        startTime: pts.first.t,
        endTime: pts.last.t,
        durationSecs: 108,
        totalSecs: 108,
        distanceM: 320,
        avgPaceSecsPerKm: 338,
        caloriesKcal: 25,
        routeJson: RoutePoint.encodeList(pts),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
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

      // 默认速度分色：图例 5 档与切换胶囊均可见，且 PolylineLayer 含多条分色线
      expect(find.byKey(const ValueKey('route_speed_legend')), findsOneWidget);
      expect(find.text('慢走'), findsOneWidget);
      expect(find.text('慢跑'), findsOneWidget);
      expect(find.text('正常'), findsOneWidget);
      expect(find.text('快跑'), findsOneWidget);
      expect(find.text('冲刺'), findsOneWidget);
      final coloredLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(coloredLayer.polylines.length, greaterThanOrEqualTo(2));

      // 切换为单色轨迹 -> 图例隐藏，合并为 1 条单色 Polyline
      await tester.tap(find.byKey(const ValueKey('route_mode_mono_btn')));
      await tester.pump();
      expect(find.byKey(const ValueKey('route_speed_legend')), findsNothing);
      final monoLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(monoLayer.polylines.length, 1);

      // 切回速度分色 -> 图例重新出现
      await tester.tap(find.byKey(const ValueKey('route_mode_speed_btn')));
      await tester.pump();
      expect(find.byKey(const ValueKey('route_speed_legend')), findsOneWidget);
    });

    testWidgets('RunningActiveScreen renders live speed-colored polylines & legend as GPS updates',
        (tester) async {
      await AppPrefsController.instance.setRouteColorBySpeed(true);
      final ctrl = RunningTrackerController(weightKg: 65.0);
      await ctrl.start(skipPlatformSideEffects: true);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunningActiveScreen(
            weightKg: 65.0,
            controllerForTest: ctrl,
            disableMapTilesForTest: true,
          ),
        ),
      );
      await tester.pump();

      // 注入多配速实时点
      for (final p in _buildMultiPaceRoute()) {
        ctrl.injectRawPoint(p);
      }
      await tester.pump();

      expect(find.byKey(const ValueKey('route_color_mode_toggle')), findsOneWidget);
      expect(find.byKey(const ValueKey('route_speed_legend')), findsOneWidget);
      final liveLayer = tester.widget<PolylineLayer>(find.byType(PolylineLayer));
      expect(liveLayer.polylines.length, greaterThanOrEqualTo(2));

      ctrl.dispose();
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/models/run_models.dart';
import 'package:lifelog/screens/running/run_detail_screen.dart';
import 'package:lifelog/screens/running/running_active_screen.dart';
import 'package:lifelog/services/running_tracker.dart';
import 'package:lifelog/widgets/common.dart';

void main() {
  group('v3.1.0 Batch 1: GPS track filtering, smoothing & pause isolation', () {
    // 纬度 1 度 ≈ 111,195 m，10 米 ≈ 0.00008993 度
    const degPerMeterLat = 1.0 / 111195.0;
    const degPerMeterLngAt21 = 1.0 / 103800.0;

    test('1km clean & noisy GPS tracks stay within 5% accuracy and drop bad points/spikes', () {
      // 1) 干净的 1000m 直线跑（100 段 × 10m，每 3 秒一个点，速度 3.33 m/s）
      final clean = RunTrackProcessor();
      const baseLat = 20.9628;
      const baseLng = 105.9410;
      const baseT = 1760000000000;
      for (var i = 0; i <= 100; i++) {
        clean.addRawPoint(
          RoutePoint(
            lat: baseLat + i * 10.0 * degPerMeterLat,
            lng: baseLng,
            t: baseT + i * 3000,
            accuracy: 6.0,
          ),
          isPaused: false,
        );
      }
      final cleanErrPct = (clean.distanceMeters - 1000.0).abs() / 1000.0;
      expect(cleanErrPct, lessThan(0.05));

      // 2) 含精度差 (>20m)、瞬移跳点 (+150m/1s) 与 ±3.5m 横向漂移的 1000m 跑
      final noisy = RunTrackProcessor();
      for (var i = 0; i <= 100; i++) {
        // 每 10 步插入一个精度 35m 的坏点
        if (i > 0 && i % 10 == 0) {
          final okBad = noisy.addRawPoint(
            RoutePoint(
              lat: baseLat + i * 10.0 * degPerMeterLat + 45.0 * degPerMeterLat,
              lng: baseLng + 30.0 * degPerMeterLngAt21,
              t: baseT + i * 3000 - 500,
              accuracy: 35.0,
            ),
            isPaused: false,
          );
          expect(okBad, isFalse);
        }
        // 在第 50 步插入一个 150m 瞬移跳点（accuracy 虽好但速度 > 12.5 m/s）
        if (i == 50) {
          final okSpike = noisy.addRawPoint(
            RoutePoint(
              lat: baseLat + (i * 10.0 + 150.0) * degPerMeterLat,
              lng: baseLng,
              t: baseT + (i - 1) * 3000 + 1000,
              accuracy: 8.0,
            ),
            isPaused: false,
          );
          expect(okSpike, isFalse);
        }

        final lateralJitterM = (i == 0 || i == 100) ? 0.0 : (i.isEven ? 3.5 : -3.5);
        noisy.addRawPoint(
          RoutePoint(
            lat: baseLat + i * 10.0 * degPerMeterLat,
            lng: baseLng + lateralJitterM * degPerMeterLngAt21,
            t: baseT + i * 3000,
            accuracy: 8.0,
          ),
          isPaused: false,
        );
      }

      expect(noisy.droppedAccuracyCount, 10);
      expect(noisy.droppedSpikeCount, 1);
      final noisyErrPct = (noisy.distanceMeters - 1000.0).abs() / 1000.0;
      expect(noisyErrPct, lessThan(0.05));
    });

    test('pause/resume NEVER counts travel during pause into distance and splits segments', () {
      final proc = RunTrackProcessor();
      const baseLat = 20.9628;
      const baseLng = 105.9410;
      const baseT = 1760000000000;

      // 第一段跑 200m
      for (var i = 0; i <= 20; i++) {
        proc.addRawPoint(
          RoutePoint(
            lat: baseLat + i * 10.0 * degPerMeterLat,
            lng: baseLng,
            t: baseT + i * 3000,
            accuracy: 6.0,
          ),
          isPaused: false,
        );
      }
      final distBeforePause = proc.distanceMeters;
      expect(distBeforePause, inInclusiveRange(190.0, 210.0));

      // 暂停并移动 800m（期间即使有回调也必须忽略）
      proc.markPauseBreak();
      expect(
        proc.addRawPoint(
          RoutePoint(
            lat: baseLat + 600.0 * degPerMeterLat,
            lng: baseLng,
            t: baseT + 120000,
            accuracy: 5.0,
          ),
          isPaused: true,
        ),
        isFalse,
      );

      // 恢复后从 +1000m 处继续跑 200m
      for (var i = 0; i <= 20; i++) {
        proc.addRawPoint(
          RoutePoint(
            lat: baseLat + (1000.0 + i * 10.0) * degPerMeterLat,
            lng: baseLng,
            t: baseT + 300000 + i * 3000,
            accuracy: 6.0,
          ),
          isPaused: false,
        );
      }

      // 总距离只含两段 200m ≈ 400m，绝不含暂停期间的 800m 跨越
      expect(proc.segments.length, 2);
      expect(proc.distanceMeters, inInclusiveRange(380.0, 420.0));
    });

    test('route_json round-trip & assets/running_courses.json loads all 8 courses', () async {
      final pts = const [
        RoutePoint(lat: 20.962801, lng: 105.941002, t: 1760000000000),
        RoutePoint(lat: 20.963001, lng: 105.941102, t: 1760000005000),
      ];
      final encoded = RoutePoint.encodeList(pts);
      final decoded = RoutePoint.decodeList(encoded);
      expect(decoded.length, 2);
      expect(decoded.first.lat, closeTo(20.962801, 1e-6));
      expect(decoded.last.t, 1760000005000);

      final raw = File('assets/running_courses.json').readAsStringSync();
      final courses = await RunningCourseCatalog.loadAll(overrideRawJson: raw);
      expect(courses.length, 11);
      expect(courses.any((c) => c.id == 'free_run' && c.isFree), isTrue);
      expect(courses.any((c) => c.id == 'fartlek_3k'), isTrue);
      expect(courses.any((c) => c.id == 'fartlek_5k'), isTrue);
      expect(courses.any((c) => c.id == 'fartlek_10k'), isTrue);
      expect(courses.any((c) => c.id == 'distance_3k' && c.isDistanceCourse), isTrue);
      expect(courses.any((c) => c.id == 'distance_5k' && c.isDistanceCourse), isTrue);
      expect(courses.any((c) => c.id == 'distance_10k' && c.isDistanceCourse), isTrue);
      final intervals = courses.firstWhere((c) => c.id == 'interval_5x400');
      expect(intervals.segments.any((s) => s.isDistanceBased && s.durationMeters == 400), isTrue);
    });
  });

  group('v3.1.0 Batch 1: RunningActiveScreen & RunDetailScreen widget tests', () {
    testWidgets('tracks live points, handles pause/resume, saves route_json & opens RunDetailScreen',
        (tester) async {
      final ctrl = RunningTrackerController(weightKg: 70.0);
      await ctrl.start(skipPlatformSideEffects: true);
      RunRecord? savedRun;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: RunningActiveScreen(
            weightKg: 70.0,
            controllerForTest: ctrl,
            disableMapTilesForTest: true,
            onSaveRunOverrideForTest: (r, _) async {
              savedRun = r;
              return 42;
            },
          ),
        ),
      );
      await tester.pump();

      // OSM 版权标注必须可见
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

      // 模拟注入 30 个 GPS 点（300m）
      const degPerMeterLat = 1.0 / 111195.0;
      const baseT = 1760000000000;
      for (var i = 0; i <= 30; i++) {
        ctrl.injectRawPoint(
          RoutePoint(
            lat: 20.9628 + i * 10.0 * degPerMeterLat,
            lng: 105.9410,
            t: baseT + i * 3000,
            accuracy: 6.0,
          ),
        );
      }
      await tester.pump();

      expect(ctrl.distanceMeters, greaterThan(285.0));
      expect(find.byKey(const ValueKey('run_metric_distance_val')), findsOneWidget);

      // 点击暂停 -> 按钮变为「继续」，期间注入点不增加距离
      final distWhenPaused = ctrl.distanceMeters;
      await tester.tap(find.byKey(const ValueKey('run_pause_resume_btn')));
      await tester.pump();
      expect(find.text('继续'), findsOneWidget);
      ctrl.injectRawPoint(
        const RoutePoint(lat: 20.9800, lng: 105.9500, t: baseT + 200000, accuracy: 5.0),
      );
      expect(ctrl.distanceMeters, distWhenPaused);

      // 点击结束 -> 确认保存 -> 跳转 RunDetailScreen 并还原轨迹 PolylineLayer
      await tester.tap(find.byKey(const ValueKey('run_finish_btn')));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byKey(const ValueKey('run_confirm_save_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(savedRun, isNotNull);
      expect(savedRun!.distanceM, closeTo(distWhenPaused, 0.1));
      expect(savedRun!.caloriesKcal, greaterThan(0));
      expect(savedRun!.decodeRoute().length, greaterThanOrEqualTo(2));
      expect(find.byType(RunDetailScreen), findsOneWidget);
      expect(find.byType(PolylineLayer), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

      ctrl.dispose();
    });
  });
}

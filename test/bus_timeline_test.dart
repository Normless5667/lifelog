import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lifelog/l10n/app_localizations.dart';
import 'package:lifelog/services/bus_service.dart';
import 'package:lifelog/utils/l10n_ext.dart';

void main() {
  late BusRouteData buvRoute;

  setUpAll(() {
    final raw = File('assets/bus_routes.json').readAsStringSync();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final list = j['routes'] as List;
    buvRoute = BusRouteData.fromJson(
      Map<String, dynamic>.from(list.first as Map),
      overrideSource: 'builtin',
    );
  });

  group('BusService forward segment & monotonic BusTrip guards', () {
    test('duplicate stop name SKY OASIS -> BUV CAMPUS picks final arrival (08:28 -> 08:40)', () {
      final seg = BusService.filterForwardSegmentStops(
        buvRoute.outboundStops,
        'SKY OASIS',
        'BUV CAMPUS',
      );
      expect(seg.length, greaterThanOrEqualTo(2));
      expect(seg.first.name, 'SKY OASIS');
      expect(seg.last.name, contains('BUV CAMPUS'));

      final refDay = DateTime(2026, 11, 19, 9, 17); // Thursday
      final trips = BusService.buildTripsForSegment(seg, refDay);
      expect(trips.length, 5);
      for (final trip in trips) {
        expect(trip.firstTime.day, refDay.day);
        expect(trip.lastTime.day, refDay.day);
        for (var i = 0; i < trip.times.length - 1; i++) {
          expect(
            !trip.times[i + 1].isBefore(trip.times[i]),
            isTrue,
            reason: '${trip.slotName} stop $i time went backwards',
          );
        }
      }
      expect(trips.first.firstTime, DateTime(2026, 11, 19, 8, 28));
      expect(trips.first.lastTime, DateTime(2026, 11, 19, 8, 40));
    });

    test('reverse loop stop order LANDMARK -> SKY FOREST returns empty instead of reversing time', () {
      final outSeg = BusService.filterForwardSegmentStops(
        buvRoute.outboundStops,
        'LANDMARK',
        'SKY FOREST',
      );
      final inSeg = BusService.filterForwardSegmentStops(
        buvRoute.inboundStops,
        'LANDMARK',
        'SKY FOREST',
      );
      expect(outSeg, isEmpty);
      expect(inSeg, isEmpty);
    });
  });

  group('BUGFIX_bus_timeline.md time matrix verification', () {
    List<BusStopSchedule> fullOutbound() => BusService.filterForwardSegmentStops(
          buvRoute.outboundStops,
          'LE DAI HANH',
          'BUV CAMPUS',
        );

    test('09:17 Thursday (between Slot 1 and Slot 2) -> NO bus en route, next trip <= 180m', () {
      final now = DateTime(2026, 11, 19, 9, 17); // Thursday
      final seg = fullOutbound();
      final trips = BusService.buildTripsForSegment(seg, now);

      for (final trip in trips) {
        final eval = BusService.evaluateTripAt(
          trip,
          now,
          isWeekend: false,
          allEndedToday: false,
        );
        expect(eval.isEnRoute, isFalse, reason: '${trip.slotName} should not be en route at 09:17');
        expect(eval.activeSegIdx, isNull);
        expect(eval.currentStopIdx, isNull);
      }

      // Slot 2 (09:40 -> 10:40) starts in 23 minutes (well within <= 180m cap)
      final remainMins = trips[1].firstTime.difference(now).inMinutes;
      expect(remainMins, 23);
      expect(remainMins, lessThanOrEqualTo(BusService.maxCountdownMinutes));
    });

    test('09:17 Thursday from LANDMARK -> BUV CAMPUS (Slot 2 at 10:30) -> NO 1392 min, NO 3%', () {
      final now = DateTime(2026, 11, 19, 9, 17);
      final seg = BusService.filterForwardSegmentStops(
        buvRoute.outboundStops,
        'LANDMARK',
        'BUV CAMPUS',
      );
      final trips = BusService.buildTripsForSegment(seg, now);
      for (final trip in trips) {
        final eval = BusService.evaluateTripAt(
          trip,
          now,
          isWeekend: false,
          allEndedToday: false,
        );
        expect(eval.isEnRoute, isFalse);
        expect(eval.activeSegIdx, isNull);
      }
      // Slot 2 departs LANDMARK at 10:30 -> 73 mins away
      expect(trips[1].firstTime.difference(now).inMinutes, 73);
    });

    test('10:00 Thursday (Slot 2 running 09:40 -> 10:40) -> active between TIMES CITY and AEON MALL', () {
      final now = DateTime(2026, 11, 19, 10, 0);
      final seg = fullOutbound();
      final trips = BusService.buildTripsForSegment(seg, now);

      final eval2 = BusService.evaluateTripAt(
        trips[1],
        now,
        isWeekend: false,
        allEndedToday: false,
      );
      expect(eval2.isEnRoute, isTrue);
      expect(eval2.activeSegIdx, 1); // between [1] TIMES CITY (09:55) and [2] AEON MALL (10:05)
      expect(eval2.segProgress, closeTo(0.5, 0.001));
      expect(eval2.tripProgress, closeTo(20 / 60, 0.001));
    });

    test('08:35 Thursday (Slot 1 running 07:40 -> 08:40) -> past first stop, progress > 0', () {
      final now = DateTime(2026, 11, 19, 8, 35);
      final seg = fullOutbound();
      final trips = BusService.buildTripsForSegment(seg, now);

      final eval1 = BusService.evaluateTripAt(
        trips[0],
        now,
        isWeekend: false,
        allEndedToday: false,
      );
      expect(eval1.isEnRoute, isTrue);
      expect(eval1.activeSegIdx, greaterThan(0));
      expect(eval1.tripProgress, greaterThan(0.8));
      expect(eval1.tripProgress, lessThan(1.0));
    });

    test('14:40 Thursday: active Slot 5 route is en route with valid progress; BUV outbound ended', () {
      final now = DateTime(2026, 11, 19, 14, 40);
      final customStops = const [
        BusStopSchedule(name: 'Stop A', times: ['14:20']),
        BusStopSchedule(name: 'Stop B', times: ['15:00']),
      ];
      final customTrips = BusService.buildTripsForSegment(customStops, now);
      final evalCustom = BusService.evaluateTripAt(
        customTrips.first,
        now,
        isWeekend: false,
        allEndedToday: false,
      );
      expect(evalCustom.isEnRoute, isTrue);
      expect(evalCustom.activeSegIdx, 0);
      expect(evalCustom.tripProgress, closeTo(0.5, 0.001));

      final buvOutTrips = BusService.buildTripsForSegment(fullOutbound(), now);
      for (final trip in buvOutTrips) {
        expect(
          BusService.evaluateTripAt(trip, now, isWeekend: false, allEndedToday: true).isEnRoute,
          isFalse,
        );
      }
    });

    test('15:00 Thursday outbound all ended -> NO bus en route', () {
      final now = DateTime(2026, 11, 19, 15, 0);
      final trips = BusService.buildTripsForSegment(fullOutbound(), now);
      for (final trip in trips) {
        final eval = BusService.evaluateTripAt(
          trip,
          now,
          isWeekend: false,
          allEndedToday: true,
        );
        expect(eval.isEnRoute, isFalse);
        expect(eval.activeSegIdx, isNull);
      }
    });

    test('Saturday 08:35 & 10:00 weekend -> NO bus drawn even inside weekday time window', () {
      final satMorning = DateTime(2026, 11, 21, 8, 35); // Saturday
      final trips = BusService.buildTripsForSegment(fullOutbound(), satMorning);
      final eval = BusService.evaluateTripAt(
        trips[0],
        satMorning,
        isWeekend: true,
        allEndedToday: false,
      );
      expect(eval.isEnRoute, isFalse);
      expect(eval.activeSegIdx, isNull);
      expect(eval.currentStopIdx, isNull);
    });
  });

  group('Home summary computeNextBusSummary direction filtering & fallback', () {
    test('morning 09:17 filters outbound only (TIMES CITY -> 09:55)', () {
      final now = DateTime(2026, 11, 19, 9, 17);
      final isInbound = BusService.inferDefaultIsInbound(buvRoute, 'TIMES CITY', now);
      expect(isInbound, isFalse);
      final s = BusService.computeNextBusSummary(buvRoute, 'TIMES CITY', now, isInbound: isInbound);
      expect(s.nextTime, '09:55');
      expect(s.minutesUntil, 38);
      expect(s.direction, buvRoute.outboundTitle);
    });

    test('afternoon 14:40 filters inbound only (TIMES CITY -> 15:55)', () {
      final now = DateTime(2026, 11, 19, 14, 40);
      final isInbound = BusService.inferDefaultIsInbound(buvRoute, 'TIMES CITY', now);
      expect(isInbound, isTrue);
      final s = BusService.computeNextBusSummary(buvRoute, 'TIMES CITY', now, isInbound: isInbound);
      expect(s.nextTime, '15:55');
      expect(s.minutesUntil, 75);
      expect(s.direction, buvRoute.inboundTitle);
    });

    test('ended today (19:00) uses first bus of CURRENT direction, not hardcoded outbound', () {
      final now = DateTime(2026, 11, 19, 19, 0);
      final sIn = BusService.computeNextBusSummary(buvRoute, 'TIMES CITY', now, isInbound: true);
      expect(sIn.minutesUntil, -1);
      expect(sIn.nextTime, '12:10'); // First inbound at TIMES CITY
      expect(sIn.direction, contains('12:10'));

      final sOut = BusService.computeNextBusSummary(buvRoute, 'TIMES CITY', now, isInbound: false);
      expect(sOut.minutesUntil, -1);
      expect(sOut.nextTime, '07:55'); // First outbound at TIMES CITY
      expect(sOut.direction, contains('07:55'));
    });

    testWidgets('Home summary hides countdown when > 180 min (>3h cap) and shows when <= 180 min', (tester) async {
      late String zhOver3h;
      late String zhUnder3h;
      late String enOver3h;
      late String zhWeekend;
      late String zhEnded;

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('zh'),
          home: Builder(
            builder: (context) {
              zhOver3h = L10nHelper.busDirectionSummary(
                context,
                rawDirection: '回程',
                nextTime: '11:30',
                minutesUntil: 210,
                isWeekend: false,
              );
              zhUnder3h = L10nHelper.busDirectionSummary(
                context,
                rawDirection: '去程',
                nextTime: '09:55',
                minutesUntil: 38,
                isWeekend: false,
              );
              zhWeekend = L10nHelper.busDirectionSummary(
                context,
                rawDirection: '周末无班次',
                nextTime: '--:--',
                minutesUntil: -1,
                isWeekend: true,
              );
              zhEnded = L10nHelper.busDirectionSummary(
                context,
                rawDirection: '今日已结束',
                nextTime: '07:55',
                minutesUntil: -1,
                isWeekend: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) {
              enOver3h = L10nHelper.busDirectionSummary(
                context,
                rawDirection: 'Outbound',
                nextTime: '07:40',
                minutesUntil: 430,
                isWeekend: false,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(zhOver3h, contains('11:30'));
      expect(zhOver3h.contains('210'), isFalse);
      expect(zhUnder3h, contains('38'));
      expect(zhUnder3h, contains('09:55'));
      expect(enOver3h, contains('07:40'));
      expect(enOver3h.contains('430'), isFalse);
      expect(zhWeekend, isNotEmpty);
      expect(zhEnded, contains('07:55'));
    });
  });
}

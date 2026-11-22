import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/run_models.dart';
import '../services/running_tracker.dart';

/// 跑步轨迹五档配速色阶（按跑者习惯以配速分档，非原始速度）：
/// - > 7:00/km  : 蓝灰 #90A4AE（慢走）
/// - 6:00~7:00  : 青   #4DD0E1（慢跑）
/// - 5:00~6:00  : 绿   #66BB6A（正常）
/// - 4:00~5:00  : 橙   #FFA726（快跑）
/// - < 4:00/km  : 红   #EF5350（冲刺）
enum PaceZone {
  slowWalk,
  jog,
  normal,
  fast,
  sprint,
}

extension PaceZoneStyle on PaceZone {
  Color get color => switch (this) {
        PaceZone.slowWalk => const Color(0xFF90A4AE),
        PaceZone.jog => const Color(0xFF4DD0E1),
        PaceZone.normal => const Color(0xFF66BB6A),
        PaceZone.fast => const Color(0xFFFFA726),
        PaceZone.sprint => const Color(0xFFEF5350),
      };

  static PaceZone fromPaceSecsPerKm(double paceSecsPerKm) {
    if (!paceSecsPerKm.isFinite || paceSecsPerKm > 420.0) {
      return PaceZone.slowWalk;
    }
    if (paceSecsPerKm > 360.0) return PaceZone.jog;
    if (paceSecsPerKm > 300.0) return PaceZone.normal;
    if (paceSecsPerKm >= 240.0) return PaceZone.fast;
    return PaceZone.sprint;
  }
}

/// 聚合后的同色轨迹段（每段可包含多个连续点，保证 Polyline 总数始终 <= 400）
class ColoredRouteSegment {
  final List<LatLng> points;
  final PaceZone zone;
  final double avgPaceSecsPerKm;

  const ColoredRouteSegment({
    required this.points,
    required this.zone,
    required this.avgPaceSecsPerKm,
  });

  Color get color => zone.color;
}

/// 轨迹按配速分色计算引擎：
/// 1) 过滤相邻距离 > 200m 的 GPS 跳点与非法时间间隔（断开不连线）
/// 2) 滑动窗口（前后各 2 个点，共 5 点窗口）计算平滑速度，消除 GPS 瞬时抖动全红毛刺
/// 3) 同档相邻点聚合成一条多点 Polyline，并按目标上限（默认 300，严格 <= 400）压缩段数，
///    确保 30 分钟数千点轨迹依然流畅不卡顿
class RouteSpeedColoring {
  RouteSpeedColoring._();

  static const double maxAdjacentJumpMeters = 200.0;
  static const double maxSingleStepSpeedMps = 12.5; // ~45 km/h 瞬移过滤
  static const int defaultWindowRadius = 2; // 前后各 2 个点
  static const int defaultMaxSegments = 300; // 目标 200-400 以内

  /// 从单条轨迹点列表生成配速分色段集合
  static List<ColoredRouteSegment> buildSegments(
    List<RoutePoint> points, {
    int maxSegments = defaultMaxSegments,
    int windowRadius = defaultWindowRadius,
  }) {
    if (points.length < 2) return const [];

    // Step 1: 按跳点 (>200m) / 暂停断档 (>60s) 切分为连续子链
    final chains = <List<RoutePoint>>[];
    var current = <RoutePoint>[points.first];
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final cur = points[i];
      final dtSec = (cur.t - prev.t) / 1000.0;
      final distM = haversineMeters(prev.lat, prev.lng, cur.lat, cur.lng);
      if (dtSec <= 0 || dtSec > 60.0 || distM > maxAdjacentJumpMeters) {
        if (current.length >= 2) chains.add(current);
        current = <RoutePoint>[cur];
      } else {
        current.add(cur);
      }
    }
    if (current.length >= 2) chains.add(current);
    if (chains.isEmpty) return const [];

    // Step 2: 对长轨迹按步长适度抽稀，控制总边数在合理规模内再算滑动窗口
    final totalPts = chains.fold<int>(0, (s, c) => s + c.length);
    final stride = totalPts > 800 ? math.max(1, (totalPts / 600).floor()) : 1;

    final segments = <ColoredRouteSegment>[];
    for (final rawChain in chains) {
      final chain = stride > 1 ? _downsampleChain(rawChain, stride) : rawChain;
      if (chain.length < 2) continue;

      final edgeCount = chain.length - 1;
      final edgeZones = List<PaceZone>.filled(edgeCount, PaceZone.normal);
      final edgePaces = List<double>.filled(edgeCount, 360.0);

      for (var e = 0; e < edgeCount; e++) {
        final pace = _windowPaceSecsPerKm(chain, e, windowRadius);
        edgePaces[e] = pace;
        edgeZones[e] = PaceZoneStyle.fromPaceSecsPerKm(pace);
      }

      // 轻度去孤立单边毛刺：若 A - B - A 夹心单边，平滑为 A，减少无意义切段
      if (edgeCount >= 3) {
        for (var e = 1; e < edgeCount - 1; e++) {
          if (edgeZones[e - 1] == edgeZones[e + 1] &&
              edgeZones[e] != edgeZones[e - 1]) {
            edgeZones[e] = edgeZones[e - 1];
            edgePaces[e] = (edgePaces[e - 1] + edgePaces[e + 1]) / 2.0;
          }
        }
      }

      // Step 3: 聚合连续同档边为一条多点 Polyline（共享端点无缝衔接）
      var runZone = edgeZones[0];
      var runPts = <LatLng>[
        LatLng(chain[0].lat, chain[0].lng),
        LatLng(chain[1].lat, chain[1].lng),
      ];
      var paceSum = edgePaces[0];
      var paceCount = 1;

      for (var e = 1; e < edgeCount; e++) {
        final nextPt = LatLng(chain[e + 1].lat, chain[e + 1].lng);
        if (edgeZones[e] == runZone) {
          runPts.add(nextPt);
          paceSum += edgePaces[e];
          paceCount++;
        } else {
          segments.add(ColoredRouteSegment(
            points: runPts,
            zone: runZone,
            avgPaceSecsPerKm: paceSum / paceCount,
          ));
          runZone = edgeZones[e];
          runPts = <LatLng>[
            LatLng(chain[e].lat, chain[e].lng),
            nextPt,
          ];
          paceSum = edgePaces[e];
          paceCount = 1;
        }
      }
      segments.add(ColoredRouteSegment(
        points: runPts,
        zone: runZone,
        avgPaceSecsPerKm: paceSum / paceCount,
      ));
    }

    // Step 4: 硬上限兜底，保证 segment 总数绝不超过 maxSegments（默认 300，严格 <= 400）
    return _capSegmentCount(segments, maxSegments);
  }

  /// 从跑步中按暂停切分的多段轨迹生成实时配速分色段（不跨越暂停连线）
  static List<ColoredRouteSegment> buildFromTrackSegments(
    List<List<RoutePoint>> trackSegments, {
    int maxSegments = defaultMaxSegments,
  }) {
    final nonEmpty = [
      for (final seg in trackSegments)
        if (seg.length >= 2) seg,
    ];
    if (nonEmpty.isEmpty) return const [];
    final perSegCap = math.max(10, maxSegments ~/ nonEmpty.length);
    final out = <ColoredRouteSegment>[];
    for (final seg in nonEmpty) {
      out.addAll(buildSegments(seg, maxSegments: perSegCap));
    }
    return _capSegmentCount(out, maxSegments);
  }

  /// 按回放进度 [0.0, 1.0] 截取分色轨迹段（在末端做线性插值，实现分色一笔画平滑回放）
  static List<ColoredRouteSegment> sliceByProgress(
    List<ColoredRouteSegment> segments,
    double progress,
  ) {
    if (segments.isEmpty) return const [];
    if (progress >= 0.999) return segments;
    final p = progress.clamp(0.0, 1.0);

    var totalEdges = 0;
    for (final s in segments) {
      totalEdges += math.max(0, s.points.length - 1);
    }
    if (totalEdges <= 0) return const [];

    final target = p * totalEdges;
    var consumed = 0;
    final out = <ColoredRouteSegment>[];

    for (final seg in segments) {
      final segEdges = seg.points.length - 1;
      if (segEdges <= 0) continue;
      if (consumed + segEdges <= target) {
        out.add(seg);
        consumed += segEdges;
        continue;
      }
      final rem = target - consumed;
      if (rem <= 0) break;
      final fullIdx = rem.floor().clamp(0, segEdges - 1);
      final frac = rem - fullIdx;
      final a = seg.points[fullIdx];
      final b = seg.points[fullIdx + 1];
      final head = LatLng(
        a.latitude + (b.latitude - a.latitude) * frac,
        a.longitude + (b.longitude - a.longitude) * frac,
      );
      final sliced = [...seg.points.sublist(0, fullIdx + 1), head];
      if (sliced.length >= 2) {
        out.add(ColoredRouteSegment(
          points: sliced,
          zone: seg.zone,
          avgPaceSecsPerKm: seg.avgPaceSecsPerKm,
        ));
      }
      break;
    }
    return out;
  }

  static List<RoutePoint> _downsampleChain(List<RoutePoint> chain, int stride) {
    final out = <RoutePoint>[];
    for (var i = 0; i < chain.length; i += stride) {
      out.add(chain[i]);
    }
    if (out.last != chain.last) {
      out.add(chain.last);
    }
    return out;
  }

  /// 滑动窗口（中心边 e 前后各 windowRadius 个点）计算平滑配速（秒/公里）
  static double _windowPaceSecsPerKm(
    List<RoutePoint> chain,
    int edgeIndex,
    int windowRadius,
  ) {
    final lo = math.max(0, edgeIndex - windowRadius);
    final hi = math.min(chain.length - 1, edgeIndex + 1 + windowRadius);
    double sumDist = 0;
    double sumSec = 0;

    for (var i = lo; i < hi; i++) {
      final a = chain[i];
      final b = chain[i + 1];
      final dt = (b.t - a.t) / 1000.0;
      if (dt <= 0) continue;
      final d = haversineMeters(a.lat, a.lng, b.lat, b.lng);
      if (d > maxAdjacentJumpMeters) continue;
      final stepSpeed = d / dt;
      // 丢弃单步 GPS 爆表毛刺（> 12.5 m/s ≈ 45 km/h）
      if (stepSpeed > maxSingleStepSpeedMps) continue;
      sumDist += d;
      sumSec += dt;
    }

    if (sumSec <= 0 || sumDist < 0.5) {
      return 600.0; // 近乎静止 -> 归入慢走档
    }
    final avgSpeedMps = sumDist / sumSec;
    if (avgSpeedMps <= 0.1) return 600.0;
    return 1000.0 / avgSpeedMps;
  }

  static List<ColoredRouteSegment> _capSegmentCount(
    List<ColoredRouteSegment> input,
    int maxSegments,
  ) {
    if (input.length <= maxSegments) return input;
    final list = List<ColoredRouteSegment>.from(input);
    while (list.length > maxSegments) {
      // 找点数最少的连续相邻对（端点相连）进行合并
      var bestIdx = -1;
      var bestWeight = 1 << 30;
      for (var i = 0; i < list.length - 1; i++) {
        final a = list[i];
        final b = list[i + 1];
        final connected = a.points.last == b.points.first;
        if (!connected) continue;
        final w = a.points.length + b.points.length;
        if (w < bestWeight) {
          bestWeight = w;
          bestIdx = i;
        }
      }
      if (bestIdx < 0) break;
      final a = list[bestIdx];
      final b = list[bestIdx + 1];
      final dominant = a.points.length >= b.points.length ? a : b;
      final mergedPts = <LatLng>[...a.points, ...b.points.skip(1)];
      list[bestIdx] = ColoredRouteSegment(
        points: mergedPts,
        zone: dominant.zone,
        avgPaceSecsPerKm: (a.avgPaceSecsPerKm + b.avgPaceSecsPerKm) / 2.0,
      );
      list.removeAt(bestIdx + 1);
    }
    return list;
  }
}

# P0 Bug：校车时间轴把「所有班次」当成一条连续时间线

> 实测时间 2026-11-19 09:17（周四）
> 现象：Slot 1（08:30 发车）的班次早该结束了，界面却显示「车在这里 · 行驶中 (3%)」，
> 车图标停在 LANDMARK（08:30）那一站；下面的 SKY FOREST 显示「还有 1392 分」（≈23 小时）。

---

## 一、根因（已定位到具体行）

### 问题代码
`lib/screens/schedule/bus_schedule_screen.dart` 第 1399-1425 行：

```dart
if (!allEndedToday && stopTimes.length >= 2) {
  if (!now.isBefore(stopTimes.first) && now.isBefore(stopTimes.last)) {
    for (var k = 0; k < stopTimes.length - 1; k++) {
      final t1 = stopTimes[k];
      final t2 = stopTimes[k + 1];
      if (!now.isBefore(t1) && now.isBefore(t2)) {
        activeSegIdx = k;
        segProgress = calcBusSegmentProgress(now, t1, t2);
        ...
      }
    }
  }
}
```

### 为什么错
`stopTimes` 是把**当前方向所有班次的所有站点时间**按顺序摊平成一个 list，
例如（去程）：
```
08:30 LANDMARK, 08:28 SKY OASIS, 08:28 SOL FOREST, 08:29 SKY FOREST, ...
08:30 LANDMARK, 10:28 SKY OASIS, ...(Slot2)
13:30 LANDMARK, 14:30 BUV CAMPUS (Slot5 末站)
```

这段代码把整条 list 当**一条连续的时间线**，只要 `now` 落在
「首元素」和「末元素」之间，就认为「有车在路上」，然后在 list 里找夹住 `now`
的那两个相邻元素，算插值。

**9:17 确实在 08:30 和 14:30 之间，所以它算出「有车」，然后正好夹在
08:29 SKY FOREST 和 08:30 LANDMARK 之间 → 3% 进度 → 车卡在第一站。**

实际上 08:30 那班早就到终点了，9:17 根本没有车。

### 附带的一个数据问题
截图里 SKY FOREST 是 08:29、SOL FOREST 是 08:28、SKY OASIS 是 08:28，
但时刻表原文是 SKY OASIS 08:28 → SOL FOREST 08:28 → SKY FOREST 08:29（递增）。
如果 `stopTimes` 是**按站点顺序排列的**，那时间本不该递减；这说明
`stopTimes` 的构造里把 `origin` 和 `stops` 的拼接顺序搞反了，
或者方向反了仍按原顺序升序排。

**顺带查一下 `stopTimes` 的构造**——它应该保证「同一趟车，站点按行进顺序，
时间单调不减」。

---

## 二、正确的模型

### 关键认知
**「一条线路」不等于「一趟车」。** 一条线路有 5 个 Slot（5 趟车），
每趟车有自己的一条时间序列。**Slot 之间是独立的**，不能连成一条线。

### 正确做法

```dart
// 1. 先把当前方向的所有班次拆成一个个「trip」
class Trip {
  final String slotName;      // "Slot 1"
  final List<DateTime> times; // 这一趟的各站时间，按站点顺序，单调不减
}

// 2. 找「当前正在跑的那一趟」
Trip? activeTrip;
for (final trip in trips) {
  if (trip.times.isEmpty) continue;
  final first = trip.times.first;   // 首站发车
  final last = trip.times.last;     // 末站到达
  if (!now.isBefore(first) && !now.isAfter(last)) {
    activeTrip = trip;
    break;
  }
}

// 3. 只有存在 activeTrip 才算「行驶中」
if (activeTrip != null) {
  // 在 activeTrip.times 里找夹住 now 的区间，算进度
  for (var k = 0; k < activeTrip.times.length - 1; k++) {
    final t1 = activeTrip.times[k];
    final t2 = activeTrip.times[k + 1];
    if (!now.isBefore(t1) && now.isBefore(t2)) {
      activeSegIdx = k;
      segProgress = calcBusSegmentProgress(now, t1, t2);
      break;
    }
  }
} else {
  // 没有车在路上：不要显示任何进度条、不要显示车图标
  // 状态显示「无行驶中的班次」，或者「下一班 XX:XX」
}
```

### 关键点
1. **`stopTimes` 必须按 trip 拆开，不能再摊平成一个 list**
2. **判据改成 `now` 落在某趟车的 `[first, last]` 区间内**——不是所有班次的首尾
3. **没有活跃 trip 时，`activeSegIdx` 保持 null**，UI 要能正确处理 null（不画车）
4. **`segProgress` 只在有活跃 trip 时才计算**

---

## 三、「还有 1392 分」也要修

### 现在的算法（推测）
用 `target - now` 直接算，结果是负数（already passed），
负数被某种方式转成了「明天同一时间」，于是变成了 1392 分钟。

### 正确做法
对每个站点的倒计时，**只在它属于「当前或未来还没到达的那一趟」时才显示**：

```dart
// 对某个站点的下一次到达时间：
DateTime? nextArrival(trip, stopIdx, now) {
  final t = trip.times[stopIdx];
  if (t.isAfter(now)) return t;          // 还没到，就这趟
  return null;                            // 已经过了，不算倒计时
}
```

如果当前没有活跃 trip，就显示**下一趟**该站的到达时间：
```
不是「还有 1392 分」，而是「明日 08:28」或「下一班 10:28」
```

**超过某个阈值（比如 3 小时）就不要显示「还有 N 分」**，改成显示绝对时间。
用户看到「还有 1392 分」只会困惑。

---

## 四、UI 上要处理的边界状态

必须覆盖这四种，一种都不能漏：

| 场景 | 应显示 |
|---|---|
| 有一趟车正在跑 | 车图标在区间内，进度百分比，各站倒计时正常 |
| 刚好在两趟车之间（上一趟已到，下一趟未发） | **不画车**，显示「下一班 10:28 · 还有 71 分钟」 |
| 今天所有班次都结束了 | 「今日班次已结束 · 明日首班 08:30」，不画车、不显示倒数 |
| 周末/节假日 | 按现有逻辑（`isWeekend`）处理，不画车 |

**特别强调**：第二种情况现在完全没处理，就是导致这次 bug 的原因。

---

## 五、首页那张卡也要一起检查

`lib/services/bus_service.dart:485` 的 `nextBusSummary()`：

```dart
for (final t in outStop.times) {
  final diff = hm.hour * 60 + hm.minute - nowMins;
  if (diff >= 0 && diff < bestDiff) { ... }
}
for (final t in inStop.times) {
  // 同样的逻辑
}
```

**两个问题**：
1. 它把**去程和回程混在一起比较**，取「时间上最近的一个」，但没管用户当前是想去上课还是回家。
   应该**先按方向过滤**（早上显示去程的下一班，下午显示回程的下一班），
   或者显示「去程下一班 / 回程下一班」两条。
2. `bestTime == null` 时的兜底写死了 `outStop.times.first`：
   ```dart
   direction: '今日班次已结束（明日首班 ${outStop.times.first}）',
   ```
   **不管你是什么方向、什么时间，永远显示去程首班。** 应该根据当前方向取对应的首班。

---

## 六、还有一个硬编码的猜测

`lib/screens/schedule/bus_schedule_screen.dart:93`：
```dart
_isInbound = DateTime.now().hour >= 14;
```

**「下午 2 点之后就是回程」是硬编码猜的。** 实际情况可能是：
- 用户下午还有课，需要看去程
- 用户周末在家，不需要看回程

**建议**：默认方向用「上一趟发车的方向」来推断，或者干脆记住用户上次手动选的，
或者无论如何都给一个明确的切换按钮（已经有 SegmentedButton 了，用它的状态就好）。

---

## 七、验收（必须逐条验证，不能只看截图）

**用当前时间实测以下几种情况**（可以直接改系统时间或在代码里临时注入 now 来测）：

- [ ] **09:17**（Slot1 已到终点，Slot2 未发）→ 不画车，显示「下一班 10:28」
- [ ] **10:00**（Slot2 行驶中）→ 车图标在两站之间，进度合理（0-100%）
- [ ] **08:35**（Slot1 行驶中）→ 车图标已过第一站，进度 > 0
- [ ] **14:40**（Slot5 行驶中）→ 正常显示
- [ ] **15:00**（今天全部结束）→ 不画车，显示「今日班次已结束」
- [ ] **周末** → 按周末逻辑处理
- [ ] 各站倒计时**绝不能出现超过 3 小时**的「还有 N 分」
- [ ] 首页卡片：早上显示去程下一班，下午显示回程下一班（或两条都显示）
- [ ] 首页「今日班次已结束」的明日首班时间，要跟当前方向一致

---

## 八、提醒

- flutter 命令用 `C:\Users\33239\dev\flutter-nops.bat`
- 项目 `C:\Users\33239\Documents\LifeLog`，改完 git commit
- 这次只改校车相关的计算和显示逻辑，**不要动刚做好的 UI 样式**
- 改完 analyze 0 error + build apk 出包给我验收

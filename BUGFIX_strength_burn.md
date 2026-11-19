# P0 Bug：训练消耗估算不准 + 饮食页没同步

> 老大实测（2026-11-19 12:40 两张截图）
> 1. 训练**17 组、总容量 9004 kg**，却显示「消耗约 14 kcal」
> 2. 饮食页的「训练消耗」没跟着涨

---

## 一、问题1：14 kcal 的计算依据错了

### 现在的算法
`lib/services/nutrition.dart` 第 154-163 行 `calcMetCalories`：
```dart
kcal = MET × 体重(kg) × (分钟 / 60)
```
`strengthMet = 5.0`

带入实际数据：
```
5.0 × 70kg × (2.78分钟 / 60) ≈ 16 kcal
```

**数学没错，错在「分钟」这个输入。** 老大是「先加完 17 组、再统一点勾」，计时器只走了 2:46，
所以按 2.78 分钟算，自然只有 14 kcal。

**但 17 组 9004 kg 的训练量，现实中至少 40-60 分钟。** 用计时器时长估算，对「批量补录」的用法完全失效。

### 修法：改成**按训练容量估算**，不再依赖计时

**核心公式**（力量训练的经验值）：
```
消耗出的净消耗 kcal ≈ 容量(kg) × 0.008 + 组数 × 2
```

验算老大的实际数据：
- 9004 kg × 0.008 = 72 kcal
- 17 组 × 2 = 34 kcal
- 合计 ≈ 106 kcal

**这个量级合理**（对照：一小时中等强度力量训练约 300-400 kcal，老大这次是「2 分钟补录」但训练量相当于 40 分钟的量，106 偏保守，可以再调系数）。

### 建议的两段式
```dart
static double estimateStrengthBurnKcal({
  required double totalVolumeKg,
  required int workSets,
  required double weightKg,
  required double elapsedMinutes,
}) {
  // 1) 按容量估算（主依据，不依赖计时）
  final byVolume = totalVolumeKg * 0.008 + workSets * 2.0;

  // 2) 按计时估算（辅助，防止只有 1-2 组但计时很长）
  final byTime = calcMetCalories(
    met: strengthMet, weightKg: weightKg, minutes: elapsedMinutes);

  // 3) 取较大值，但上限封顶
  //    （容量法在批量补录场景更可靠；计时法在真实连续训练时更可靠）
  final result = byVolume > byTime ? byVolume : byTime;
  return result.clamp(0.0, 800.0);  // 单次力量训练不该超过 800 kcal
}
```

**系数说明**（给个出处，别瞎定）：
- 0.008 kg⁻¹ 这个系数的来源：完成 1 kg 容量的抗阻训练，净消耗约 0.007-0.010 kcal
- 每组的固定开销：约 2 kcal（准备、调整器械、组间走动的非运动消耗）

这些系数写在代码注释里，以后好调。

---

## 二、问题2：饮食页没同步

### 排查方向（按可能性）

**A. `wk.date` 和 `targetDate` 格式不一致**
`targets.dart:46`：
```dart
final workouts = (await Repo.getWorkouts(from: targetDate))
    .where((wk) => wk.date == targetDate);
```
`getWorkouts(from:)` 用的是 SQL `date >= ?`，但后面又用 Dart 做 `==` 精确比对。
如果 `wk.date` 存的是 `2026-11-19`、`targetDate` 是 `2026-11-19` 就没事，
但如果有任一方带了时间（`2026-11-19T00:00:00`），就永远匹配不上。
**修法**：统一用 `dateOnly()` 归一化后再比，或者干脆只依赖 SQL 的 `date = ?`。

**B. `endTime` 没写进去**
`workout_session_screen.dart:450`：
```dart
w.endTime = w.startTime + (elapsedSecs * 1000);
await Repo.updateWorkout(w);
```
确认 `Repo.updateWorkout` 真的把 `end_time` 写进了表（`w.toMap()` 里有没有这个字段）。

**C. 饮食页显示的不是 `workoutBurn`**
检查 `diet_screen.dart` 和 `home_screen.dart` 里「训练消耗」那个数字，
是不是直接读的 `_targets.workoutBurn`。如果是别的字段（比如只算有氧的），就对不上。

**D. 缓存**
`DailyTargets.load()` 有没有缓存？改了训练之后没重新 load 就是旧值。

### 验收
- [ ] 训练 17 组 9004 kg → 消耗显示 100-150 kcal 之间（不是 14）
- [ ] 点「结束训练」后，回饮食页，训练消耗数字**立即更新**（不用重启 App）
- [ ] 首页的「训练消耗 +N kcal」也跟着变
- [ ] 当天的可摄入额度 = BMR×系数 + 训练消耗，数字对得上

---

## 三、顺带检查（截图里看到的）

1. **「近期力量训练总容量 (kg)」那张柱状图**：只有一根柱子、占满整个宽度，
   而且数值 9004 标在柱子上面、日期 11-19 标在下面。
   如果只有一天数据，应该显示成居中的单柱而不是拉满，或者干脆用数字卡片代替柱状图。
2. **训练记录卡片**：「今天 · 时长 2 分钟 · 正式组 17 组 · 总容量 9004 kg · 消耗 ~14 kcal」
   —— 文字太长换行了，建议缩短成两行：
   第一行「今天 · 17 组 · 9004 kg」，第二行「2 分钟 · 约 106 kcal」
3. **完成提示 toast**：「训练完成！耗时 2 分钟 · 17 组 · 容量 9004 kg · 消耗约 14 kcal」
   同样的数字要跟着上面一起改。

---

## 四、范围与版本

- 只改消耗估算逻辑 + 数据同步
- 不动 UI 样式
- **版本号 2.1.5 → 2.1.6**（跟上一个 bug 一起，合并进同一个版本）
- 改完 analyze 0 error + build apk
- flutter：`C:\Users\33239\dev\flutter-nops.bat`

---

## 五、附：有氧那边也检查一下
有氧用的是 `calcMetCalories` + MET 表，那个是对的（时长是真实的）。
但确认有氧记录的 `calories` 字段在保存时算对了，不要被 `clamp` 掉。

---

## 六、新增功能：消耗可以手动修正（P1，老大新提）

### 需求原话
「要不可以自己加一个结果可以修正，比如我今天练完了发现我没用这个 app」

### 为什么需要
估算永远是估算。实际情况千差万别：
- 有人练完才想起来记录，计时器只走了几分钟
- 有人练了两小时但只记了几组
- 有人的训练内容 App 里根本选不到（壶铃摆荡、农夫行走、战绳）

**不能修正的话，数据越攒越不准，最后整个饮食模块的推荐都是错的。**

### 做法

#### 6.1 训练记录卡片上加「修正」入口
训练记录卡片（`workout_list_screen`）右侧，加一个铅笔图标或长按菜单：
```
┌────────────────────────────────────┐
│ 今天 · 17 组 · 9004 kg        [✏️] │
│ 2 分钟 · 约 106 kcal           [🗑️] │
└────────────────────────────────────┘
```

#### 6.2 修正弹窗
点铅笔，弹出一个底部弹窗：
```
┌──────────────────────────────────┐
│  修正训练记录                     │
│                                  │
│  实际训练时长    [ 45 ] 分钟      │
│  消耗热量        [ 320 ] kcal    │
│                                  │
│  ⓘ 估算值 106 kcal，可手动改      │
│                                  │
│        [ 取消 ]    [ 保存 ]       │
└──────────────────────────────────┘
```

**两个可改字段**：
1. **实际时长**（分钟）：改了这个，如果用户没单独改热量，就按新时长重算
2. **消耗热量**（kcal）：直接覆盖，优先级最高

#### 6.3 数据层
`workouts` 表加两个字段（或者用已有的扩展方式）：
```sql
ALTER TABLE workouts ADD COLUMN manual_duration_min INTEGER;  -- 用户手动填的时长
ALTER TABLE workouts ADD COLUMN manual_burn_kcal REAL;        -- 用户手动填的消耗
```
**用 `manual_` 前缀区分「用户填的」和「算出来的」**，
这样以后调整算法时，用户手动改过的数据不会被覆盖。

`targets.dart` 里的优先级：
```dart
double burnFor(Workout wk) {
  // 1) 用户手动填的热量最优先
  if (wk.manualBurnKcal != null && wk.manualBurnKcal! > 0) {
    return wk.manualBurnKcal!.clamp(0, 3000);
  }
  // 2) 用户手动填的时长
  if (wk.manualDurationMin != null && wk.manualDurationMin! > 0) {
    return calcMetCalories(
      met: strengthMet, weightKg: w, minutes: wk.manualDurationMin!.toDouble());
  }
  // 3) 自动估算（容量法 + 计时法取大）
  return estimateStrengthBurnKcal(...);
}
```

#### 6.4 有氧记录也一样
有氧卡片同样支持修正时长和消耗。数据结构一致。

#### 6.5 UI 上要标明「这是修正过的」
如果用户改过，卡片上显示一个小标记：
```
今天 · 17 组 · 9004 kg  [已修正]
45 分钟 · 320 kcal
```
**不要偷偷改，要让用户知道这个数字不是算出来的。**

#### 6.6 顺带：允许「补录」一整天的训练
老大那个场景的极端版：练完了完全没开 App。
现在的流程是「开始训练→加动作→结束」，补录很别扭。

**建议加一个「快速补录」入口**：
- 选日期（默认今天）
- 选时长（直接填 45 分钟）
- 选消耗（或按体重×MET 自动算）
- 可选：关联具体动作和组数
- 一条记录直接进库，不进入会话流程

这样「没用 App 练完」也能补上。

### 验收
- [ ] 训练记录卡片能点「修正」
- [ ] 能改时长和消耗，保存后列表立即刷新
- [ ] 改过的记录在饮食页/首页的训练消耗跟着变
- [ ] 改过的记录有「已修正」标记
- [ ] 能快速补录一条「只有时长和消耗」的记录
- [ ] 算法以后改进时，用户手动改过的值不被覆盖

---

## 七、版本
以上全部（消耗估算法 + 饮食同步 + 手动修正 + 快速补录）
**版本号 2.1.5 → 2.1.6**（如果改动太大也可以拆成 2.1.6 和 2.1.7，你判断）

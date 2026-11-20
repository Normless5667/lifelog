# P0 补丁：训练中断无法恢复 + AI 计划无法清除

> 用户实测反馈（2026-11-20 12:26）
> 1. 「不小心划开健身页面进入主页面计时器就会停止，**想继续也没有地方可以继续计时器**」
> 2. 「AI 已经导入的健身计划**没办法清除**」

---

## 一、问题 1：训练中断后无法恢复（P0，体验致命）

### 用户描述
训练进行中（截图显示 44:56、20组 5704kg），从屏幕边缘划一下回到了主页，回来之后：
- 计时器停了
- **没有任何入口能回到那个训练会话**
- 之前记的组数、重量全部悬空

这比"计时器停止"严重得多。**整个训练数据等于丢了。**

### 代码现状
`workout_session_screen.dart` 是独立页面（push 进去的）。一旦 pop 或系统回收，页面状态就没了。

`didChangeAppLifecycleState` 那段只处理了"App 切后台"，**没处理"页面被销毁"**：
```dart
if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
  _appInForeground = false;
  _stopTicker();
} else if (state == AppLifecycleState.resumed) {
  _appInForeground = true;
  _syncTimeFromWallClock();
  _ensureTickerIfVisible();
}
```
如果页面已经被 pop 或者被路由栈丢了，这个回调都不会触发。

### 正确做法：**持久化"进行中的训练"**

#### 1.1 数据层
数据库里 `workouts` 表已经有一条记录（`startTime` 有值，`endTime` 为 null 就是"进行中"）。
**关键是要能查出来**：

```dart
// repo.dart 已有 getWorkouts，但没有"查未结束的训练"的方法
static Future<Workout?> getInProgressWorkout() async {
  final rows = await (await _db).query(
    'workouts',
    where: 'end_time IS NULL',
    orderBy: 'start_time DESC',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return Workout.fromMap(rows.first);
}
```

#### 1.2 训练页恢复能力
`workout_session_screen` 现在只接受 `workoutId`（从列表页传进来）。
**要支持"从 workoutId 恢复"**：
```dart
// 已经有这个逻辑了（第 223 行 getWorkout），
// 确认从 DB 加载 sets 时是对的：
final sets = await Repo.getSets(widget.workoutId);
```
**问题**：现在的 sets 是"结束后才写入"的（`_finish` 里才 `replaceSets`）。**训练中途切出去，sets 没落库，恢复时是空的。**

**修法**：改成**每次点 ✓（完成一组）就写库**，而不是等结束才写。
```dart
void _markSetDone(_ExerciseBlock b, int si) {
  setState(() { b.sets[si].done = true; });
  _persistSetsDraft();   // 新增：立刻落库
}
```

#### 1.3 UI 入口（这是用户最要的那一步）
**在训练列表页和首页都要显示"进行中的训练"卡片**：

```
┌────────────────────────────────────┐
│ 🔴 训练进行中                       │
│    杠铃卧推 · 20 组 · 5704 kg       │
│    已进行 44:56                     │
│    [ 继续训练 ]  [ 结束并保存 ]     │
└────────────────────────────────────┘
```

- **继续训练**：重新 push 进 session 页面，带上已有的 workoutId，恢复计时（`now - startTime`）和已记录的组
- **结束并保存**：直接走 `_finish` 流程，把未完成的组也存上

#### 1.4 冷启动也要能恢复
App 被杀掉重开，`getInProgressWorkout()` 还能查到那条 `end_time IS NULL` 的记录。
**建议**：如果 `startTime` 距今超过 6 小时，弹窗问"这次训练还要继续吗？"，避免开着忘了一整天。

#### 1.5 顺手修计时器的两个隐患
```dart
// 现在 inactive 也会停表
if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
```
**建议**：
- `inactive` 不停 ticker（下拉通知栏、来电、分屏都会触发，停表太敏感）
- 只在 `paused` 时停
- 而且既然有 1.3 的"进行中卡片"，即使 ticker 停了，用户也能看到真实时长（靠 `now - startTime` 算）

---

## 二、问题 2：AI 导入的计划无法清除（P0）

### 代码现状
`repo.dart`：
```dart
static Future<TrainingPlan?> getTrainingPlan() async {
  final s = await getKv('active_training_plan');
  ...
}

static Future<void> saveTrainingPlan(TrainingPlan plan) =>
    setKv('active_training_plan', jsonEncode(plan.toJson()));
```

**有 `saveTrainingPlan`，但没有 `clearTrainingPlan`。** 存进去之后没有任何删除的路径。

UI 上 `workout_list_screen.dart:379` 的 `_activePlanCard(_plan!)` 只做了展示和"开始"，**没有删除按钮**。

### 修法

#### 2.1 数据层加清除方法
```dart
static Future<void> clearTrainingPlan() => setKv('active_training_plan', '');
```

#### 2.2 UI 加删除入口
`_activePlanCard` 右上角加一个「⋯」菜单或删除图标：

```
┌────────────────────────────────────┐
│ 当前训练计划：推拉腿·三分化    [⋯] │
│ ────────────────────────────────  │
│ 周一 推（胸/肩/三头）  [ 开始 ]    │
│ 周二 拉（背/二头）     [ 开始 ]    │
│ 周三 腿                [ 开始 ]    │
└────────────────────────────────────┘
```

点「⋯」弹出：
- **重命名计划**
- **替换计划**（重新让 AI 生成）
- **删除计划** ← 必须有的

#### 2.3 删除要二次确认
```
确认删除「推拉腿·三分化」？
这个计划会被移除，但已经完成的训练记录不受影响。
                    [取消]  [删除]
```
说清楚"训练记录不受影响"，不然用户怕误删历史数据不敢删。

#### 2.4 也支持"跳过计划直接自由训练"
现在有活跃计划时，用户可能只想临时练一次别的。在计划卡片下面加一行：
```
或者 [ 不按计划，自由训练 ]
```

---

## 三、验收

**训练恢复**：
- [ ] 训练中途从屏幕边缘划回主页，再回到 App → 训练列表页顶部出现「训练进行中」卡片
- [ ] 点「继续训练」→ 回到 session 页，**已记录的组还在，计时器继续走**
- [ ] 点「结束并保存」→ 正常存库，消耗算对
- [ ] 训练中途杀掉 App 重开 → 还能看到「训练进行中」卡片
- [ ] 训练超过 6 小时后打开 App → 问「还要继续吗」
- [ ] 下拉通知栏再收起，计时器不停

**计划清除**：
- [ ] 有活跃计划时，卡片上有「⋯」菜单
- [ ] 点「删除计划」→ 二次确认 → 删除后卡片消失
- [ ] 删除后可以重新导入 AI 新计划
- [ ] 删除计划不影响已完成的历史训练记录

---

## 四、其他（跟上一个 BUGFIX 一起做）

上一个报告里的：
- `log_weight` tap=4 success=0
- `ai_plan_import` tap=2 success=0
- `quick_log_diet` tap=3 cancel=3
- `start_workout` success 重复计数
- `timer_tick` 指标改成累计秒数

**版本号 2.1.7 → 2.1.8**（改动多的话可以拆 2.1.8/2.1.9）

---

## 五、环境
- flutter：`C:\Users\33239\dev\flutter-nops.bat`
- 项目：`C:\Users\33239\Documents\LifeLog`
- analyze 0 error + build apk + git commit

# 训练计时器 Bug + 使用数据分析（2026-11-20 真实导出数据）

> 数据来源：`lifelog_usage_7d_2026-11-20.json`（v2.1.7，7 天，1357 条事件）
> 环境：OPPO Find X8 / ColorOS

---

## 一、用户报的 bug（P0）

**现象**：健身过程中不小心划出去（切到别的 App / 回桌面），回到 App 后**计时器停止**，时间对不上。

**用户原话**：「健身那里如果我正在健身不小心划出去了，那计时器就会停止」

### 代码现状（我看了 `workout_session_screen.dart`）

这段写得其实**思路是对的**：
```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
    _appInForeground = false;
    _stopTicker();                    // 切后台停表（省电，对的）
  } else if (state == AppLifecycleState.resumed) {
    _appInForeground = true;
    _syncTimeFromWallClock();         // 回前台用墙上时钟补算（也对）
    _ensureTickerIfVisible();
  }
}

void _syncTimeFromWallClock() {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (w != null) {
    if (w.endTime != null && !widget.isNew) {
      _elapsedNotifier.value = ((w.endTime! - w.startTime) ~/ 1000).clamp(0, 86400);
    } else {
      _elapsedNotifier.value = ((nowMs - w.startTime) ~/ 1000).clamp(0, 86400);
    }
  }
  ...
}
```

**理论上这样应该没问题**：切后台停 tick 省电，回前台按 `now - startTime` 重算。所以问题**不在这一段**。

### 那问题在哪？三个可疑点

**嫌疑 A：`AppLifecycleState.inactive` 也被当成"停表"**

`inactive` 在 Android 上比 `paused` 更早触发，很多场景会进入：下拉通知栏、来电话、**分屏/悬浮窗/多任务预览**、甚至某些机型的手势返回。

如果只是**短暂** inactive（比如划一下查看最近任务又回来），`_stopTicker` + `_ensureTickerIfVisible` 会反复执行。虽然 `_syncTimeFromWallClock` 会补上时间，但**如果 `resumed` 没被触发**（某些 ColorOS 场景下切回 App 只发 `inactive → resumed` 但顺序有延迟），时间就停在切出去的那一刻。

**建议**：`inactive` 时**只暂停 UI 刷新，不要 cancel ticker**；只在 `paused` 时停。或者干脆 `inactive` 什么都不做，让 ticker 继续跑（1 秒一次开销极小，之前 v1.6 的耗电修复是校车页，训练页本来就该跑）。

**嫌疑 B：`RouteAware` 的 `didPopNext` 和 `didChangeAppLifecycleState` 打架**

页面 `with WidgetsBindingObserver, RouteAware`。当用户从训练页跳到别的页面（比如点开动作库）再回来：
- `didPushNext` 会设 `_routeVisible = false` → 停表
- `didPopNext` 会设 `_routeVisible = true` → `_syncTimeFromWallClock` + `_ensureTickerIfVisible`

**如果 `didPushNext` 被触发但 `didPopNext` 没触发**（比如用返回手势而不是返回键），页面会一直认为"不可见"，回来也不恢复 ticker。

**嫌疑 C：`_ensureTickerIfVisible` 的守卫条件**

```dart
void _ensureTickerIfVisible() {
  if (!_routeVisible || !_appInForeground || _ticker != null) return;
  ...
}
```

如果 `_routeVisible` 或 `_appInForeground` 有一个卡在 false，就永远不恢复。**建议加日志或临时把这两个值打到 UI 上（debug 版）**，让用户能看到是哪一个是 false。

### 数据佐证（这个最有说服力）

从导出的 7 天数据统计：

| 事件 | 次数 | 含义 |
|---|---|---|
| `lifecycle/resumed` | **123** | 7 天进前台 123 次，平均一天 17.6 次 |
| `lifecycle/paused` | **120** | 基本一一对应 |
| `perf/timer_tick` | **146** | **只有 146 次 tick** |

**这是明显对不上的。** `timer_tick` 应该等于「计时器活跃秒数」。用户一次训练就 45 分钟（2700 秒），7 天 7 次训练（`start_workout` tap 7 次），按理 tick 应该有几千次。现在只有 146 次。

**两种可能**：
1. tick 事件被节流了（BatteryProbe 里可能采样了）—— 那这个指标就没意义，需要改成「累计活跃秒数」。
2. 或者 ticker 确实经常停，累计只跑了 146 秒。

结合 `lifecycle` 120+ 次切换，**大概率是第 2 种**：每次切出去就停，回来虽然会补时间但 tick 计数没补。

**建议改成记录"累计计时器活跃秒数"而不是"tick 次数"**，这样才能看出真实的计时覆盖情况。

---

## 二、使用数据里的其他问题（按严重程度）

### P1：`log_weight` 点击 4 次，成功 0 次

```
feature/log_weight: tap=4, success=0, fail=0, cancel=0, rate=0.0
```

点了 4 次，一次都没成功，也没标记失败或取消。**说明记录体重的流程要么卡住、要么成功后没触发 `trackFeature('log_weight', 'success')`。**

用户反馈「记今日体重」是首页四个快捷入口之一，点进去应该能记。要么按钮坏了，要么埋点在成功后漏了。**必须查。**

### P1：`quick_log_diet` 点击 3 次，取消 3 次

```
feature/quick_log_diet: tap=3, success=0, cancel=3, rate=0.0
```

全都取消了。可能是 AI 识别慢、输入框难用，或者用户试了一下觉得麻烦。**这个功能的核心价值是"快"，全取消说明不"快"。**

### P1：`ai_plan_import` 点击 2 次，成功 0 次

```
feature/ai_plan_import: tap=2, success=0, rate=0.0
```

v1.7 做的"AI 生成计划一键导入"，点了两次都没导入成功。要么 JSON 解析失败，要么写库报错。**这个功能等于废了。**

### P2：`start_workout` 的 rate = 2.0，计数重复

```
feature/start_workout: tap=7, success=14, rate=2.0
```

success 是 tap 的 2 倍。**同一个动作被记了两次 success**（可能是「开始训练」页面 `initState` 记一次、`_finish` 又记一次）。需要去重，不然转化率永远 >1，没意义。

### P2：`frame_jank` 数字在 summary 和 events 里不一致

- summary 说 `jank_frames: 2643`
- events 里实际只有 **542** 条 `perf/frame_jank`

**差不多是 5 倍。** 可能是 summary 聚合时把某个值重复累加了，也可能一次 jank 事件里 `value` 是掉帧数、summary 累加了 value 而 events 计数是行数。**两种统计口径要统一**，否则分析会得出错误结论。

### P2：内存平均 216 MB 偏高

7 天 17 次采样，平均 216.1 MB。对一个本地 SQLite 的生活记录 App 来说偏高。Windows 上没见过这么高的 Flutter 应用。**可能有大对象没释放，或者图片缓存没清理（拍照识热量那块）。**

### 信息：`step_sync` 的 tap=0 / success=74

不算 bug，但指标定义要改：这是后台自动同步，没有用户点击。**建议单独归为 `system` 类，不要混在 `feature` 的转化率里**，否则算平均转化率时会被它拉高。

---

## 三、修复优先级

| 优先级 | 项目 |
|---|---|
| **P0** | 训练计时器切后台停止（用户直接报的） |
| **P1** | `log_weight` 成功率为 0 |
| **P1** | `ai_plan_import` 成功率为 0 |
| **P1** | `quick_log_diet` 全取消 |
| **P1** | `timer_tick` 指标改成累计秒数 |
| **P2** | `start_workout` 重复计数 |
| **P2** | `frame_jank` 两处口径不一致 |
| **P2** | 内存 216 MB 排查 |

---

## 四、验收

- [ ] 训练中切后台 30 秒再回来，计时器时间**正确累加**（不是停在切走那一刻）
- [ ] 训练中从屏幕边缘滑动（手势返回）再回来，同样正确
- [ ] 训练中下拉通知栏再收起，时间不停
- [ ] `log_weight` 点一次记一次，success 有值
- [ ] 快速记饮食能成功走通一次
- [ ] AI 计划导入能成功一次
- [ ] `start_workout` 的 success 数 = tap 数
- [ ] `frame_jank` 的 summary 和 events 一致
- [ ] 版本号 2.1.7 → 2.1.8

---

## 五、环境

- flutter：`C:\Users\33239\dev\flutter-nops.bat`
- 项目：`C:\Users\33239\Documents\LifeLog`
- 改完 analyze 0 error + build apk + git commit

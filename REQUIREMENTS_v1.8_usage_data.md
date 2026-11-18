# LifeLog v1.8 需求：使用数据埋点 + 导出分析

> 老大原话：「下一版能不能加一个使用数据啊，导出到电脑分析，这样就不用一直盲猜了」
> 背景：现在所有优化全凭感觉——耗电哪来的、哪个功能没人用、用户在哪个页面卡住，全是猜。

---

## 一、设计原则（先看这个）

1. **只采数据，不上报**：全部存本地，用户手动导出。**不要加任何联网上报**，
   一是隐私，二是将来上架审核会被问数据安全声明。
2. **轻量**：采样本身不能成为新的耗电源。用 SQLite 批量写，别每次事件都 commit。
3. **可关**：设置里给一个「使用数据统计」开关，默认开，用户可以关。
4. **能看懂**：导出的格式要人/Excel/我 都能直接分析，JSON 或 CSV。

---

## 二、要采什么（分成四类）

### 2.1 页面浏览（知道哪些功能真被用）

```dart
PageViewEvent(
  page: 'home' | 'schedule' | 'diet' | 'workout' | 'body' | 'ai' | 'settings',
  enteredAt: DateTime,
  durationMs: int,          // 停留时长
  source: 'tab' | 'deeplink' | 'push',
)
```

**这批数据能回答**：哪个页面停留最久、哪些页面点了就走（说明没价值）。

### 2.2 功能使用（知道哪些功能真被用）

```dart
FeatureEvent(
  feature: 'quick_log_diet' | 'ai_log' | 'start_workout' | 'log_weight'
          | 'bus_board' | 'ai_plan_import' | 'weather_refresh' | 'step_sync',
  action: 'tap' | 'success' | 'fail' | 'cancel',
  durationMs: int?,
  errorMsg: String?,
)
```

**能回答**：AI 速记用了几次、成功几次；训练开始了多少次、完成了几次；
计划导入点了几次、真导入了几次。**点击到成功的转化率是产品最重要的指标**。

### 2.3 性能与耗电（这是老大最关心的）

```dart
PerformanceEvent(
  kind: 'frame_jank' | 'memory' | 'db_write' | 'gps_call' | 'timer_tick',
  value: num,
  extra: Map?,
)
```

采样规则：
- **帧卡顿**：`SchedulerBinding.addTimingsCallback`，只记超过 16ms 的帧（掉帧）
- **内存**：每 5 分钟一次 `ProcessInfo.currentRss`
- **GPS 调用**：记次数和时间戳（看有没有偷偷多次调用）
- **计时器**：记录哪些 Timer 在什么时段活跃（定位耗电元凶）

**这批数据直接回答「电到底被谁吃了」。**

### 2.4 生命周期（知道 App 在前台多久）

```dart
LifecycleEvent(
  state: 'resumed' | 'paused' | 'detached',
  at: DateTime,
)
```

配合页面数据能算出「前台时长」「后台时长」「日均使用时长」。

---

## 三、存储设计

新建一张表，不要动现有业务表：

```sql
CREATE TABLE IF NOT EXISTS usage_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,          -- 毫秒时间戳
  category TEXT NOT NULL,       -- 'page' | 'feature' | 'perf' | 'lifecycle'
  name TEXT NOT NULL,           -- page 名 / feature 名 / perf kind
  action TEXT,                  -- 'tap'|'success'|'fail'|'cancel'
  duration_ms INTEGER,
  value REAL,
  extra TEXT,                   -- JSON 字符串，自由字段
  app_version TEXT,
  session_id TEXT               -- 一次前后台周期一个 id，方便聚合
);
CREATE INDEX idx_usage_ts ON usage_events(ts);
CREATE INDEX idx_usage_cat ON usage_events(category, name);
```

**写入策略**：
- 内存里缓冲，**每 30 秒或每 50 条**批量 flush 一次
- App 进后台时立即 flush（`WidgetsBindingObserver.didChangeAppLifecycleState`）
- 单条 insert 不要每个事件都做，那本身就很耗电

**保留策略**：
- 只留 30 天，超过的自动删
- 加一个「清空使用数据」的按钮

---

## 四、导出

### 4.1 导出格式（三选一或都做）

**推荐：JSON（完整）+ CSV（方便 Excel）**

JSON 结构：
```json
{
  "exported_at": "2026-11-18T21:42:00+07:00",
  "app_version": "1.8.0",
  "device": {"model": "OPPO Find X8", "os": "Android 15", "screen": "1080x2394"},
  "range": {"from": "2026-11-11", "to": "2026-11-18"},
  "summary": {
    "total_fg_minutes": 342,
    "daily_active_days": 5,
    "top_pages": [{"page": "home", "minutes": 120}, ...],
    "feature_conversion": [
      {"feature": "ai_plan_import", "tap": 5, "success": 2, "rate": 0.4}
    ],
    "perf": {"jank_frames": 23, "avg_memory_mb": 180, "gps_calls": 6}
  },
  "events": [ ... 明细，可选是否包含 ... ]
}
```

**关键：summary 要有**。老大不想看几十万条明细，他要的是「这几天用了什么、哪里慢」。

CSV 就平铺：`ts,category,name,action,duration_ms,value,extra`

### 4.2 导出方式

用现有的 `share_plus`（已经在依赖里）：
- 「导出使用数据」按钮 → 生成文件到临时目录 → `SharePlus.instance.share(...)` 分享出去
- 也能存到 Downloads（Android 10+ 需要 `MediaStore`，或者用 SAF 让用户选位置）

### 4.3 导出范围选择
弹窗让用户选：最近 1 天 / 7 天 / 30 天 / 全部

---

## 五、界面

设置页新增一栏「使用数据」：
```
┌──────────────────────────────┐
│ 📊 使用数据                   │
├──────────────────────────────┤
│  记录使用情况        [开关·开] │
│  已记录 1,234 条（7 天）      │
│                              │
│  [ 导出数据 ]  [ 清空 ]       │
└──────────────────────────────┘
```

---

## 六、我的建议（怎么用这批数据）

导出之后我可以帮老大分析，重点看这五个问题：

1. **哪个功能点了不用**：tap 次数高但 success 低 → 流程有问题
2. **哪个页面停留最短**：点开就走 → 那个页面没价值
3. **耗电元凶**：`perf` 里的 timer_tick 和 gps_call 时间分布
4. **掉帧集中在哪**：`frame_jank` 的 extra 里带页面名，能定位是哪页卡
5. **坚持度**：daily_active_days / 连续登录，判断这 App 是不是真被需要

**建议先跑一周再分析**，一天的数据说明不了什么。

---

## 七、验收标准

- [ ] 四类事件都能采到（page/feature/perf/lifecycle）
- [ ] 数据库表建好，索引有，不拖慢主流程
- [ ] 批量写入（不是每条都 commit），进后台会 flush
- [ ] 30 天自动清理
- [ ] 设置页有开关、能看到已记录条数
- [ ] 能导出 JSON 和 CSV，带 summary
- [ ] 导出范围可选（1/7/30 天）
- [ ] **采样本身不能增加耗电**——加完后跑一次对比，后台耗电不能比之前高
- [ ] analyze 0 error，git commit

---

## 八、明确不要做的

- ❌ 不要联网上报（隐私 + 审核风险）
- ❌ 不要采个人内容（吃了什么、体重多少、AI 聊了什么，这些不采）
  只采「操作行为」，不采「数据内容」
- ❌ 不要用第三方分析 SDK（Firebase/友盟），多一个依赖多一个隐私声明
- ❌ 不要在 release 包里留调试日志

---

## 九、跟其他版本的关系

这条排在 **v1.6（耗电+校车）之后**，可以和 v1.7（JSON 隐藏）并行做。
**注意：前端视觉重写是 Opus 5.5 的活，你只管把埋点逻辑加进去，别动样式。**

flutter 命令：`C:\Users\33239\dev\flutter-nops.bat`
项目：`C:\Users\33239\Documents\LifeLog`（git 仓库）

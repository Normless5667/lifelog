# LifeLog v3.0.0 分阶段交付进度（PROGRESS.md）

> 对应总需求：`REQUIREMENTS_v3.0.md`

## 阶段 A：P0 Bug 修复（v2.1.8+14）✅ 已完成并出包
- [x] **1.1 训练中断无法恢复**：`Repo.getInProgressWorkout()`、`workout_session_screen` 即时草稿落库（点 ✓ / 增删 / 切后台 / 600ms 防抖）、边缘返回防误杀弹窗、首页与训练列表页「🔴 训练进行中」恢复卡片、冷启动 6 小时超时询问、`inactive` 不再停表。
- [x] **1.2 AI 计划清不掉**：`Repo.clearTrainingPlan()`、活跃计划卡片「⋯」菜单（重命名 / 替换 / 删除二次确认，说明不影响历史记录）、卡片下方「不按计划，自由训练」。
- [x] **1.3 三个功能成功率归零**：修复 `log_weight` 首页误打 tap、修复 `ai_plan_import` 误打 tap + 提高 `maxTokens` + JSON 容错修复、升级 `quick_log_diet` 近 7 天常吃一键填入与极简模式。
- [x] **1.4 埋点口径与内存排查**：`start_workout` 一次性防重锁、`frame_jank` 同时输出 `jank_events` 与 `jank_frames`、`timer_tick` 升级为 `timer_active_sec` 累计秒数、`step_sync` 独立归 `system` 类、图片解码 `cacheWidth`/`cacheHeight` 与 `imageCache` 32MB 上限。
- [x] 交付物：Commit `482e7fe`，24/24 测试通过，`analyze` 0 error / 0 warning，APK：`LifeLog_v2.1.8_release.apk`。

## 阶段 B：清空课表 + 假期判断（v2.1.9+15）✅ 已完成并出包
- [x] **2.1 课表可清空 + 首次引导 + 多选星期表单**：
  - `Course.source`（`builtin` / `user`）与 SQLite v6 幂等迁移，全新安装不再强塞 BUV 课表。
  - `Repo.clearAllCourses()` 清空课表并同步取消上课提醒闹钟。
  - 课表页右上角「⋯」菜单 + 课表设置 + 设置页均提供「清空所有课程」与带课程数的二次确认。
  - 全新安装询问「要不要导入 BUV 示例课表？」（导入示例 / 跳过，自己添加）。
  - 手动添加课程表单支持星期多选（如周一三五一次添加）。
- [x] **2.2 公共假期判断（本地内置 + 联网补充）**：
  - `assets/holidays.json` 内置人工校验的 VN / CN / GB / US（2025–2027，完整含越南春节 Tết、雄王纪念日与中国农历假日）。
  - `HolidayService` 基于天气模块已有城市/经纬度推断国家（零新增定位权限），Nager.Date 仅补充不覆盖、按国家+年份 kv 缓存 180 天、离线兜底。
  - 假期当天首页显示「今天是假期，没有课程」、课表页列与周头清晰标记、上课提醒与系统闹钟自动跳过。
- [x] 验证：29/29 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v2.1.9_release.apk`。

## 阶段 C：课程状态倒计时 + M3 动效（v3.0.0+16）✅ 已完成并出包
- [x] **2.3 课程状态 + 倒计时**：
  - 新增 `lib/utils/course_status.dart`（`CourseStatus` 三态评估、按节次实时倒计时与今日汇总 `summarizeTodayCourses`）。
  - 首页「今日课程」顶部新增实时倒计时条（正在上课剩多久下课 / 下节课倒计时 / 今日课程已全部上完），使用轻量 30 秒生命周期感知定时器（`ValueNotifier<DateTime>` 局部刷新，切后台自动暂停，不重绘整页）。
  - 课程卡片三态视觉区分：已上完（`Opacity(0.55)` + 删除线 + 灰标「已上完」）、进行中（模块色浅底高亮边框 + `BreathingDot` 克制呼吸圆点 +「还有 N 分钟下课」）、未开始（正常样式 +「N 分钟后开始」），并接入 `ScaleTap` 点击直达课表。
- [x] **2.4 Material 3 动效**：
  - 新增 `AppMotion` 动效 Token 与 `M3SubtlePageTransitionsBuilder`（路由切换 300ms 淡入 + 16dp 轻微横向位移，无夸张缩放/翻转）。
  - 新增 `M3SlidingNavBar`：底部导航选中图标 `24 → 28` 平滑放大、图标/文案颜色过渡、64×32 `StadiumBorder` 药丸指示器横向滑动（**250ms**，`Curves.easeInOutCubicEmphasized`）。
  - 首页 5 Tab 切换使用 `AnimatedSwitcher`（260ms 淡入 + 16dp 方向感知水平位移）。
  - `ScaleTap` 校准至 `0.98` / `120ms` / `Curves.easeOut`；全局所有动效（含 `BreathingDot`、`ScaleTap`、`M3SlidingNavBar`、页面转场与 Tab 切换）均遵循 `MediaQuery.disableAnimationsOf(context)`。
- [x] 验证：版本号跃升至 **`3.0.0+16`**，35/35 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.0.0_release.apk`。

## v3.0.1：课表左右滑切周 + 学术日历周数 + 学期设置（v3.0.1+17）✅ 已完成并出包
- [x] **学术日历驱动真实周数 (`AcademicCalendarService` + `assets/academic_calendar.json`)**：
  - 周数统一按 `floor((date - week1Start) / 7) + 1` 计算（2026-09-28 起第 1 周，2026-11-20 精确为第 8 周；自动区分 2026 秋季 / 2027 春季学期）。
  - `confidence: high` 日期（国庆、圣诞、元旦、寒假等）自动并入假期系统，隐藏当日课程并跳过闹钟；`confidence: low` 日期（如 2026-11-24）默认以「非教学日」中性提示且不含「假期」字样，可在设置中逐条手动修正（非教学日 / 设为假期 / 正常上课）。
- [x] **课表 `PageView` 左右滑动切周 + 周数导航条 + 边界处理**：
  - `ScheduleScreen` 升级为 `PageView.builder` 按真实周数逐页滑动（左滑下一周、右滑上一周），顶部实时联动显示周数与 `MM-dd ~ MM-dd` 日期范围。
  - 新增顶部周数导航条（`← MM-dd ~ MM-dd [今天] →`），点「今天」一键跳回当前周；切到其他周时在今天对应星期列显示克制小圆点标记。
  - 边界清晰处理：第 1 周前显示「学期未开始」（含迎新周提示），第 12 周后显示「学期结束，进入考试周」。
- [x] **「学期设置」独立表单页 (`SemesterSettingsScreen`)**：
  - 设置页与课表页均可进入，支持普通用户直接填写「学期名称 / 第 1 周开始日期 / 总周数」实时预览周数并保存；支持一键切换校历学期、手动修正低置信度日期、粘贴导入 `academic_calendar.json`（高级功能），并预留 iCal (`.ics`) 导入入口。
- [x] 验证：版本号跃升至 **`3.0.1+17`**，39/39 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.0.1_release.apk`。

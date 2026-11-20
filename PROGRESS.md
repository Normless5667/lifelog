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

## 阶段 C：课程状态倒计时 + M3 动效（v3.0.0+16）⏳ 待阶段 B 验收后开始
- [ ] **2.3 课程状态 + 倒计时**：今日课程三态（已上完 / 进行中含呼吸动画与下课倒计时 / 未开始含上课倒计时）+ 首页倒计时条。
- [ ] **2.4 Material 3 动效**：底部导航 250ms 放大+变色+滑条（`easeInOutCubicEmphasized`）、页面切换 250–300ms 淡入+轻微横向位移、卡片按压 0.98 / 120ms，全局遵循 `MediaQuery.disableAnimations`。
- [ ] 版本号跃升至 **`3.0.0+16`**，全量验收与出包。

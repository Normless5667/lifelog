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

## v3.1.0 跑步模块 + 深色皮肤 + 生图插画（分三批交付）
### 第一批：GPS 轨迹 + 地图 + 自由跑/距离跑 + 记录保存（v3.1.0+18）✅ 已完成并出包
- [x] **地图与依赖**：接入 `flutter_map ^8.0.0` + `latlong2 ^0.9.1`（OpenStreetMap 免费免 Key，地图页统一标注 `© OpenStreetMap contributors`）与 `wakelock_plus` 屏幕常亮。
- [x] **Android 原生前台定位服务 & 权限**：新增 `RunningForegroundService.kt`（`FOREGROUND_SERVICE_LOCATION` 常驻通知「正在记录跑步」+ 实时距离/时长/配速刷新 + `PARTIAL_WAKE_LOCK`），补充 `ACCESS_BACKGROUND_LOCATION` / `FOREGROUND_SERVICE` / `FOREGROUND_SERVICE_LOCATION` / `WAKE_LOCK` 权限，并实现 Android 11+ 后台定位分步引导页 `location_permission_guide.dart`。
- [x] **GPS 精准过滤与平滑引擎 (`RunningTrackerController` + `RunTrackProcessor`)**：
  - 使用 `Geolocator.getPositionStream(distanceFilter: 5)`（不轮询），丢弃 `accuracy > 20m` 坏点与速度突变跳点，结合 Haversine 与轻量 EMA 坐标平滑（1km 实测与噪声模拟误差均 < 5%）。
  - 暂停时停止接收 GPS 并切断分段，继续时绝不计入暂停位移；单调时钟独立统计「运动时长（不含暂停）」与「累计总时长（含暂停）」。
- [x] **数据库 v7 & 饮食热量同步**：新增 `runs`（`route_json` 存 `[{lat,lng,t}]`）与 `run_segments` 表；保存跑步记录后自动汇总进 `DailyTargets.load()` 同步至饮食页热量预算。
- [x] **Keep 风格跑步首页 / 跑步中 / 历史详情**：健身页顶部独立入口，跑步首页提供「自由跑 / 距离跑 (1/3/5/10km) / 跑步课程（加载 8 门内置课）」及历史记录；跑步中采用超大四项核心数字 + 实时轨迹地图 + 暂停/结束；历史详情可从 `route_json` 完整重绘轨迹。
- [x] 验证：43/43 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.1.0_release.apk`。

### 第二批（P0）：11 门跑步课程分段执行 + TTS 语音教练 + 分段记录（v3.1.1+19）✅ 已完成并出包
- [x] **课程分段执行引擎 (`lib/services/run_course_engine.dart`)**：
  - 同时支持按时间（`durationSeconds`，如 3/5/10 公里法特莱克）与按距离（`durationMeters`，如新增 3/5/10 公里分段跑与 5×400m 间歇）。
  - 复用 `assets/running_courses.json` 中 `segmentTypes` 中文名与色值（热身 / 慢跑 / 快跑 / 慢跑恢复 / 快走 / 放松）。
  - 完整三种结束/推进判定：全部段跑完记「已完成」、用户提前结束记「未完成」但照存数据与分段、单段达 3 倍预期基准时长自动强制切段防 GPS 信号差卡死。
- [x] **TTS 语音教练 (`lib/services/run_voice_coach.dart`)**：
  - 引入 `flutter_tts ^4.0.2` + `audio_session ^0.1.25`，初始化前先检测 TTS 可用性，不可用安全降级为震动 + 横幅绝不崩溃；说话时申请 `gainTransientMayDuck` 压低音乐而不打断音乐；支持顶栏一键静音与整公里配速播报。
- [x] **跑步中实时指导 UI & 分段持久化**：
  - 跑步中新增：切段滑入横幅（2.4s 自动收起）+ `HapticFeedback.mediumImpact()` 震动 + 醒目当前段卡片（中文名 / 进度条 / 还剩几分几秒或还剩多少米 / `第 X 段 / 共 Y 段` 总进度 / 语音文案 / 手动跳段）+ 底部「下一段预告」。
  - 跑步首页支持全部 11 门课（含按距离/按时间标签），点击课程先弹出完整分段一览再开跑；跑步结束同步写入 `runs` 与 `run_segments` 并在详情页完整展示已完成/未完成标签与每段明细。
- [x] **跑步→有氧双写闭环 + 配速分档热量 + 删除联动（DB v8）**：
  - `Nutrition.estimateRunKcal` 统一热量口径：按配速分档（`<5'00"` ×1.15 / `<6'30"` ×1.08 / `>8'00"` ×0.95 / 其余 ×1.036），室内/无 GPS 距离时退回 MET 7.0 兜底绝不为 0。
  - SQLite v8 为 `cardio_records` 新增 `source_run_id INTEGER` 与索引（并自动补齐历史老数据）；`Repo.saveRun()` 同事务双写 `type='running'` 有氧记录并直接复用 `runs` 数值，保证 `runs` / 有氧页 / 饮食页热量 100% 一致且绝不重复计算；删除跑步或有氧记录双向同步删除。
  - 新增 `CardioType` 统一常量；有氧记录页支持 `running`（「跑步」+ `directions_run_rounded` + 距离/时长/配速/热量），点击直达 `RunDetailScreen` 查看轨迹。
- [x] 验证：50/50 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.1.1_release.apk`。

### 第三批：Gemini 深夜黑皮肤 + 生图插画/图标 + 轨迹回放与配速曲线（v3.1.2+20）✅ 已完成并出包
- [x] **Gemini 深夜黑高级皮肤 (`lib/theme/app_colors_dark_premium.dart`)**：
  - 精准落地 Gemini 暗色色板（`#000000` → `#0A0E27` 渐变、`#15161A` 无边框表面、`#1E1F24` 胶囊输入框、`#E8EAED` / `#9AA0A6` 文本、`#4285F4` 主强调色与 Gemini 四色）。
  - 通过 `AppSkinExtension`（`ThemeExtension`）与根部固定 `MidnightBackdropLayer`（`RepaintBoundary` 隔离，滚动零重绘背景渐变）实现无边框大圆角（`24dp` 常规卡 / `28dp` 半透明 Hero 卡）、融合式底部导航栏、无边框 AI 对话气泡 + 胶囊输入条、地图暗色蒙版。
  - 设置页升级为三皮肤切换：`默认浅色 / 深色 / 深夜黑`（持久化并平滑兼容旧主题设置）。
- [x] **Gemini 生图 1024×1024 透明 PNG 资产 (`assets/icons/generated/`)**：
  - 生成并精修去底 6 张透明 PNG：`course_fartlek.png`、`course_easy_run.png`、`course_interval.png`、`course_run_walk.png`、`empty_running_whale.png`（大肥鱼赛前拉伸）、`icon_running.png`。
  - 接入健身页跑步入口图标、跑步首页全部课程卡插画，以及无跑步记录空状态（大肥鱼插画 + 鼓励语 + 「立即开始第一次跑步」主按钮）。
- [x] **轨迹动态回放动画 + `fl_chart` 配速曲线 (`RunDetailScreen`)**：
  - 新增 `computePaceCurveSamples()`（自动过滤跳点与暂停断档、动态分桶与 3 点平滑），在跑步详情页渲染 `fl_chart` 平滑配速曲线（纵轴越靠上配速越快，支持触摸查看公里点配速）。
  - 地图轨迹新增一笔平滑插值绘制回放动画（进入自动播放 + 右上角「回放轨迹」重播按钮，严格遵循 `MediaQuery.disableAnimationsOf(context)`）。
- [x] 验证：55/55 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.1.2_release.apk`。

### P0 语音修复补丁（v3.1.3+21）✅ 已完成并出包
- [x] **Android 11+ `<queries>` 补齐 `TTS_SERVICE` 意图**：在 `AndroidManifest.xml` 声明 `android.intent.action.TTS_SERVICE`，修复 OPPO/ColorOS 等 Android 11+ 机型因包可见性限制导致查询/绑定 TTS 引擎失败的问题。
- [x] **`RunVoiceCoach` 根治静默失败 + 分步诊断 + 失败可重试 (`lib/services/run_voice_coach.dart`)**：
  - 增加 `step1~step5` 完整 `debugPrint` 诊断日志与 `lastFailureReason`；独立捕获 `getLanguages` 异常不误杀；支持多候选语言回退（`zh-CN / zh_CN / zh-Hans / zh`）。
  - 移除存在平台兼容性问题的 `awaitSpeakCompletion(false)`；移除初始化失败后永久锁死的 `_initialized` 门控，失败后随时可重试。
  - 新增 `speakSequence()`（等待前句结束 + 间隔防吞字）；所有 `_speak()` 调用增加 `try/catch` 与错误日志。
- [x] **不可用可见弹窗 + 直达系统文字转语音设置 (`MainActivity.kt` + `RunningActiveScreen`)**：
  - 首次进课程若 TTS 不可用，立即弹出明确提示弹窗，提供「知道了」与「去设置」（通过 `com.lifelog/running` → `openTtsSettings` 直达 `TTS_SETTINGS` / 辅助功能设置），点击顶栏语音图标还可随时重试。
  - 不可用时确保分级降级生效：开跑与切段 `HapticFeedback.mediumImpact()` + 顶部滑入横幅，每公里 `HapticFeedback.lightImpact()`。
- [x] **课程开跑主动语音引导**：开跑先播总述（「开始 3 公里法特莱克跑，共 9 段，预计 29 分钟」），间隔 1.5 秒后再播第 1 段提示。
- [x] 验证：59/59 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.1.3_release.apk`。

## v3.2.0：跑步机拍照读数 + 轨迹按配速五档分色（v3.2.0+22）✅ 已完成并出包
- [x] **拍照读跑步机 / 椭圆机 / 动感单车屏幕 (`AiService.analyzeTreadmillImage` + `TreadmillScanScreen`)**：
  - 复用 `SettingsService.visionConfig()` 视觉识别通道，返回结构化 JSON（`distance_km / duration_secs / calories / pace / machine_type / unit_note`）；反光模糊看不清的字段严格返回 `null` 不瞎猜；自动兼容 `mile → km` 换算并注明，兼容 `MM:SS` / `HH:MM:SS` 时长格式。
  - 跑步首页（2×2 入口「拍照记录」）与有氧记录页顶部均提供入口；识别后**必须展示可编辑确认页**（照片缩略图 + 距离/时长/热量/器械类型可修正 + `[重拍]`/`[保存]`）。
  - 保存至 `cardio_records`，新增 `CardioType.treadmill` / `treadmill_fast` / `elliptical` / `bike` 与真实 GPS 跑步区分；热量读不到时自动按 MET 兜底（跑步机 8.0 / 跑步机快跑 11.0 / 椭圆机 5.0 / 动感单车 7.0）。
- [x] **轨迹按配速五档分色 (`RouteSpeedColoring` + `RouteSpeedLegend` + `RouteColorModeToggle`)**：
  - 严格按跑者习惯以配速分五档：`>7:00/km` 蓝灰 `#90A4AE`（慢走）、`6–7` 青 `#4DD0E1`（慢跑）、`5–6` 绿 `#66BB6A`（正常）、`4–5` 橙 `#FFA726`（快跑）、`<4:00` 红 `#EF5350`（冲刺）。
  - 相邻跳点 `> 200m` 直接过滤断开不连线；采用前后各 2 点（5 点）滑动窗口算速度，消除单点 GPS 抖动全红毛刺；同档连续点聚合为多点 Polyline 并将 segment 总数控制在 `<= 300`（严格 `<= 400`），30 分钟数千点轨迹依然流畅不卡顿。
  - **跑步中 (`RunningActiveScreen`) 与详情回放 (`RunDetailScreen`) 同步支持实时/回放分色**，地图右下角展示五档图例，顶部提供 `[单色轨迹 | 速度分色]` 一键切换开关并持久化偏好。
- [x] 验证：68/68 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.2.0_release.apk`。

## v3.3.0 AR 菜单相机 + 调试后端（分批验证）
### 第一批：ML Kit 端侧越南语/英语菜单 OCR 验证（v3.3.0+23）✅ 已完成并出包
- [x] **新增依赖**：`camera: ^0.11.0`、`google_mlkit_text_recognition: ^1.0.3`、`google_mlkit_commons: ^1.0.3`（使用 `TextRecognitionScript.latin` 单识别器，原厂正式支持越南语与英语，零额外语言包）。
- [x] **端侧 OCR 服务 (`lib/services/menu_ocr_service.dart`)**：
  - 实时相机帧转换（Android 优先单平面 `NV21` 零拷贝 + 3-plane `YUV420 → NV21` 兼容兜底 + 精确旋转角计算）。
  - 支持高清拍照与相册图片直接识别（`InputImage.fromFilePath`），返回每块文本、边界框与识别耗时（ms）。
- [x] **临时验证页 (`lib/screens/diet/menu_ocr_lab_screen.dart`) & 入口**：
  - 饮食页顶部快捷入口「菜单 OCR 验证（英/越）」直达。
  - 上半区实时取景 + 闪光灯 + 实时耗时/块数胶囊；操作栏支持「定格画面 / 继续实时 / 拍高清帧 / 相册测图 / 复制文字」；下半区大字号展示识别文本块与坐标，便于实测 `Phở bò` / `Bún chả` 等越南语变音符。
  - 严格遵守第一批边界：暂不接 AI、不做 AR 浮层、不碰调试后端，待实测准确率验收后进入第二批。
- [x] 验证：71/71 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.3.0_release.apk`。

### 第二批：OCR 文字接 AI 翻译 + 可调汇率 + 红绿灯菜品卡片列表（v3.3.1+24）✅ 已完成并出包
- [x] **仅发文字 AI 翻译 (`AiService.translateMenuOcrText` + `parseMenuTranslationResponse`)**：
  - 复用 `SettingsService.visionConfig()`（未单独配识图时自动回退 `chatConfig()`），仅发送 ML Kit 识别文本不发图，大幅省 Token，严格设置 **15 秒超时**。
  - 返回契约严格对齐 `{ fx_rate, items: [{ id, vn, cn, vnd, rmb, kcal, macros, light, tip }] }`，支持 `65k` / `120.000đ` 等越南盾写法容错。
- [x] **可手动覆盖汇率 + 实时重算**：默认填入 AI 返回汇率，用户随时在顶部输入框修改汇率后，所有菜品卡片的人民币价格即时重算。
- [x] **红绿灯菜品卡片列表 (`MenuOcrLabScreen`)**：
  - 按卡片列表清晰展示：红绿灯徽章（挂接 Material 3 色板 `success/warning/danger`）、中文菜名、越南语原文、越南盾 + 人民币折算价（如 `120,000₫ ≈ 34.2元`）、热量 `kcal`、三大营养素与简短提示 `tip`。
  - 完整加载与异常兜底：请求中 loading、AI 未配置时提示并带「去设置配置 API」按钮、超时支持一键「重试翻译」、非合法 JSON 时安全展示原始回复绝不崩溃。
  - 严格遵守分批边界：AR 浮层（Positioned）留到第三批，调试后端留到第四批。
- [x] 验证：75/75 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.3.1_release.apk`。

### P0 实时流热修：修复 CameraX `ImageFormatGroup.nv21` 导致 0 ms / 0 块不识别（v3.3.2+25）✅ 已完成并出包
- [x] **根因定位（已查源码实锤）**：`camera_android_camerax 0.6.30` 在 Android 上使用 `ImageFormatGroup.nv21` 时，会将 `OUTPUT_IMAGE_FORMAT_NV21 (3)` 传给 `ImageAnalysis`，随后调用内部 `ImageProxyUtils.planesToNV21()` 并因平面数校验/布局不匹配抛异常，导致 `startImageStream` 一帧都吐不出来（界面始终停在 `0 ms · 0 块`）。
- [x] **彻底修复 (`menu_ocr_lab_screen.dart` + `menu_ocr_service.dart`)**：
  - Android 统一改用全机型通用的 **`ImageFormatGroup.yuv420`**，彻底绕开 CameraX 内部有坑的 `ImageProxyUtils`，由自研 `MenuOcrService.convertYuv420ToNv21()`（支持 `yRowStride == width` 快路径与独立 U/V stride）安全转换为紧凑 `NV21` 喂给 ML Kit。
  - 若高分辨率 `high` 并发绑定 `ImageAnalysis` 失败，自动降级 `medium` 重试一次。
  - 消灭静默失败：默认进入先显示实时 OCR 原文区；未出首帧前显示「等待相机帧…」而非误导性的 `0 ms · 0 块`；流启动或帧 OCR 发生任何异常直接在取景框底部显示红色错误条。
- [x] 验证：75/75 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.3.2_release.apk`。

### P0 实时流转换兜底热修：自动切换纯 Y 平面 `InputImage.fromBitmap` 彻底规避 `InputImageConverterError`（v3.3.3+26）✅ 已完成并出包
- [x] **问题闭环**：v3.3.2 可视化红条在真机成功捕获 `PlatformException(InputImageConverterError, java.la...)`，定位到部分机型通过 `InputImage.fromBytes` 构造 NV21 失败。
- [x] **双通道无缝兜底 (`menu_ocr_service.dart` + `menu_ocr_lab_screen.dart`)**：
  - 修正奇数分辨率 NV21 UV 向上取整（`(width + 1) ~/ 2`）与单平面长度校验。
  - 新增 `convertYPlaneToRgbaBitmap()` + `buildBitmapInputImageFromCameraImage()`：直接取全机型必有的 `planes[0]` Y 亮度平面生成紧凑 RGBA 位图走 `InputImage.fromBitmap`（Android `ARGB_8888 Bitmap`，彻底绕开 NV21/YUV 格式兼容问题，R=G=B=亮度且超 1280px 自动抽稀）。
  - 帧循环中首次命中 `InputImageConverterError` 立即自动切换 Bitmap 通道并在**同一帧**完成重试，零中断出字；同时取消错误条 `maxLines: 2` 截断并附带帧参数诊断信息。
- [x] 验证：76/76 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.3.3_release.apk`。

### P0 实时流终极修复：Y 亮度平面正立 8-bit 灰度 BMP + `InputImage.fromFilePath`（v3.3.4+27）✅ 已完成并出包
- [x] **终极根治 `InputImageConverterError`**：v3.3.3 完整诊断确认 `google_mlkit_commons 1.0.3` 在 OPPO Find X8 上 `fromBytes`（NV21）与 `fromBitmap`（raw RGBA）两条通道均在 `InputImageConverter` 报异常。
- [x] **改走 `InputImage.fromFilePath` 零兼容坑通路 (`MenuOcrService.encodeYPlaneToUprightGrayscaleBmp` + `processCameraImage`)**：
  - 直接取 Android 全机型统一的 `planes[0]` Y 亮度平面，纯 Dart 同步完成 0/90/180/270 正立旋转并封装为标准 8-bit 灰度 BMP（含 54 字节头 + 1024 字节调色板 + 4 字节行对齐，720p 仅 ~0.9MB、编码 <3ms）。
  - 复用单个缓存文件走 `InputImage.fromFilePath`（与高清拍照/相册测图完全同一条零坑原生链路，退出页面自动清理临时文件），且输出边界框直接是正立坐标系（为第三批 AR 浮层铺路）。
- [x] 验证：77/77 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.3.4_release.apk`。

### P0 方案重构：废弃自研编码器，改用 `takePicture()` 定时抓帧 + 原图 `InputImage.fromFilePath`（v3.3.5+28）✅ 已完成并出包
- [x] **一步到位零格式转换**：移除全部手写 YUV420→NV21、Y→RGBA、8-bit 灰度 BMP 编码器及 `startImageStream`，彻底消除跨机型格式兼容风险与维护负担，完整保留菜单彩色对比度与越南语声调符号（`ế ệ ộ`）清晰度。
- [x] **`takePicture()` 定时抓帧 (`menu_ocr_lab_screen.dart` + `menu_ocr_service.dart`)**：
  - 相机初始化后默认锁定 `FlashMode.off`（避免暗光餐厅定时抓帧连续触发自动闪光灯），以 `Timer.periodic(1200ms)` 配合防重入锁 `_processingFrame` 与 `isTakingPicture` 校验定时调用 `takePicture()`。
  - 直接走硬件编码 JPEG + `InputImage.fromFilePath(path)`，由 `MenuOcrService.processFilePath(..., deleteAfter: true)` 在 `finally` 块自动删除临时抓帧文件（相册测图保持 `deleteAfter: false` 绝不删用户原图）。
  - 手动「拍高清帧」自动先停定时器并等待在途抓帧收尾，杜绝并发 `takePicture()` 冲突。
- [x] 验证：75/75 测试通过，`analyze` 0 error / 0 warning，UI 规范检查 0 问题，APK：`LifeLog_v3.3.5_release.apk`。

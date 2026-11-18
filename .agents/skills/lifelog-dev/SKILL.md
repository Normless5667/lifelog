---
name: lifelog-dev
description: Development handoff guide for the LifeLog Android app (Flutter). Read this FIRST before doing any work on this project - it contains requirements, architecture, environment setup, current progress and next steps. Update the "Progress Log" section after every meaningful change.
---

# LifeLog 开发交接手册 (Handoff)

> **给接手的模型 / 开发者**：先完整读完本文件再动手。每完成一个有意义的步骤，**必须更新底部的「进度日志」和「下一步」**，让下一个接手的人能无缝继续。

## 1. 项目概述

个人生活记录 Android App，用户分享给亲友使用（APK 侧载安装，不上架）。

- **平台**：仅 Android
- **语言**：仅简体中文（UI 文案直接硬编码中文，不做 i18n）
- **框架**：Flutter (stable 3.50.0, Dart 3.14)
- **数据**：全部本地 SQLite（sqflite），无后端
- **AI**：OpenAI 兼容 Chat Completions 接口，默认 DeepSeek
  - 对话/建议/总结 → 对话模型（默认 `https://api.deepseek.com` + `deepseek-chat`）
  - 拍照识别热量 → 识图模型（可单独配置 base url / key / model；默认与对话相同）
  - 用户先**拍照/选图**，再把图片 base64 发给模型（不是实时识别）
  - ⚠️ DeepSeek 是否原生支持图片输入未经官方文档确认（网传 `deepseek-flash` 支持）。所以识图模型做成可配置，失败可换通义千问 VL 等。
- **API Key**：用户在 App 设置页自己填写，存 `flutter_secure_storage`。**绝不能把 Key 写进代码或提交到仓库。**

原始需求报告：见对话 artifact `life_tracker_app_report.md`（已复制到 `docs/requirements.md`）。

## 2. 功能范围

### 第一期 MVP（当前目标）
1. **课表**：周视图网格、单双周/起止周、学期开始日期自动算当前周、点击空格添加、点击课程编辑
2. **饮食**：按日按餐（早/午/晚/加餐）记录；拍照 → AI 估算（名称/份量/热量/蛋白/碳水/脂肪）→ 可编辑后保存；文字描述估算；手动添加；每日热量目标进度、三大营养素统计
3. **训练**：动作库（预置 + 自定义）；训练会话；每组 重量×次数、热身组标记；显示该动作上次成绩；历史记录；总训练量
4. **身体数据**：性别/年龄/身高/活动水平/目标；体重记录与曲线；BMR(Mifflin-St Jeor)/TDEE/每日热量目标自动计算
5. **AI 助手**：带个人数据上下文的对话；快捷按钮（今日总结、本周总结、饮食建议、训练建议）；聊天记录本地保存
6. **设置**：AI 配置（对话 + 识图）、测试连接、数据导出 JSON

### 第二期（未开始）
上课提醒通知、休息计时器、训练模板、PR/1RM、动作进步曲线、常用食物/复制昨天、饮水、导入导出恢复、深色模式开关

## 3. 架构

```
lib/
  main.dart                 入口，MaterialApp + 底部导航 (HomeShell)
  db/database.dart          sqflite 单例，建表 + 预置动作数据
  models/                   纯数据类 (toMap/fromMap)
  services/
    ai_service.dart         OpenAI 兼容接口：chat()、analyzeFoodImage()、estimateFoodText()
    settings_service.dart   AI 配置（secure storage）+ 普通设置（kv 表）
    nutrition.dart          BMR/TDEE/目标计算
    context_builder.dart    为 AI 组装用户数据上下文
  screens/
    home_screen.dart        今日仪表盘
    schedule/               课表
    diet/                   饮食
    workout/                训练
    body/                   身体数据
    ai/                     AI 对话
    settings/               设置
  widgets/                  通用组件
```

- **状态管理**：刻意保持简单——`StatefulWidget` + 直接调用 DB 仓库方法 + 返回后刷新。不引入 Riverpod/Bloc，降低交接成本。
- **数据库**：`lib/db/database.dart`，修改表结构时**必须升级 `_dbVersion` 并在 `onUpgrade` 中写迁移**（用户手机上已有数据）。
- 日期统一存 `yyyy-MM-dd` 字符串；时间戳存毫秒 int。

### 数据表
| 表 | 字段 |
|---|---|
| kv | key TEXT PK, value TEXT |
| courses | id, name, teacher, location, weekday(1-7), start_section, end_section, start_week, end_week, week_type(0全/1单/2双), color(int) |
| meals | id, date, meal_type(0早1午2晚3加餐), name, amount, calories, protein, carbs, fat, photo_path, note, created_at |
| body_records | id, date(UNIQUE), weight, body_fat, waist |
| exercises | id, name, category, is_custom |
| workouts | id, date, start_time, end_time, note |
| workout_sets | id, workout_id, exercise_id, set_index, weight, reps, is_warmup |
| chat_messages | id, role, content, created_at |

## 4. 开发环境（Windows）

- Flutter SDK：`C:\Users\33239\dev\flutter`（⚠️ **重要**：本机 PowerShell 会卡死，已将 `C:\Users\33239\dev\flutter\bin\flutter.bat` 替换为指向 `C:\Users\33239\dev\flutter-nops.bat`，直接通过 `dart.exe` 运行 `flutter_tools.snapshot`，完全绕过 PowerShell。执行命令请使用 `cmd /c` 调用 `C:\Users\33239\dev\flutter-nops.bat`）
- Android SDK：`C:\Users\33239\dev\android-sdk`（已安装 `cmdline-tools/latest`、`platform-tools`、`platforms;android-35`、`platforms;android-36`、`build-tools;35.0.0`、`build-tools;36.0.0`、`ndk;28.2.13676358`、`cmake;3.22.1`）
- JDK 17：`C:\Program Files\Eclipse Adoptium\jdk-17.0.21.9-hotspot`（注意：AGP 9.3.1 的 `lintVital` 在 JDK 17 下会因调用 JDK 21 的 `List.removeLast()` 崩溃，已在 `android/build.gradle.kts` 中禁用所有 `lintVital` 任务）
- 项目目录：
  - 主工程：`C:\Users\33239\.gemini\antigravity\scratch\lifelog`
  - 持久备份：`C:\Users\33239\Documents\LifeLog`
- Git：已使用 Flutter 内置的 `C:\Users\33239\dev\flutter\bin\mingit\cmd` 加入 `flutter-nops.bat` 的 `PATH`。

常用命令（在 `cmd /c` 下运行，避免触发 PowerShell）：
```bat
cd /d C:\Users\33239\.gemini\antigravity\scratch\lifelog
C:\Users\33239\dev\flutter-nops.bat pub get
C:\Users\33239\dev\flutter-nops.bat analyze
C:\Users\33239\dev\flutter-nops.bat build apk --release
```

## 5. 约定
- UI 文案中文；代码标识符英文
- 用 Material 3，主题色 teal
- AI 返回 JSON 时要容错（去掉 ```json 代码块、截取第一个 { 到最后一个 }）
- 所有 AI 调用都要 try/catch 并向用户显示友好错误（未配置 Key 时引导去设置页）

## 6. 进度日志（倒序，最新在上）

- **2026-11-18 (阶段 6 - 生活助手 v1.2 `1.2.0+3` 全量升级与打包完成)**：
  - **P0 正式签名 + 桌面图标 + 改名「生活助手」+ 通知诊断页**：
    - 使用 `keytool` 生成正式签名文件 `android/app/lifelog-release.jks`（并备份于 `C:\Users\33239\dev\lifelog-release-backup.jks`），配置 `android/key.properties` 与 `android/app/build.gradle.kts` `signingConfigs`。
    - 桌面应用图标采用 `assets/icon/app_icon.png`（深蓝渐变 + 日历 + 心跳线 + 星芒），通过 `flutter_launcher_icons` 生成全套分辨率与自适应图标；App 内部彩蛋（`AboutScreen`、首页 AI 入口与 `EmptyHint` 空状态）采用从官方三视图 `dafeiyu_reference.png` 100% 保真裁切出的 `assets/icon/dafeiyu_mascot.png`。
    - 改名为 **「生活助手 (Life Assistant)」**，新增独立「通知与震动诊断页」`notification_diagnostics_screen.dart`，可实时查看通知总开关、渠道重要性、震动、声音、精确闹钟权限及一键跳系统设置。
  - **P1 校车时刻表 + 天气集成 + 硬件计步器 + API 预设简化**：
    - 新增 `assets/bus_schedule.json`（完整收录 Hai Ba Trung Route 去程/回程 5 个时段全部站点，保留原图 `BUY CAMPUS` 拼写）、`bus_service.dart` 与 `bus_schedule_screen.dart`：支持选常用站点、首页实时显示「下一班 XX:XX，还有 N 分钟」倒计时、仅周一至周五到站前震动提醒。
    - 新增 `weather_service.dart`：接入免费无 Key 的 Open-Meteo API（带 30 分钟本地缓存与 IP 定位兜底），首页顶部显示天气卡片、课表页下雨天显示带伞提示、每日 07:00 推送天气简报，并注入 `ContextBuilder` 供 AI 参考。
    - 新增原生硬件计步传感器支持（`MainActivity.kt` `Sensor.TYPE_STEP_COUNTER` + `step_service.dart` 每日零点基准重置与降级提示），首页展示步数进度环，并将步数消耗自动计入 `DailyTargets` 动态饮食目标。
    - `settings_screen.dart` 与 `ai_service.dart` 支持 Base URL 预设芯片（DeepSeek / OpenAI / 通义千问）及简写自动补全（只填 `deepseek` 自动补全路径）、模型预设选择与一键测试连接。
  - **P1 界面美化（Keep 风格）+ 双语切换 + 三档字号 + 桌面小组件 (AppWidget) + 首页快捷 FAB**：
    - 升级 `main.dart` 与 `app_prefs.dart`：深蓝 `#2B5B84` + 活力橙 `#FF7A22` 配色、20dp 大圆角卡片、深色模式（跟随系统/浅色/深色）、字体大小三档调节（小/标准/大）、中英双语切换（`lib/l10n/app_zh.arb` & `app_en.arb`）。
    - 新增 Android 原生桌面小组件 `LifeAssistantWidgetProvider.kt`（展示今日课程 + 剩余热量 + 今日步数）及首页右下角快捷记录 FAB。
  - **编译与归档**：`flutter analyze` 0 error / 0 warning，已产出正式签名的 `v1.2.0+3` Debug 与 Release APK，同步至 `C:\Users\33239\Desktop\LifeLog_APK\`。
- **2026-11-17 (阶段 5 - LifeLog v1.1 `1.1.0+2` 全面升级与打包完成)**：
  - **P0 课表提醒不震动修复（适配 OPPO Find X8 / ColorOS 15）**：
    - `CourseReminderReceiver.kt` 升级为全新通知渠道 `course_reminders_v2`（因为 Android 不会更新已存在渠道的震动属性），显式设置 `vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 600)`、闹钟铃声 `RingtoneManager.TYPE_ALARM`、`setDefaults(DEFAULT_ALL)`、`setVibrate(pattern)`、`setCategory(CATEGORY_ALARM)` 与 `setFullScreenIntent(contentPi, true)`，并在广播触发时直接调用硬件 `Vibrator`（`AudioAttributes.USAGE_ALARM`）双保险震动。
    - 课表设置弹窗新增 ColorOS 渠道降级检测（`checkNotificationStatus`）与一键跳系统渠道设置按钮（`Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS`），并新增「用系统时钟 App 闹钟提醒（`AlarmClock.ACTION_SET_ALARM`）」可选开关与一键写入下一节课按钮。
  - **P1 健身板块改造**：
    - 数据库升级至 `_dbVersion = 3`，新增 `cardio_records` 独立有氧表（支持走路/快走/慢跑/中速跑/骑行/游泳/跳绳/其他，按 `MET × 体重kg × 小时` 自动计算消耗 kcal）。
    - `workout_session_screen.dart` 升级为「开始 → 实时计时 (`mm:ss`) → 结束」会话模式，自动开启 `FLAG_KEEP_SCREEN_ON`；每组右侧新增 `✓` 完成按钮，点按自动启动**组间休息倒计时**（可设 60/90/120/180 秒，支持暂停/+15s/跳过，同时注册后台 `AlarmManager` 闹钟确保切后台也准时震动弹窗）。
  - **P1 AI 模块升级**：
    - `ai_chat_screen.dart` 支持请求并解析结构化 JSON 训练计划（`plan_name` + `days`），气泡下方自动显示「导入到训练计划」按钮；导入后在 `workout_list_screen.dart` 顶部卡片展示，点任意分化直接带出全部动作与组数开练。
    - 新增首次使用引导问卷 `onboarding_sheet.dart`（性别、年龄、身高、体重、目标、经验、每周天数、单次时长、可用器械、伤病限制），存入 `Profile` 并注入 `ContextBuilder`。
  - **P1 动态饮食热量目标 + 第五节 4 项高价值特性**：
    - `DailyTargets.load` 改为动态计算：`每日总消耗 = BMR × 活动系数 + 当日训练消耗(力量 MET 5.0 + 有氧 MET)`，减脂 -18%，增肌 +12%；`CalorieSummaryCard` 底部清晰展示：**基础代谢 / 训练消耗 / 今日摄入 / 剩余额度**。
    - 首页新增 **连续打卡天数（Streak）** 徽章与 **一句话 AI 速记饮食输入框**；身体页体重趋势图新增 **红色虚线目标体重线**；设置页新增 **JSON 与 Excel CSV 双格式导出**。
  - **编译与归档**：`flutter analyze` 0 error / 0 warning，已产出 `v1.1.0+2` Debug 与 Release APK，同步至 `C:\Users\33239\Documents\LifeLog` 及 `C:\Users\33239\Desktop\LifeLog_APK\`。
- **2026-11-17 (阶段 4 - 课表自动导入 + 课前闹钟提醒 + 全界面图标化视觉大升级)**：
  - **内置用户真实课表**：数据库升级至 `_dbVersion = 2`（含平滑 `onUpgrade` 迁移），内置用户 5 张 `My Schedule` 截图中的全部 9 门课程排期（`Database Principles and Applications`、`Introduction to Machine Learning`、`UX Design` 周一至周五时间、教室、老师）。
  - **多种课表导入方式**：课表页右上角新增「导入课表」菜单，支持：① 一键载入默认课表、② 相册选课表截图 AI 自动识别、③ 拍照识别课表、④ 粘贴教务文字/JSON 由 DeepSeek 解析。
  - **原生课前通知提醒**：新增 `CourseReminderReceiver.kt`、`MainActivity.kt` MethodChannel（`com.lifelog/reminders`）和 `lib/services/reminder_service.dart`，通过 Android `AlarmManager` 实现课前准时弹窗+震动提醒（支持提前 5/10/15/30 分钟设置及「立即测试提醒通知」）。
  - **全面图标化与视觉层次升级**：
    - 底部导航栏与首页 4 大模块入口升级为 48dp 彩色圆角方块底 + 白色圆角图标（`Icons.*_rounded`）。
    - 空状态（`EmptyHint`）升级为 112dp 低透明度主题色圆底 + 72dp 图标 + 引导文案 + 主操作按钮。
    - 饮食页、训练页（新增近期训练容量柱状图 `_volumeBarCard` 与肌群专属彩色图标）、身体页（6 宫格彩色统计徽章 + 单点也能渲染的 `fl_chart` 曲线）全面可视化。
    - 所有编辑弹窗（`meal_edit_dialog.dart`、`course_edit_screen.dart`、`profile_screen.dart`、`_BodyRecordDialog`）的输入框均加上语义前缀图标，全局统一 16dp 卡片圆角与 12dp 输入框圆角。
  - **重新编译产出 Debug、Release APK 及微信免拦截压缩包**，并已同步至 `C:\Users\33239\Documents\LifeLog`。
- **2026-11-17 (阶段 3 - MVP 编译与打包完成)**：
  - 解决了本机 PowerShell 挂死的问题（`flutter-nops.bat` 绕过 PowerShell，并覆盖了 `flutter\bin\flutter.bat` 防止 Gradle 内部回调卡死）。
  - 安装完成 Android 35/36、Build-Tools、NDK 28.2.13676358、CMake 3.22.1。
  - 修复 `lib/services/nutrition.dart` 中 `double` 作为 `const Map` 键的编译报错，`flutter analyze` 0 error。
  - 在 `android/build.gradle.kts` 中禁用 JDK 17 下崩溃的 `lintVital` 任务。
  - **成功编译产出 Debug 与 Release APK**：
    - `build\app\outputs\flutter-apk\app-debug.apk`
    - `build\app\outputs\flutter-apk\app-release.apk` (55.4 MB)
  - 已将完整工程与产物同步备份至 `C:\Users\33239\Documents\LifeLog`。
- **2026-11-17 (阶段 2)**：
  - Flutter 3.50.0 与 Android cmdline-tools 已下载完成（位于 `C:\Users\33239\dev\_downloads`）。
  - MVP 全部 Dart 源码已编写完毕。
- **2026-11-17 (阶段 1)**：确定需求（安卓 / 中文 / 亲友分享 / DeepSeek 方案A 可配置识图模型）。

## 7. 下一步（TODO - 第二期扩展功能）

- [ ] **上课提醒与训练组间休息计时器**：接入本地通知或震动提醒
- [ ] **训练模块进阶**：训练计划/模板（如推/拉/腿一键开练）、个人记录（PR）与估算 1RM、单动作重量/容量进步曲线（`fl_chart`）
- [ ] **饮食模块进阶**：常用食物收藏、一键复制昨天某餐、饮水打卡、課表截图 AI 识别导入
- [ ] **数据恢复**：在设置页支持从导出的 JSON 备份文件恢复数据
- [ ] （可选）将 `package:flutter/material.dart` 迁移至 Flutter 3.50 新推的 `package:material_ui/material_ui.dart` 以消除 info 级别提示

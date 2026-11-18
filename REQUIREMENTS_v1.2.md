# 生活助手 v1.2 需求（老大第二批实测反馈）

> 基于 v1.1 打完包之后的反馈。优先级 P0 = 关键/影响使用，P1 = 这版做，P2 = 下版

---

## 一、天气集成（P1）

**需求**：接入手机天气，每天播报。

**技术做法**（不用第三方 SDK，省钱且稳）：
- **Open-Meteo**（`https://api.open-meteo.com/v1/forecast`）—— 完全免费、无需 API Key、
  支持按经纬度查询、返回 JSON。这是最优选。
- 定位：`geolocator` 插件（Android 需要 `ACCESS_FINE_LOCATION` 权限）。
  也可以用 `IP 定位兜底`（拿不到 GPS 权限时用公网 IP 查城市）。
- 缓存：天气数据缓存 30 分钟，别每次都请求。

**展示位置**：
1. 首页顶部卡片：今日天气 + 温度 + 一句话（"今天 28°C 有雨，记得带伞"）
2. 课表页：如果当天有雨，提醒一句
3. AI 上下文：把天气塞进 `context_builder`，AI 建议会更贴合（下雨天不会建议你户外跑步）

**通知**：每天早上 7:00 推一条天气简报（走已有的通知渠道）。

---

## 二、校车时刻表（P1，重点）

**老大给的时刻表**（Hai Ba Trung Route，2026.11.16–11.20，周一到周五）：

### 去程（Hai Ba Trung → BUV Campus）
| 站点 | Slot1 | Slot2 | Slot3 | Slot4 | Slot5 |
|---|---|---|---|---|---|
| LE DAI HANH | 07:40 | 09:40 | 10:40 | 12:00 | 13:30 |
| TIMES CITY | 07:55 | 09:55 | 10:55 | 12:15 | 13:45 |
| AEON MALL LONG BIEN | 08:05 | 10:05 | 11:05 | 12:25 | 13:55 |
| RUNG CO - E2 BUILDING | 08:20 | 10:20 | 11:20 | 12:35 | 14:10 |
| BUY CAMPUS | 08:25 | 10:25 | 11:25 | 12:40 | 14:15 |
| SKY OASIS | 08:28 | 10:28 | 11:28 | 12:43 | 14:18 |
| SOL FOREST | 08:28 | 10:28 | 11:28 | 12:43 | 14:18 |
| SKY FOREST | 08:29 | 10:29 | 11:29 | 12:44 | 14:19 |
| LANDMARK | 08:30 | 10:30 | 11:30 | 12:45 | 14:20 |
| SWANLAKE | 08:30 | 10:30 | 11:30 | 12:45 | 14:20 |
| WESTBAY - B BUILDING | 08:31 | 10:31 | 11:31 | 12:46 | 14:21 |
| WESTBAY - C BUILDING | 08:31 | 10:31 | 11:31 | 12:46 | 14:21 |
| AQUABAY - SKY 2 BUILDING | 08:34 | 10:34 | 11:34 | 12:49 | 14:24 |
| AQUABAY - PARK 1 BUILDING | 08:34 | 10:34 | 11:34 | 12:49 | 14:24 |
| BUY CAMPUS（到校） | 08:40 | 10:40 | 11:40 | 13:00 | 14:30 |

### 回程（BUV Campus → Hai Ba Trung）
| 站点 | Slot1 | Slot2 | Slot3 | Slot4 | Slot5 |
|---|---|---|---|---|---|
| BUY CAMPUS（发车） | 11:30 | 12:30 | 13:30 | 15:15 | 17:35 |
| SKY OASIS | 11:33 | 12:33 | 13:33 | 15:18 | 17:38 |
| SOL FOREST | 11:33 | 12:33 | 13:33 | 15:18 | 17:38 |
| SKY FOREST | 11:34 | 12:34 | 13:34 | 15:19 | 17:39 |
| LANDMARK | 11:35 | 12:35 | 13:35 | 15:20 | 17:40 |
| SWANLAKE | 11:35 | 12:35 | 13:35 | 15:20 | 17:40 |
| WESTBAY - B BUILDING | 11:36 | 12:36 | 13:36 | 15:21 | 17:41 |
| WESTBAY - C BUILDING | 11:36 | 12:36 | 13:36 | 15:21 | 17:41 |
| AQUABAY - SKY 2 BUILDING | 11:42 | 12:42 | 13:42 | 15:27 | 17:47 |
| AQUABAY - PARK 1 BUILDING | 11:42 | 12:42 | 13:42 | 15:27 | 17:47 |
| RUNG CO - E2 BUILDING | 11:45 | 12:45 | 13:45 | 15:30 | 17:50 |
| AEON MALL LONG BIEN | 12:00 | 13:00 | 14:00 | 15:45 | 18:05 |
| TIMES CITY | 12:10 | 13:10 | 14:10 | 15:55 | 18:15 |
| LE DAI HANH（终点） | 12:25 | 13:25 | 14:25 | 16:10 | 18:30 |

### 功能要求
- **选站**：让用户设一个「常用站点」（从上面列表里选），只关心那一站的时刻
- **倒计时**：首页显示「下一班 07:40，还有 12 分钟」
- **提醒**：车到站前 N 分钟（可设 5/10/15 分钟）推通知，走已有的提醒渠道
- **仅周一到周五**：周末/节假日不提醒
- **数据硬编码**：这张表放在 `assets/bus_schedule.json`，别写死在 Dart 代码里
- **可维护**：给个「校车时刻表变更」的说明，以后换学期改 JSON 就行

**注意**：Slot 表里 "BUY CAMPUS" 是原图拼写（应为 BUV），照原样保留免得对应不上。

---

## 三、通知更醒目（P0，实测）

老大说现在的通知不够显眼。要做的：

1. **用全屏 Intent（Heads-up）**：
   ```kotlin
   setFullScreenIntent(pendingIntent, true)  // 锁屏也能弹出来
   .setCategory(NotificationCompat.CATEGORY_ALARM)
   .setPriority(NotificationCompat.PRIORITY_MAX)
   ```
2. **加震动**（v1.1 已经修了，确认 v1.2 别退回去）
3. **加声音**：`setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))`
4. **加 LED 闪烁**：`enableLights(true)`
5. **OPPO 特殊处理**：ColorOS 有自己的「通知importance」分级，
   加一个「一键跳转设置」按钮，直接打开 `Settings.ACTION_APP_NOTIFICATION_SETTINGS`，
   让用户自己把 LifeLog 提到「重要」
6. **加一个「通知诊断」页**：显示当前通知权限状态、渠道重要性、是否被系统降级，
   用户能自己排查为什么没响

---

## 四、改名 + 英文版（P1）

**改名**：LifeLog → **生活助手**（英文 Life Assistant）

要改的地方：
- `pubspec.yaml` 的 `name`（Android 包名 `com.lifelog.lifelog` 建议保留，改包名要重装）
- `android/app/src/main/AndroidManifest.xml` 的 `android:label`
- 所有界面标题、App 内文案
- 通知渠道名

**英文版**：
- 用 Flutter 自带的 `flutter_localizations` + `intl`（已经在依赖里了）
- 建 `lib/l10n/app_en.arb` 和 `app_zh.arb` 两个文件
- 设置页加语言切换：跟随系统 / 中文 / English
- **注意**：中文文案有 300+ 条，先做界面骨架的翻译（导航、按钮、标题），
  长文本（AI 提示词、帮助说明）可以留中文

---

## 五、API 配置简化（P1）

**需求**：Base URL 只填 deepseek 就能用，不用填完整 URL。

**做法**：
- 设置页的 Base URL 字段加**预设下拉**：
  - DeepSeek（默认）：`https://api.deepseek.com`
  - OpenAI：`https://api.openai.com/v1`
  - 通义千问：`https://dashscope.aliyuncs.com/compatible-mode/v1`
  - 自定义（手填）
- 只填域名时自动补 `/v1/chat/completions` 路径
- 提供「测试连接」按钮，点了立刻验证 Key 和 URL 对不对
- 模型名也给预设：deepseek-chat / deepseek-reasoner，可自定义

---

## 六、安装包签名和图标（P0，观感问题）

老大说「安装的时候看着像非法软件」。这是**没有正式签名 + 用默认 Flutter 图标**导致的。

### 6.1 正式签名（必须做）
现在用的是 debug 签名，Android 会标记为「未知来源」。要做：
1. 用 `keytool` 生成 keystore（我可以帮你生成，见附录）
2. `android/key.properties` 配置签名信息
3. `android/app/build.gradle.kts` 里配置 `signingConfigs`
4. 用 release 签名重新打包

**注意**：keystore 文件绝对不能丢失，丢了以后无法更新同一个 App（只能让用户卸载重装）。

### 6.2 应用图标
现在用的是 Flutter 默认图标。要做：
- 用 `flutter_launcher_icons` 插件，一套图自动生成所有尺寸
- 图标设计：目前四个角色里，建议用**大肥鱼（DeepSeek 蓝发女仆）**的头像做图标，
  因为这是老大最熟悉的形象。或者用简洁的「日历 + 心跳」组合图形。
- 需要一张 1024×1024 的 PNG 源图

### 6.3 应用信息
`android/app/build.gradle.kts`：
```kotlin
defaultConfig {
    applicationId = "com.lifelog.lifelog"
    versionCode = 3
    versionName = "1.2.0"
}
```
- 加 `android:label="生活助手"`
- 加应用描述（在 Play Store 和系统设置里显示）

---

## 七、步数自动记录（P1）

**需求**：不用手动计，直接读手机步数。

**技术做法**：
- Android 用 `TYPE_STEP_COUNTER` 传感器（硬件级，不耗电，但只有 Android 4.4+ 且部分机型被阉割）
- 备选 `TYPE_STEP_DETECTOR`
- Flutter 插件：`pedometer`（比较成熟）或 `health` 插件（走 Health Connect）
- **权限**：Android 10+ 需要 `ACTIVITY_RECOGNITION` 运行时权限

**注意的点**：
- `TYPE_STEP_COUNTER` 返回的是**开机以来的总步数**，需要存一个基准值来算「今天走了多少」
- 每天零点重置基准
- 如果传感器不可用（部分模拟器/老机型），要有降级方案：显示「设备不支持」

**展示**：
- 首页今日步数 + 目标进度环
- 健身页：把步数折算成消耗，加到当天的活动消耗里（影响饮食的动态目标）

---

## 八、界面美化（参考 Keep）（P1）

Keep 的核心设计语言：
1. **大圆角卡片**（20-24dp），有轻微阴影
2. **主色 + 强调色**：一个主色贯穿，重要数据用强调色（比如橙色/绿色）
3. **大量留白**，不要塞满
4. **数据可视化**：环形进度、条形图、折线图，不要纯数字
5. **底部导航 5 个项**，选中项有填充+颜色
6. **卡片式列表**，每张卡有明确的主次信息层级

**给 LifeLog 的落地建议**：
- 定一套色板：主色深蓝（呼应大肥鱼）、强调色橙（活跃/进度）、
  背景浅灰白、卡片纯白、深色模式深灰
- 圆角统一：卡片 20、按钮 16、输入框 12
- 阴影：`BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: Offset(0,2))`
- 字体：标题 20/18，正文 14，说明 12，都加适当的字重对比
- 间距：8 的倍数，页面左右边距 16

---

## 九、我补充的建议（按价值排序）

### P1（这版做）
1. **桌面小组件（Widget）**：安卓的 `AppWidget`，显示「今日课程 + 剩余热量 + 步数」。
   这是生活类 App 最有价值的功能之一，不用打开 App 就能看。
2. **快捷记录悬浮按钮（FAB）**：首页右下角一个 + 按钮，长按弹出「快速记饮食 / 快速记训练 / 快速记体重」，
   比点进对应模块快得多。记录成本越低越能坚持。
3. **深色模式 + 跟随系统**：现在可能只有浅色。加 `ThemeMode.system`。
4. **字体大小调节**：设置里给三挡（小/中/大）。你经常在外面看，大一点会舒服。

### P2（下版）
5. **AI 对话历史保存**：现在对话应该是每次清空的。存起来，能回顾之前聊过什么。
6. **常用食物一键收藏**：吃过的食物收藏起来，下次一秒记录。
7. **每周数据总结**：周日推一条「这周练了 3 次、平均摄入 2100、体重 -0.5kg」。
8. **训练动作图示**：每个动作配一张示意图或者 GIF，不然不知道怎么做。

### 明确不建议
- 云同步（要后端，成本和复杂度不值，用数据导出兜底就行）
- 社交功能（一个人用的 App 加社交是负担）
- 跑步 GPS 轨迹（要定位权限、耗电，体验也一般）

---

## 十、版本规划
- 1.0：初版
- 1.1：震动修复、图标改造、训练会话、AI 计划导入、饮食动态目标（**已完成**）
- **1.2**：本文件的全部 P0 + P1
- 1.3：P2

---

## 附录：keystore 生成命令

```bash
keytool -genkey -v -keystore lifelog-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias lifelog \
  -storepass <你的密码> -keypass <你的密码> \
  -dname "CN=Life Assistant, OU=Personal, O=Personal, L=Hanoi, ST=Hanoi, C=VN"
```

生成后：
1. 文件放在 `android/app/lifelog-release.jks`
2. 建 `android/key.properties`：
```
storePassword=<密码>
keyPassword=<密码>
keyAlias=lifelog
storeFile=lifelog-release.jks
```
3. `build.gradle.kts` 里读这个文件配置 signingConfigs

**再次强调**：这个 jks 文件要备份，丢了就永远无法更新同一个 App。

---

## 环境提醒（还是老问题）
- 所有 flutter 命令走 `C:\Users\33239\dev\flutter-nops.bat`（PowerShell 是坏的）
- 项目已经在 `C:\Users\33239\Documents\LifeLog`（终于挪对了，保持)
- analyze 到 0 error 再打包

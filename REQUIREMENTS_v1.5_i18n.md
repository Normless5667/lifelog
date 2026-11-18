# LifeLog v1.5 需求：i18n 彻底改造（切英文不全切）

> 老大实测：切到英文后，底部导航和四个快捷入口变英文了，但
> 「一句话速记今天吃了什么」「AI速记」「剩余额度」「基础代谢」「训练消耗」
> 「今日摄入」这些还是中文。**中英混排。**

---

## 一、根因分析（我查过了）

### 现状
1. **`lib/l10n/app_en.arb` 和 `app_zh.arb` 各只有 10 个词条**（appTitle / tabToday /
   tabSchedule / tabDiet / tabWorkout 等）。这就是为什么只有导航栏那几个字变了。
2. **60 处用了 `prefs.tr('中文', 'English')`** 这种双参数硬编码，散在 6 个文件里。
3. **167 处直接写死中文**，完全没走翻译（`Text('快速记录')` 这种）。

### `prefs.tr()` 这个方案的三个问题
1. **文案不是数据，是代码**：加第三种语言要改 60 个地方
2. **无法做复数/性别/格式**：英文 "1 day" vs "3 days"
3. **无法外部翻译**：没法把 .arb 丢给翻译人员

### 结论
这不是「补几条翻译」的事，是架构问题。但**也不需要推倒重来**——Flutter 官方
`flutter_localizations` + `gen-l10n` 就是标准方案，现在只用了 10%。

---

## 二、要做的（分三步，按优先级）

### 第一步：把 arb 从 10 条补到覆盖全部 UI 文案（P0）

1. 扫描 `lib/` 下所有界面文案（中文的），提取成 key 放进 `app_zh.arb`
2. 补 `app_en.arb` 对应英文
3. 按模块分组命名，key 要见名知意：

```json
{
  "tabToday": "今天",
  "tabSchedule": "课表",

  "homeQuickRecord": "⚡ 快速记录",
  "homeQuickDiet": "快速记饮食 / 拍照识热量",
  "homeQuickWorkout": "快速开始训练 / 记有氧",
  "homeQuickWeight": "快速记今日体重",
  "homeQuickBus": "查看校车时刻表与换站",

  "homeQuickLogHint": "一句话速记今天吃了什么…",
  "homeAiQuickLog": "AI速记",

  "dietRemaining": "剩余额度",
  "dietTarget": "目标",
  "dietProtein": "蛋白质",
  "dietCarbs": "碳水",
  "dietFat": "脂肪",
  "dietBmr": "基础代谢",
  "dietTrainingBurn": "训练消耗",
  "dietTodayIntake": "今日摄入",
  "dietSurplus": "剩余",

  "homeStreakDays": "{count}-Day Streak",
  "homeStreakHint": "Keep up the great momentum!",

  "weatherAutoLocate": "自动 GPS 定位 (6h缓存)",
  "weatherSearchCity": "去设置页搜索更多城市",
  "weatherUmbrellaHint": "记得带伞",
  "stepAuthorize": "授权计步"
}
```

4. 配置 `l10n.yaml`：
```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```
5. `pubspec.yaml` 加 `flutter: generate: true`

### 第二步：把所有 `prefs.tr(a, b)` 和硬编码中文换成 `AppLocalizations.of(context)!.key`（P0）

- 60 处 `prefs.tr()` → 改掉
- 167 处硬编码 → 改掉
- **注意**：`prefs.tr()` 在很多地方没有 BuildContext（比如 service 层），
  这类地方要把文案生成上移到 UI 层，或者传 context 进来
- 干掉 `prefs.tr()` 这个方法（留着会有人继续用错）

### 第三步：把语言切换接到 `MaterialApp.locale`（P0）

现在应该是自己维护了一个 `locale` 字符串 + 通知重建。要改成：

```dart
MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: prefs.localeOverride,   // null = 跟随系统
  ...
)
```

设置页三个选项：跟随系统 / 中文 / English，写进 prefs，重启后仍生效。

---

## 三、验收标准（严格）

**这个验收标准必须过，不能只看截图说「差不多了」：**

1. 切到 English 后，**逐个页面点一遍**，截图给我，每一屏不能有一个中文字
   - 首页 / 课表 / 饮食 / 训练 / AI / 设置 / 每个弹窗
2. 切回中文，同样逐页检查，不能有英文残留
3. 语言切换后**不重启 App 立即生效**
4. 杀掉 App 重开，语言选择还在
5. `analyze` 0 error
6. **grep 验证**：`grep -rn "[一-龥]" lib/screens/ lib/widgets/ | grep -v "l10n" | grep -v "^.*//.*"` 
   应该只剩注释，不能有 UI 字符串

---

## 四、给 Agron 的提醒

1. **别偷懒用机器翻译糊弄**：英文文案要像人写的，不是「Quick Record Diet / Photo Recognize Heat」
   这种。参考真实 App 的措辞：
   - 「快速记饮食」→ "Log a Meal"
   - 「拍照识热量」→ "Scan Food"
   - 「剩余额度」→ "Remaining"
   - 「今日摄入」→ "Consumed"
   - 「基础代谢」→ "BMR"
   - 「训练消耗」→ "Workout Burn"
2. **中文里带 emoji 的**（「⚡ 快速记录」「🔥 剩余热量」），emoji 放在 arb 里还是代码里
   选一个统一，别一半一半
3. **数字+单位**要本地化：中文「96g」英文也是「96g」，但「连续 3 天」英文是「3-day streak」
   （单数/复数要处理，用 arb 的 plural 语法）
4. **不要为了赶工，把没翻译的藏起来**（比如整个卡片都不显示）。宁可留 TODO 注释，
   也不能让界面缺东西

---

## 五、这条做完之后

- 回去把 v1.4 那两个没完成的：首页布局重叠、校车看板动态化
- 还有小组件接数据、天气 GPS 定位（这两条我已经提过了）
- 全都做完，一起打包给老大验收

---

## 附：环境
- flutter 命令：`C:\Users\33239\dev\flutter-nops.bat`（PowerShell 是坏的）
- 项目：`C:\Users\33239\Documents\LifeLog`（git 仓库，改完 commit）

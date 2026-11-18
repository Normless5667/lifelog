# LifeLog v1.7 需求：视觉美化 + AI 页隐藏 JSON

> 老大实测反馈（2026-11-18 夜）
> 1. **P1：界面再美化一下** —— 现在功能齐了，但视觉不够精致
> 2. **P0：AI 助手页把 JSON 藏起来** —— 现在整坨 JSON 代码块铺在屏幕上，横向溢出，很难看

---

## 一、P0：AI 页隐藏 JSON（实测问题）

### 现象
老大截图里，AI 回复了一整段 JSON（`{"plan_name": "...", "days": [...]}`），
`MarkdownBody` 把它当成代码块渲染，铺了一屏，还横向溢出看不清。

### 根因
`lib/screens/ai/ai_chat_screen.dart:226` 直接 `MarkdownBody(data: m.content)`，
没有对代码块做特殊处理。

### 修法

**前置：先约定 AI 输出格式。** 现在的 prompt 让 AI 在末尾附 JSON，
但要改成用**特殊的标记**包起来，App 才好识别：

```
在回复末尾必须附一个训练计划，用这个格式（其他内容照常写在前面）：

<<<PLAN_JSON>>>
{"plan_name": "...", "days": [...]}
<<<END_PLAN>>>
```

比 markdown 代码块（```json）更可靠——因为 markdown 代码块在流式输出时
可能只显示一半，标记法能等到 END 再解析。

**然后在 UI 层做三件事：**

### 1.1 解析并剥离
```dart
// 伪代码
final match = RegExp(r'<<<PLAN_JSON>>>([\s\S]*?)<<<END_PLAN>>>').firstMatch(content);
if (match != null) {
  final jsonStr = match.group(1);
  final displayText = content.replaceAll(match.group(0)!, '').trim();  // 去掉 JSON 部分
  final plan = tryParsePlan(jsonStr);  // 解析失败返回 null，别崩
}
```

### 1.2 不显示原始 JSON，改用卡片
JSON 剥离后，在气泡末尾放一张**计划卡片**：

```
┌─────────────────────────────────────┐
│  ✨ 已生成训练计划                   │
│  推拉腿+上下肢·五分化维持增肌         │
│                                      │
│  周一 推（胸/肩/三头）  5 个动作      │
│  周二 拉（背/二头）    5 个动作      │
│  周三 腿（股四/股二/腘绳） 6 个动作  │
│  ...                                 │
│                                      │
│  [ 查看详情 ]   [ 导入到训练 ✓ ]     │
└─────────────────────────────────────┘
```

- 「查看详情」：展开显示完整计划（可以是底部弹窗，不是铺在聊天里）
- 「导入到训练」：写库，成功后按钮变「已导入 ✓」并禁用

### 1.3 兜底
- **JSON 解析失败**：不显示卡片，只显示原文（但折叠起来，默认收起，
  给个「显示原始回复」的小按钮）
- **流式输出中**：还没等到 `<<<END_PLAN>>>` 之前，把已收到的 JSON 部分**暂不渲染**，
  显示「正在生成计划…」的占位

### 1.4 还要检查其他地方
- 有些非 JSON 的 markdown 代码块（比如 AI 教你写 SQL）也可能撑破布局。
  给 `MarkdownBody` 加 `MarkdownStyleSheet(code: TextStyle(fontSize: 12))`
  并且外面套 `SingleChildScrollView(scrollDirection: Axis.horizontal)` 让代码块能横滑，
  不要溢出到屏幕外

---

## 二、P1：视觉美化（对标 Keep）

现在的问题（从截图看）：
1. 深色模式下颜色偏"脏"——底部导航的橙色、红色、紫色色块饱和度太高，像调色板
2. 首页四个快捷入口的图标方块**形状不统一**（有的圆角大有的小），阴影也不一致
3. 热量环的蓝色和品牌色没关系，是随手选的
4. 卡片间距不统一，有的 12 有的 16
5. 文字层级不够：标题和正文区分度不够，卡里全是同一种粗细

### 2.1 统一设计 token（先做这个）

建 `lib/theme/app_theme.dart`，定义一套常量：

```dart
class AppColors {
  // 主色：深蓝（呼应大肥鱼）
  static const primary = Color(0xFF1E5AA8);
  static const primaryDark = Color(0xFF0D3A73);
  static const primaryLight = Color(0xFF4A8FE7);

  // 强调：橙（进度/热量）
  static const accent = Color(0xFFFF7A22);

  // 功能色
  static const success = Color(0xFF34C759);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF3B30);

  // 四个模块的标识色（低饱和度！）
  static const moduleDiet = Color(0xFFFF8A50);      // 橙
  static const moduleWorkout = Color(0xFFEF5B5B);   // 红（降饱和）
  static const moduleBody = Color(0xFF3D7EBF);      // 蓝
  static const moduleAi = Color(0xFF9B6BD6);        // 紫（降饱和）

  // 深色模式
  static const darkBg = Color(0xFF121417);
  static const darkSurface = Color(0xFF1C1F24);
  static const darkSurfaceHigh = Color(0xFF262A31);
}

class AppRadius {
  static const card = 20.0;
  static const button = 14.0;
  static const input = 12.0;
  static const chip = 999.0;
}

class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

class AppText {
  static const h1 = TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.3);
  static const h2 = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.35);
  static const body = TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5);
  static const caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.4);
  static const mono = TextStyle(fontSize: 12, fontFamily: 'monospace', height: 1.4);
}
```

### 2.2 深色模式的具体问题

**底部的四个模块色块**：现在饱和度太高（红 0xFFFF3B30、紫 0xFF8B5CF6 这种），
在深色背景上很刺眼。改成：
- 前景色（图标）用原色
- 背景色用**同一个色 15% 透明度**，不要实心高饱和方块

**卡片**：深色模式不要用纯黑，用 `#1C1F24`，卡片之间要能看出层次

**热环**：深色模式用 `primaryLight`（#4A8FE7）不是那个亮蓝，会更沉

### 2.3 视觉层级

**首页从上到下的视觉重量**应该递减：
1. 打卡徽章（有渐变、有动画感）—— 最新鲜
2. 天气卡片 + 校车卡片 —— 信息重要但次要
3. 四个快捷入口 —— 操作入口，图标要醒目
4. 快捷记录输入框 —— 弱化（灰色边框，不要醒目）
5. 热量环 —— 数据展示，居中偏大
6. 营养素进度条 —— 细节

现在的问题是**全部都一样重**，用户眼睛不知道往哪看。

**具体做法**：
- 卡片阴影按层级递减：重要的 `blurRadius: 16, opacity: 0.08`，次要的 `blurRadius: 8, opacity: 0.04`
- 重要数字（热量、剩余额度）用 `fontSize: 40, w700`，次要标签用 `caption` 灰色
- 模块图标方块统一 `BorderRadius.circular(18)` + `size: 56`

### 2.4 微交互（加分项，不多但要有）

- 卡片按下时轻微缩放 `scale: 0.98`（`AnimatedScale` 200ms）
- 热量环变化时用 `TweenAnimationBuilder` 补间（不要跳变）
- 底部导航切换有 200ms 的颜色过渡

**不要做**：粒子效果、渐变背景动画、多余的光晕 —— 那会让 App 变"廉价"。

### 2.5 深色/浅色要都试

改完必须在**深色和浅色两套主题下**都截图看一眼，别只顾深色。

---

## 三、验收标准

**AI 页**：
- [ ] AI 回复里的 JSON 不再铺屏，改成卡片
- [ ] 卡片能「查看详情」和「导入到训练」
- [ ] JSON 解析失败不崩，能看原文（折叠）
- [ ] 流式输出时不闪

**美化**：
- [ ] 建了 `app_theme.dart`，颜色/圆角/间距全部有常量
- [ ] 四个模块色块统一形状和尺寸
- [ ] 深色模式配色不刺眼
- [ ] 文字层级分明（标题/正文/说明）
- [ ] 卡片间距统一
- [ ] 深色浅色都截图给我看

---

## 四、给 Agron 的提醒

1. **先做 token 再改页面**——不要直接往各页面里改色值，否则下次还要改一遍
2. **AI 页的改动要和 v1.6 的耗电修复一起验证**，别改坏了
3. 改 UI 不要动业务逻辑，`git diff` 要能看清只改了样式
4. flutter 命令：`C:\Users\33239\dev\flutter-nops.bat`
5. 做完 git commit，提交信息写清是 UI 改动

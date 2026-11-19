# P0 Bug：训练会话页三个问题

> 老大实测（2026-11-19 10:45 截图）
> 1. **顶部统计离谱**：显示「1组 · 7320420kg」，七百万公斤
> 2. **组数不涨**：明明有第二组，还是显示「1组」
> 3. **输入框填不进去**：键盘弹出来后，点「次」那个框想输入数字，填不进去

---

## 一、问题1+2：统计计算错误

### 问题代码
`lib/screens/workout/workout_session_screen.dart` 第 304-326 行：

```dart
({int sets, double volume, double kcal}) _liveStats() {
  var workSets = 0;
  var vol = 0.0;
  for (final b in _blocks) {
    if (L10nHelper.isCardioCategory(b.exercise.category)) continue;
    for (final s in b.sets) {
      final w = double.tryParse(s.weight.text) ?? 0;
      final r = int.tryParse(s.reps.text) ?? 0;
      if (!s.warmup && (w > 0 || r > 0)) {
        workSets++;
        vol += w * r;
      }
    }
  }
  ...
}
```

### 三个具体缺陷

**缺陷 A：`(w > 0 || r > 0)` 用「或」**
现状：只要重量或次数有一个非零就计入一组。
应该：**两个都有效才算一组**（`w > 0 && r > 0`）。
否则填了重量没填次数，或者只填了个 2 在次数框里，都会被算进去。

**缺陷 B：`vol += w * r` 没有上限校验**
这是 7320420 的直接来源。如果 `w` 解析出异常大值（比如输入法塞进了奇怪的字符、
或者 `w` 是某个超大的 double），乘出来就是天文数字。
**必须加合理性钳制**：
```dart
// 单组合理性检查：重量 0-500kg，次数 0-100次
if (w < 0 || w > 500) continue;   // 或者当作无效
if (r < 0 || r > 100) continue;
```
另外 `double.tryParse` 对 `"7.3e5"` 这种也认，要挡掉科学计数法。

**缺陷 C：组数统计逻辑可能不对**
现在 `workSets` 是数「有几条 set 记录」，但截图里明明是「第二组」，
它却显示 1 组。检查：
- 新增 set 时是不是真的 `b.sets.add(...)` 了
- 还是 UI 上有两行但数据只有一条
- `_SetRow` 的 `w`/`r` 是不是共享了同一个 controller

### 正确实现
```dart
({int sets, double volume, double kcal}) _liveStats() {
  var workSets = 0;
  var vol = 0.0;
  for (final b in _blocks) {
    if (L10nHelper.isCardioCategory(b.exercise.category)) continue;
    for (final s in b.sets) {
      if (s.warmup) continue;
      final w = double.tryParse(s.weight.text.trim()) ?? 0;
      final r = int.tryParse(s.reps.text.trim()) ?? 0;
      // 必须两个都有效才算一组
      if (w <= 0 || r <= 0) continue;
      // 合理性钳制，防止异常值
      if (w > 500 || r > 100) continue;
      workSets++;
      vol += w * r;
    }
  }
  // 兜底：容量不可能超过 100 吨
  if (vol > 100000) vol = 0;  // 或者记录一次错误日志
  ...
}
```

---

## 二、问题3：输入框填不进去

### 现象
键盘弹出后，点击「次」那个输入框，光标在闪，但输入数字没反应，或者数值不更新。

### 可能原因（按可能性）

**原因 A（最可能）：`onChanged` 里 `setState(() {})` 导致整页重建，TextField 失去焦点**
```dart
TextField(
  controller: b.sets[si].reps,
  onChanged: (_) => setState(() {}),   // ← 这里
)
```
每次输入一个字符，整页重建，TextField 的 `FocusNode` 可能被重置。
**修法**：`setState` 只更新需要变的部分，或者用 `ValueListenableBuilder` 包住统计数字，
不要包整个页面。

**原因 B：键盘遮挡**
`Scaffold` 没有设置 `resizeToAvoidBottomInset: true`（默认是 true，但如果是自定义布局可能被关掉了），
或者列表没有 `padding` 让出键盘高度。
**修法**：
```dart
Scaffold(
  resizeToAvoidBottomInset: true,  // 确认这行开着
  body: ListView(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 80),
    ...
  ),
)
```

**原因 C：`controller` 被复用**
如果 `_SetRow` 的 `weight`/`reps` 两个 `TextEditingController` 在构造时共享了同一个实例，
或者每次 build 都新建，那输入就会被吃掉。
**修法**：`TextEditingController` 必须在 `initState` 里建一次，`dispose` 里释放。

**原因 D：`suffixText`/`prefixIcon` 占位导致点击区域错位**
截图里输入框有图标和单位，实际可点区域可能只有中间一小块。
**修法**：给 `TextField` 外面包一层 `GestureDetector`，点哪都能聚焦。

### 验收
- [ ] 点进「kg」框，输入 60，数字即时显示
- [ ] 点进「次」框，输入 10，数字即时显示
- [ ] 两个都填好后，顶部统计变成「1组 · 600kg」
- [ ] 点「+」加一组，顶部变成「2组 · 1200kg」（假设两组都是 60×10）
- [ ] 键盘弹出时，当前输入框不被挡住
- [ ] **任何情况下容量都不会超过 100000kg**（加个上限兜底）

---

## 三、顺带检查（截图里看到的）

1. **「组」这个字的位置**：截图里显示「1组 · 7320420kg」挤在一起，
   应该是「1 组 · 7320420 kg」，加个空格好读。
2. **单位**：`kg` 前面没空格，跟数字粘在一起。
3. **第二行那个黄色的「热」标记**：那是 warmup（热身组）吗？
   如果是，它**不该被计入容量**（现在代码里 `!s.warmup` 已经排除了，确认一下）。
4. **休息倒计时 01:42** 跟「组间休息结束！开始下一组吧」同时出现，
   说明提示语没跟着倒计时消失。检查一下这个提示的显示条件。

---

## 四、范围

- 只改训练会话页的计算和输入交互
- 不要动刚做好的 UI 样式（颜色、字号、圆角）
- 不要改数据模型和数据库 schema
- 改完 analyze 0 error + build apk
- **版本号 2.1.5 → 2.1.6**（老大要求每版都往上加）

---

## 五、环境
- flutter：`C:\Users\33239\dev\flutter-nops.bat`
- 项目：`C:\Users\33239\Documents\LifeLog`
- 记得 git commit

---

## 附：同类问题自查
既然容量计算有这个毛病，**建议顺手检查其他地方的数值计算**：
- 饮食页的热量总和
- 身体数据的 BMI / 体重变化
- 有氧的 MET 消耗
- 步数折算的卡路里

都要有合理性钳制，不能让异常值直接显示给用户。

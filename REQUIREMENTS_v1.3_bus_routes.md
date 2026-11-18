# LifeLog v1.3 需求：校车表多路线化（为将来上架做准备）

> 目标：把「写死 BUV 一套表」改成「支持多条路线 + 用户可导入自定义」，
> 默认仍是 BUV，但架构上为将来面向其他学校打开口子。
> 优先级：P1，这是 v1.2 之后的第一个增量。

---

## 一、数据结构改造

### 现状
`assets/bus_schedule.json` 是单条路线：
```json
{
  "route": "Hai Ba Trung Route",
  "valid_period": "2026-11-16 to 2026-11-20",
  "weekdays_only": true,
  "outbound": { "title": "...", "stops": [{ "name": "...", "times": [...] }] },
  "inbound":  { "title": "...", "stops": [{ "name": "...", "times": [...] }] }
}
```

### 改成「路线包」结构
`assets/bus_routes.json`（保留原 `bus_schedule.json` 作为 BUV 的一条内置记录，不动它）：
```json
{
  "default_route_id": "buv-hai-ba-trung",
  "routes": [
    {
      "id": "buv-hai-ba-trung",
      "name": "BUV · Hai Ba Trung Route",
      "name_en": "BUV · Hai Ba Trung Route",
      "school": "British University Vietnam",
      "source": "builtin",
      "valid_period": "2026-11-16 to 2026-11-20",
      "weekdays_only": true,
      "outbound": { ... },
      "inbound":  { ... }
    }
  ]
}
```

关键字段：
- `id`：稳定标识，存在用户偏好里
- `source`：`builtin` / `imported` / `custom`
- `name` / `name_en`：双语名（呼应 i18n）

### 用户自定义路线的存储
不放 assets（assets 是只读的），放应用数据目录：
```
<app_data>/routes/<route_id>.json
```
启动时合并：内置 routes + 用户目录里的 routes。

---

## 二、UI 改造

### 2.1 路线选择器
课表页（或独立的「校车」页）顶部加一个下拉/卡片：
```
当前路线：BUV · Hai Ba Trung Route  [切换]
```
点开弹出一个列表：
- 内置路线（带「内置」标签）
- 我的路线（可删除、可编辑）

### 2.2 添加自定义路线
两个入口：
1. **手动创建**：表单，填路线名 + 站点名 + 每个站点的时间（逗号分隔）
2. **导入文件**：选 `.json` 文件，校验格式后加入

### 2.3 导出模板
提供「下载模板」按钮，导出一个空的 JSON 骨架，用户照着填。
这对将来的「用户之间分享学校路线」很关键。

---

## 三、导入格式校验

导入时必须校验，不能让坏文件进库：

```dart
// 校验规则
- 必须有 id（自动生成也行）、name、outbound、inbound
- outbound.stops 和 inbound.stops 都不能为空
- 每个 stop 必须有 name 和 times
- times 必须是 "HH:mm" 格式的字符串数组
- 所有 times 数组长度一致（否则算错）
```

校验失败时给明确的错误提示：
```
导入失败：第 3 个站点 "AAA" 的时间不是 HH:mm 格式
```

---

## 四、默认行为不变

- 首次安装：自动用 `default_route_id`（BUV）
- 用户没切换过：一直用 BUV
- 用户切换后：记住选择，下次启动还是那个

**这一条很重要**：不要因为改架构，让老大自己用的时候多出一步选择。

---

## 五、为将来上架留的口子（现在只做架构，不做功能）

1. **路线包可分享**：导出的 JSON 可以给别人导入（格式已经支持）
2. **多语言**：`name` / `name_en` 双语字段
3. **时区**：每条路线可以带 `timezone` 字段（默认 `Asia/Ho_Chi_Minh`），
   将来有跨时区的学校能对
4. **站点坐标**（可选）：`{"name": "SKY OASIS", "lat": 20.99, "lng": 105.84, "times": [...]}`
   将来做地图/到站距离估算要用

这四条现在**只加字段，不实现功能**，避免过度设计。

---

## 六、验收标准

- [ ] 首次安装打开，直接显示 BUV 校车，不需要任何设置
- [ ] 能切换路线（列表里有 BUV）
- [ ] 能手动创建一条新路线并保存
- [ ] 能导入一个 JSON 文件并出现在列表里
- [ ] 导入坏文件时有明确错误提示，不会崩
- [ ] 能删除自己创建/导入的路线（内置的不能删）
- [ ] 切换路线后，首页倒计时和提醒都跟着换
- [ ] analyze 0 error

---

## 七、不要做的事

- **不要**现在做「用户上传路线到云端共享」——要后端，先不做
- **不要**现在做地图/导航——定位权限会引审核问题
- **不要**改 `assets/bus_schedule.json` 的现有内容（它是数据源，别动）

---

## 附：提醒
- flutter 命令一律 `C:\Users\33239\dev\flutter-nops.bat`
- 项目根目录 `C:\Users\33239\Documents\LifeLog`，已经是 git 仓库了，改完记得提交
- 现有 8 条需求里「英文版」「界面美化」还没收尾，这条做完回去继续

# OneBoard 品牌规范 — Warm Minimal（温暖极简）

**日期**：2026-06-27 | **设计方向**：Warm Minimal
**基于**：swiftui-design-skill 设计系统

---

## 一、设计哲学

> 「安静、温暖、克制」—— 一个不打扰用户、但每次打开都让人感到舒适的工具。

- **主色调**：单一暖色强调（琥珀/焦糖），大面积留白
- **层次感**：通过暖灰底色和微妙的透明度差异区分层级，而非边框和分割线
- **字体**：SF Pro 为主，关键标题用 New York 衬线点缀
- **间距**：8pt 网格，充足的呼吸空间

---

## 二、色彩系统

### 强调色

| Token | Hex | 用途 |
|-------|-----|------|
| `accent` | `#D4792E` | 按钮、选中态、链接、关键图标 |
| `accentLight` | `#F5E6D3` (accent 12%) | hover 背景、选中行背景 |
| `accentDark` | `#B5651F` | 按下态、深色模式强调 |

### 中性色

| Token | 浅色 | 深色 | 用途 |
|-------|------|------|------|
| `background` | `#FAFAF8` | `#1C1C1E` | 面板主背景 |
| `surface` | `#F5F3EF` | `#2C2C2E` | 卡片、输入框、次级区域 |
| `textPrimary` | `#1A1A1A` | `#F2F2F7` | 标题、正文 |
| `textSecondary` | `#7A7A7A` | `#8E8E93` | 辅助信息、时间戳 |
| `textTertiary` | `#B0B0B0` | `#636366` | 占位符、禁用态 |
| `divider` | `#E8E6E1` | `#38383A` | 分割线 |

> 实现方式：浅色模式用 hex 值，深色模式用系统语义色（`.labelColor` 等自动适配）。面板壳使用 `.regularMaterial` 覆盖所有模式。

### 语义色

| Token | Hex | 用途 |
|-------|-----|------|
| `success` | `#6B9E6D` | 已完成、已授权、在线 |
| `warning` | `#D4A03C` | 警告、将过期 |
| `error` | `#C95A4A` | 错误、删除、已过期 |
| `info` | `#5B8DB8` | 中性提示 |

### 不使用紫色-蓝色渐变 ❌
app 没有任何渐变背景。所有背景是纯色或系统毛玻璃 material。

---

## 三、字体系统

### 字体选择

| 用途 | 字体 | 原因 |
|------|------|------|
| 面板标题 | **SF Pro** 17pt Semibold | 系统原生，清晰 |
| 标题点缀 | **New York** 衬线（仅面板标题的英文部分） | 温暖、有品位 |
| 正文 | **SF Pro** 13pt Regular | 可读性 |
| 辅助信息 | **SF Pro** 11pt Regular | 信息层级 |
| 等宽 | **SF Mono** 12pt（OCR 结果、尺寸标签） | 技术感 |

### 字号层级

| 级别 | 字号 | 字重 | 行高 | 用途 |
|------|------|------|------|------|
| Display | 20pt | Bold (New York) | 28 | 大面板标题（仅 Settings 侧栏） |
| Title | 17pt | Semibold | 24 | 面板标题 |
| Headline | 14pt | Semibold | 20 | 区块标题 |
| Body | 13pt | Regular | 18 | 正文、列表 |
| Caption | 11pt | Regular | 15 | 辅助、时间戳 |
| Mono | 12pt | Regular | 18 | 代码/OCR 结果 |

### 字体规则
- 每个面板最多 3 种字号（title + body + caption）
- 不用 Inter、Roboto、Poppins
- 不用 `.font(.caption)` 系统动态字体 → 统一用固定 `Font.system(size:)`

---

## 四、间距系统（8pt 网格）

| Token | 值 | 用途 |
|-------|---|------|
| `spaceXS` | 4pt | 图标与文字间距、紧凑间距 |
| `spaceSM` | 8pt | 行内元素间距、按钮内边距 |
| `spaceMD` | 12pt | 列表行水平内边距、卡片内边距 |
| `spaceLG` | 16pt | 面板内边距、区块间距 |
| `spaceXL` | 20pt | 区块间距 |
| `space2XL` | 24pt | 面板间距 |
| `space3XL` | 32pt | 大型间距 |

---

## 五、圆角系统

| Token | 值 | 用途 |
|-------|---|------|
| `radiusSM` | 6pt | 按钮、标签、图标容器 |
| `radiusMD` | 8pt | 卡片、输入框、搜索栏 |
| `radiusLG` | 12pt | 浮动面板 |
| `radiusFull` | 999pt | 胶囊/徽章 |

---

## 六、阴影系统

暖色投影（不是纯黑投影）：

| 级别 | 浅色 | 深色 | 用途 |
|------|------|------|------|
| `shadowSM` | `warmGray 6%, r=4, y=2` | `black 15%, r=4, y=2` | 卡片、hover |
| `shadowMD` | `warmGray 8%, r=8, y=3` | `black 20%, r=8, y=3` | 浮动面板（小） |
| `shadowLG` | `warmGray 10%, r=16, y=4` | `black 25%, r=16, y=6` | 浮动面板（大） |

> 浅色模式用暖灰投影（`#8B7355` 8% 透明度），深色模式用黑色投影。

---

## 七、图标系统

- **来源**：SF Symbols 5（macOS 14+，5000+ 图标）
- **强调色图标**：`accent` 色，用于主要操作
- **普适图标**：`textSecondary` 色
- **图标大小**：14pt（工具栏）、18pt（面板标题）、28pt（类型图标）
- **不使用**：任何 emoji、自定义 SVG、AI 生成的 clipart
- **菜单栏图标**：手绘 NSBezierPath（18×18pt 画布，精确居中），`isTemplate = true`

---

## 八、组件规范

### 浮动面板（所有弹出窗口）
```
背景: .regularMaterial（系统毛玻璃）
圆角: 12pt
阴影: shadowLG（暖灰）
边框: 无（material 自带层次感）
内边距: 16pt
最小宽度: 300pt（剪贴板）/ 320pt（待办/网关）/ 480pt（翻译）
```

### 面板 Header
```
高度: 40pt
字体: title (17pt semibold)
内边距: h16 v8
底部分割: divider 色细线或 material 自带层次
```

### 关闭按钮（所有面板统一）
```
样式: xmark 图标
大小: 28×28pt
颜色: textSecondary
位置: header 右侧
hover: textPrimary
```

### 列表行
```
高度: 36pt（紧凑）/ 40pt（标准）
内边距: h12 v8
hover: accentLight（accent 12%）
圆角: 6pt
```

# 设计规范：OneBoard 统一设计系统 v2.0

**日期**：2026-06-26
**版本**：v2.0
**状态**：待评审

---

## 一、设计理念

遵循 **Apple Human Interface Guidelines for macOS**，构建一个**轻量、专业、和谐**的设计系统。设计关键词：

- **轻盈**：通过材料和透明感融入 macOS 环境
- **精准**：严格的间距和比例系统
- **克制**：品牌色仅用于最关键的交互元素
- **原生**：深色/浅色模式无缝切换

---

## 二、色彩系统

### 2.1 品牌色

| Token | 浅色模式 | 深色模式 | 用途 |
|-------|---------|---------|------|
| `accent` | `#4A9EF7` (0.29, 0.62, 0.97) | `#6AB4FF` (0.42, 0.71, 1.0) | 主要操作按钮、选中态、焦点环 |
| `accentLight` | `#7ABFFF` (0.48, 0.75, 1.0) | `#4A8EDB` (0.29, 0.56, 0.86) | Hover 背景、次要强调 |
| `accentMuted` | accent 10% 透明度 | accent 15% 透明度 | 标签背景、选中行背景 |

> **修改说明**：当前 primary 色 `#59A6F2 (0.35, 0.65, 0.95)` 偏灰，改为苹果风格蓝 `#4A9EF7` 更鲜艳、更符合 macOS 原生风格。

### 2.2 中性色

| Token | 映射 | 用途 |
|-------|------|------|
| `textPrimary` | `NSColor.labelColor` | 标题、正文 |
| `textSecondary` | `NSColor.secondaryLabelColor` | 辅助信息、时间戳 |
| `textTertiary` | `NSColor.tertiaryLabelColor` | 占位符、禁用态文字 |
| `textInverted` | `NSColor.white` (浅色) / `NSColor.black` (深色) | 深色背景上的文字 |
| `bgPrimary` | `NSColor.controlBackgroundColor` | 内容区背景 |
| `bgSecondary` | `NSColor.windowBackgroundColor` | 窗口背景 |
| `bgTertiary` | `NSColor.underPageBackgroundColor` | 分组背景 |
| `border` | `NSColor.separatorColor` | 分割线、边框 |
| `borderSubtle` | `separatorColor.opacity(0.5)` | 细微边框 |

### 2.3 语义色

| Token | 值 | 用途 |
|-------|---|------|
| `success` | `NSColor.systemGreen` | 成功状态 |
| `warning` | `NSColor.systemOrange` | 警告状态 |
| `error` | `NSColor.systemRed` | 错误、删除 |
| `pinned` | `#FFE8B0` (浅色) / `#5C4A1E` (深色) | 置顶条目背景 |
| `info` | `NSColor.systemBlue` | 信息提示 |

### 2.4 色彩使用规则

1. **文本**：只用 `textPrimary/Second/Third/Inverted`，禁止直接使用 `Color.black/white` 或 `.primary/.secondary`
2. **背景**：只用 `bgPrimary/Second/Tertiary` 或系统材料
3. **强调**：主操作按钮用 `accent`，删除操作用 `error`
4. **材料视图中的文字**：使用 `.primary/.secondary`（material 会自动适配）

---

## 三、间距系统

基于 4pt 网格，所有间距（padding、gap、offset）均为 4 的倍数。

| Token | 值 | 用途 |
|-------|---|------|
| `spacing2XS` | 4 | 图标与文字间距、密集列表 |
| `spacingXS` | 8 | 行内间距、小型按钮内边距 |
| `spacingSM` | 12 | 卡片内边距、列表行内边距 |
| `spacingMD` | 16 | 区块内边距、按钮水平内边距 |
| `spacingLG` | 20 | 区块间距 |
| `spacingXL` | 24 | 面板内边距 |
| `spacing2XL` | 32 | 页面级间距 |
| `spacing3XL` | 48 | 大型间距 |

---

## 四、圆角系统

| Token | 值 | 用途 |
|-------|---|------|
| `radiusSM` | 4 | 小图标容器、标签、徽章 |
| `radiusMD` | 6 | 列表行、按钮 |
| `radiusLG` | 8 | 卡片、输入框、面板内子区域 |
| `radiusXL` | 12 | 浮动面板、弹出窗口 |
| `radius2XL` | 16 | 大型模态面板 |

> 规则：面板(window)统一使用 12pt，内容区卡片统一使用 8pt，按钮和行统一使用 6pt

---

## 五、阴影系统

| Token | 浅色模式 | 深色模式 | 用途 |
|-------|---------|---------|------|
| `shadowSM` | `black 6%, r=4, y=1` | `black 20%, r=3, y=1` | 卡片、列表行 hover |
| `shadowMD` | `black 8%, r=8, y=2` | `black 25%, r=6, y=2` | 浮动面板（小） |
| `shadowLG` | `black 12%, r=16, y=4` | `black 30%, r=12, y=4` | 浮动面板（大） |

---

## 六、字体排版系统

### 6.1 字体族

- **UI 字体**：`SF Pro`（系统默认）
- **等宽字体**：`SF Mono`（代码/OCR 结果）

### 6.2 排版层级

| Token | 字号 | 字重 | 行高 | 用途 |
|-------|-----|------|------|------|
| `titleLarge` | 22 | `.bold` | 28 | 面板标题 |
| `title` | 17 | `.semibold` | 22 | 区块标题 |
| `headline` | 14 | `.semibold` | 19 | 列表项标题 |
| `body` | 13 | `.regular` | 18 | 正文、列表项描述 |
| `callout` | 12 | `.medium` | 16 | 标签、状态 |
| `caption` | 11 | `.regular` | 14 | 辅助信息、时间戳 |
| `captionSmall` | 10 | `.regular` | 13 | 小标签 |

### 6.3 等宽字体 Token

| Token | 字号 | 用途 |
|-------|-----|------|
| `monoBody` | 13 | OCR 文字展示 |
| `monoCaption` | 11 | 尺寸标签 |

---

## 七、图标系统

- **来源**：SF Symbols 5（macOS 14+）
- **风格**：统一使用 `.body` 大小，`symbolRenderingMode: .hierarchical`（支持层级渲染的图标）
- **工具栏图标**：统一 16pt
- **列表项类型图标**：统一 28pt

---

## 八、组件规范

### 8.1 浮动面板（Panel）

```
背景: .regularMaterial
圆角: radiusXL (12pt)
阴影: shadowLG
边框: accent 10% 透明度描边 (1pt)
内边距: 无（内容视图自行控制）
行为: .borderless + .nonactivatingPanel + .floating
```

### 8.2 设置窗口

```
窗口背景: NSColor.windowBackgroundColor
侧栏宽度: 180pt
侧栏背景: bgTertiary（自动支持 vibrant 效果）
内容区内边距: spacing2XL (32pt)
分组标题: title (17pt semibold)
分组间距: spacingXL (24pt)
```

### 8.3 列表行

```
背景: 默认透明，hover 时 accentMuted
圆角: radiusMD (6pt)
内边距: spacingSM.horizontal + spacingXS.vertical (12x8)
最小高度: 40pt
图标: 28pt，圆角 6pt
```

### 8.4 主操作按钮（Primary Button）

```
背景: accent
文字: textInverted
字体: headline (14pt semibold)
圆角: radiusMD (6pt)
内边距: 16x10 (horizontal × vertical)
最小宽度: 80pt
```

### 8.5 次级按钮（Secondary Button）

```
背景: accent 10% 透明度
文字: accent
字体: headline (14pt semibold)
圆角: radiusMD (6pt)
内边距: 16x10
```

### 8.6 输入框（TextField / TextEditor）

```
背景: bgPrimary
边框: borderSubtle (1pt)
圆角: radiusLG (8pt)
内边距: spacingSM (12pt)
焦点环: accent (2pt)
字体: body (13pt)
```

### 8.7 分段选择器（Picker / Segmented Control）

```
使用系统 .segmented 风格
```

### 8.8 开关（Toggle）

```
使用系统 .switch 风格
```

### 8.9 标签 / 徽章

```
背景: accentMuted
文字: accent
字体: callout (12pt medium)
圆角: radiusSM (4pt)
内边距: 6x3
```

---

## 九、深色模式适配规范

1. **禁止使用**：`Color.black`、`Color.white`、`Color(red:green:blue:)` 硬编码
2. **允许使用**：`textPrimary`/`textSecondary` 等语义色、系统材料、`Color.accentColor`
3. **系统色自动适配**：`NSColor.labelColor` / `.secondaryLabelColor` / `.controlBackgroundColor` 等
4. **材料色自动适配**：`.regularMaterial` / `.ultraThinMaterial` 等
5. **品牌色手动定义**：在 Asset Catalog 中为 accent 色添加深色模式变体，或用 `@Environment(\.colorScheme)` 切换
6. **方案选择**：使用 `NSColor` 扩展 + `Color(nsColor:)` 桥接，因为 `NSColor` 原生支持 name-based dynamic colors

> **推荐**：将 accent/background 等色值定义为 Asset Catalog 中的 Named Color，支持任意 appearance 切换，在 SwiftUI 中直接使用 `Color("Accent")`。

---

## 十、实施优先级

### Phase 1：基础设施（不可见，但必须先行）
1. 重构 `OneBoardColors` → 完整设计令牌系统
2. 创建字体排版 ViewModifier
3. 创建统一间距/圆角/阴影 ViewModifier
4. 创建统一组件（PrimaryButton、SecondaryButton、PanelContainer）

### Phase 2：核心页面逐个重构
5. Settings 设置窗口
6. Clipbord 剪贴板浮动窗口
7. Todo 待办面板
8. Translation 翻译面板

### Phase 3：截图模块
9. Annotation Toolbar 标注工具栏
10. OCR Bubble
11. Screenshot Overlay
12. Pinned Screenshot

### Phase 4：收尾
13. File Staging 暂存架
14. Gateway Switcher 网关切换器
15. Permission Guide
16. 清理 dead code
17. 全量测试

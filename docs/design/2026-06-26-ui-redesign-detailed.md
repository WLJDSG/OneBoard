# UI 设计文档：OneBoard 全界面重构方案

**日期**：2026-06-26
**版本**：v1.0
**状态**：待评审

---

## 一、设计总览

本文档对 OneBoard 全部 17 个 UI 页面逐一进行重构设计，遵循 [统一设计系统 v2.0](../design-spec/2026-06-26-unified-design-system.md)。

### 重构映射表

| # | 页面 | 当前问题 | 重构方向 |
|---|------|---------|---------|
| 1 | Settings | 表单风格陈旧，间距混乱 | macOS 风格设置页面（侧栏+分组） |
| 2 | Clipboard Popover | 整体可用，细节粗糙 | 微调间距、hover 效果、搜索栏 |
| 3 | File Staging Shelf | 硬编码颜色、深色模式不兼容 | 改用设计令牌、语义色 |
| 4 | Gateway Switcher | accentColor 不统一 | 改用统一令牌 |
| 5 | Gateway Profile Editor | 表单样式可优化 | 微调 |
| 6 | Screenshot Overlay | 暗色覆盖，选区框可优化 | 微调 |
| 7 | Annotation Canvas | 标注图层功能优先 | 保持功能，优化 UI 细节 |
| 8 | Annotation Toolbar | 分组太多，按钮间距密 | 简化分组结构 |
| 9 | OCR Bubble | 气泡形状，可优化阴影 | 微调 |
| 10 | Translation Panel | 布局合理，细节可优化 | 微调间距和颜色 |
| 11 | Todo Slide Panel | 材料+圆角可用 | 微调 |
| 12 | Todo History | 统计卡片优化 | 微调 |
| 13 | Todo Settings | 表单样式 | 微调 |
| 14 | Permission Guide | 弹出窗口可用 | 微调 |
| 15 | Pinned Screenshot | 贴图功能 | 保持功能 |
| 16 | Annotation Result | 简单提示窗 | 微调 |
| 17 | Menu Bar Menu | 系统原生 NSMenu | 保持 |

---

## 二、页面逐一设计

### 2.1 Settings 设置窗口（重点重构）

**当前问题**：TabView 风格陈旧，间距不统一，无清晰分组层级。

**目标设计**：
```
┌──────────────────────────────────────────────────────┐
│  [侧栏 180pt]        │  [内容区 600pt]               │
│                       │                                │
│  ● 通用               │  通用设置                      │
│  ● 截图·翻译          │  ─────────────────────────    │
│  ● 剪贴板             │  [开机自启]  [开关]           │
│  ● 文件暂存           │  [权限管理]  [状态+按钮]      │
│  ● 待办               │                                │
│  ● 快捷键             │  快捷键                        │
│  ● 网关               │  ─────────────────────────    │
│  ● 关于               │  [截图] [录制按钮]            │
│                       │  [翻译] [录制按钮]            │
│                       │  [剪贴板] [录制按钮]          │
│                       │  ...                           │
└──────────────────────────────────────────────────────┘
```

**设计要点**：
- 窗口大小：700x560
- 侧栏：180pt 宽，使用 `.list` 风格 + `bgTertiary` 背景
- 侧栏选中项：`accent` 色背景高亮
- 内容区：`spacing2XL`(32pt) 内边距
- 分组标题：`title`(17pt semibold) + 底部分割线
- 分组内容：`spacingXL`(24pt) 间距
- 表单行：高度 32pt，标签 `body`(13pt)，控件右对齐
- Picker：系统 `.segmented` 风格
- Toggle：系统 `.switch` 风格

**代码改动**：重写 `SettingsView`，使用 `NavigationSplitView` 风格（macOS 14+ 支持 sidebar-only）

---

### 2.2 Clipbord 剪贴板窗口

**当前问题**：整体可用但 hover 色用 accentColor，与设计令牌不一致；背景用 `.ultraThinMaterial`。

**目标设计**：
```
┌─────────────────────────┐
│  🔍 搜索剪贴板...       │  ← 搜索栏，accentMuted 背景
├─────────────────────────┤
│  📋 文字内容预览──      │  ← 列表行，hover 时 accentMuted
│     2分钟前 · Safari    │
│  🖼️ 图片缩略图          │
│     5分钟前 · Finder    │
│  📄 文件名称.pdf        │
│     10分钟前 · Chrome   │
└─────────────────────────┘
```

**设计要点**：
- 面板大小：350x520
- 材料：`oneBoardPanelStyle()` → `.regularMaterial`
- 搜索栏：
  - 背景：`accentMuted`
  - 圆角：`radiusLG`(8pt)
  - 图标+占位符：`body`(13pt)，`textTertiary`
- 列表行：
  - 内边距：`spacingSM`(12pt) 水平 + `spacingXS`(8pt) 垂直
  - 圆角：`radiusMD`(6pt)
  - Hover：`accentMuted`
- 类型图标：28pt，`radiusMD`(6pt)
- 预览文字：`body`(13pt)，最多 2 行
- 时间/来源：`caption`(11pt)，`textSecondary`

**代码改动**：替换 `ClipboardPopoverView`、`ClipboardRowView`、`ClipboardSearchBar` 中的颜色引用

---

### 2.3 File Staging 文件暂存架（重点）

**当前问题**：大量 `Color.black.opacity()` / `Color.white.opacity()` 不兼容深色模式；双层圆角定义。

**目标设计**：
```
┌────────────────────────────────────┐
│  📁 暂存架          [收起] [清空]  │  ← header
├────────────────────────────────────┤
│  ┌──────┐ ┌──────┐ ┌──────┐      │
│  │ 缩略图│ │ 缩略图│ │ 缩略图│      │  ← 网格布局
│  │ 文件名│ │ 文件名│ │ 文件名│      │
│  └──────┘ └──────┘ └──────┘      │
└────────────────────────────────────┘
```

**设计要点**：
- 材料：`.regularMaterial`
- 圆角：`radiusXL`(12pt) — 统一为面板圆角
- Header：`oneBoardPanelHeader()` 修饰符
- 文件卡片：
  - 大小：80x80pt
  - 圆角：`radiusLG`(8pt)
  - 缩略图：居中，最大 48pt
  - 文件名：`caption`(11pt)，`textPrimary`，最多 1 行截断
  - 删除按钮：hover 时显示，`.error` 色，18pt
- 文件卡片 hover：`accentMuted`

**重要修复**：
- 删除 `hostingView.layer?.backgroundColor = NSColor.clear.cgColor` 和 `hostingView.layer?.cornerRadius = 24` 的双层定义
- 所有 `Color.black.opacity()` 改为 `textPrimary`
- 所有 `Color.white.opacity()` 改为 `textInverted`

---

### 2.4 Gateway Switcher 网关切换器

**当前问题**：`accentColor` 未与 `OneBoardColors` 统一；布局合理。

**目标设计**：
```
┌──────────────────────────────┐
│  网关切换                    │  ← header
├──────────────────────────────┤
│  ● Profile A (当前)  [暂停]  │  ← 列表行
│  ○ Profile B          [▶]    │
│  ○ Profile C          [▶]    │
├──────────────────────────────┤
│  [+ 添加新配置]              │  ← 底部操作
└──────────────────────────────┘
```

**设计要点**：
- 面板大小：380x360
- 材料：`oneBoardPanelStyle()`
- Header：`oneBoardPanelHeader()`
- 列表行：`oneBoardListRow()`
- 当前选中行：`accent` 色左侧指示条 (3pt 宽)
- 状态图标：16pt SF Symbol，当前用 `.green`，暂停用 `.orange`
- 操作按钮：`accentMuted` 背景，`accent` 文字

**代码改动**：将 `accentColor` 替换为 `OneBoardColors.accent`，使用统一修饰符

---

### 2.5 Translation 翻译面板

**当前问题**：布局合理，细节可优化；`accentColor` 不一致。

**目标设计**：
```
┌──────────────────────────────────────┐
│  翻译                     [_][□][×] │  ← 拖拽区域
├──────────────────────────────────────┤
│  [Apple ▼]                          │  ← 服务选择器
│                                      │
│  源语言: [自动检测 ▼]  [⇄] 目标: [英文 ▼] │
│                                      │
│  ┌────────────────────────────────┐ │
│  │ 要翻译的源文本...               │ │  ← 源文本编辑器
│  │                                 │ │
│  └────────────────────────────────┘ │
│                                      │
│  ┌────────────────────────────────┐ │
│  │ 翻译结果将显示在这里...         │ │  ← 翻译结果显示
│  │                                 │ │
│  └────────────────────────────────┘ │
│                                      │
│  [重新翻译]  [复制翻译结果]          │  ← 操作按钮
└──────────────────────────────────────┘
```

**设计要点**：
- 面板大小：520x600（可调整）
- 材料：`oneBoardPanelStyle()`
- 服务选择器：`Picker` segmented，系统风格
- 语言选择器：`Picker` menu 风格，SF Symbol 箭头
- 交换按钮：`arrow.left.arrow.right`，16pt，`radiusMD`(6pt)
- 源文本区：`bgPrimary` 背景，`radiusLG`(8pt)，`borderSubtle` 边框，`spacingSM`(12pt) 内边距，`body`(13pt)，可编辑
- 翻译结果区：`bgPrimary` 背景，`radiusLG`(8pt)，`borderSubtle` 边框，`body`(13pt)，只读但可选
- "重新翻译"按钮：`PrimaryButtonStyle`
- "复制"按钮：`SecondaryButtonStyle`

**代码改动**：统一使用设计令牌，`accentColor` → `OneBoardColors.accent`

---

### 2.6 Todo 待办面板

**当前问题**：整体可用；统计栏、列表行细节可优化。

**目标设计**：
```
┌──────────────────────────┐
│  ━━━━━━━━━━━━━━━━━━━━   │  ← 拖拽手柄
│  待办列表    [历史] [设置]│  ← header
├──────────────────────────┤
│  ┌────┐ ┌────┐ ┌────┐  │
│  │ 3  │ │ 2  │ │ 1  │  │  ← 统计卡片
│  │待办│ │进行│ │完成│  │
│  └────┘ └────┘ └────┘  │
├──────────────────────────┤
│  [新建待办...]           │  ← 快速输入
├──────────────────────────┤
│  🔴 买咖啡豆             │  ← 待办行
│     📎 Safari · 2小时前 │
│  🟡 写周报               │
│     📎 无来源            │
│  🟢 重构代码 (已完成)    │
│     📎 VSCode · 1天前   │
└──────────────────────────┘
```

**设计要点**：
- 面板：`regularMaterial`，`radiusXL`(12pt)，`shadowLG`
- 拖拽手柄：`radiusSM`(4pt)，`textTertiary.opacity(0.3)`，36x5pt
- Header：`oneBoardPanelHeader()` 修饰符
- 统计卡片：
  - 宽度均分，`spacingSM`(12pt) 间距
  - 背景：`accentMuted`
  - 圆角：`radiusLG`(8pt)
  - 数字：`titleLarge`(22pt bold)，`accent`
  - 标签：`caption`(11pt)，`textSecondary`
- 快速输入区：
  - 背景：`bgPrimary`，圆角：`radiusMD`(6pt)
  - 占位符：`body`(13pt)，`textTertiary`
- 待办列表行：
  - `oneBoardListRow()` 修饰符
  - 优先级指示点：10pt 圆形，`.red` / `.orange` / `.green`
  - 标题：`body`(13pt)，完成项加删除线 + `textTertiary`
  - 来源信息：`caption`(11pt)，`textTertiary`

---

### 2.7 Annotation Toolbar 标注工具栏

**当前问题**：工具栏分组过多（4组），每组各有背景、圆角，视觉杂乱。

**目标设计**：简化为 2 组 + 操作按钮

```
┌──────────────────────────────────────────────────────┐
│  [矩形] [圆形] [箭头] [画笔] [文字] [马赛克]  │  [颜色] [线宽] │  [OCR] [完成] [×]  │
│  └─ 标注工具组 ──────────┘  └ 样式组 ─┘  └ 操作组 ──┘
└──────────────────────────────────────────────────────┘
```

**设计要点**：
- 材料：`.regularMaterial`（从 `ultraThinMaterial` 升级）
- 圆角：`radiusXL`(12pt)
- 阴影：`shadowMD`
- 工具按钮：
  - 44x32pt（点击区域）
  - 图标 16pt SF Symbol
  - 默认态：`textSecondary`
  - 选中态：`accent` 背景 + `textInverted` 图标色
  - Hover：`accentMuted`
- 工具组之间：`borderSubtle` 1pt 分隔线
- 颜色选择器：16pt 圆形色块
- 线宽按钮：`body`(13pt) 文字显示当前线宽

---

### 2.8 OCR 气泡窗口

**目标设计**：
```
         ▼  (三角指向截图文字位置)
┌──────────────────────────┐
│  OCR 识别结果            │  ← header
├──────────────────────────┤
│  识别的文字内容...       │  ← 可编辑文本
│                          │
├──────────────────────────┤
│  [复制] [翻译此文字]     │  ← 操作区
└──────────────────────────┘
```

**设计要点**：
- 材料：`oneBoardPanelStyle()`
- 气泡三角：自定义 BubbleShape，`border` 描边
- 文本区：`bgPrimary`，`radiusLG`(8pt)，`body`(13pt)，可编辑可选择
- "复制"按钮：`PrimaryButtonStyle`
- "翻译"按钮：`SecondaryButtonStyle`

---

### 2.9 Screenshot Overlay 截图覆盖层

**当前问题**：暗色蒙版 `black.opacity(0.45)`，选框颜色 `systemBlue` 而非品牌色。

**目标设计**：
- 暗色蒙版：`black.opacity(0.4)`（保持不变，视觉上没问题）
- 选区边框：`accent` 色，1.5pt 宽
- 选区填充：`accent` 10% 透明度
- 手柄：8pt 圆形，`accent` 填充
- 尺寸标签：
  - 背景：`accent` 80%
  - 文字：`monoCaption`(11pt)，`textInverted`
  - 圆角：`radiusSM`(4pt)

---

### 2.10 Pinned Screenshot 贴图窗口

**当前问题**：功能简单，无设计问题。

**改进**：
- 窗口阴影：`shadowLG`
- 关闭按钮（双击时出现）：22pt，`error` 色，半透明

---

### 2.11 Permission Guide 权限引导

**目标设计**：
```
┌──────────────────────────┐
│  [App图标]               │
│                          │
│  OneBoard 需要权限       │
│                          │
│  [按钮: 打开系统设置]    │
└──────────────────────────┘
```

- 面板：`regularMaterial`，`radius2XL`(16pt)，`shadowLG`
- 图标：64pt
- 标题：`title`(17pt semibold)
- 按钮：`PrimaryButtonStyle`

---

## 三、实施计划

### 基础设施 Phase（1 天）

| 步骤 | 内容 | 文件 |
|------|------|------|
| 1 | 重写 `OneBoardColors` → 完整设计令牌 | `Core/Theme/OneBoardColors.swift` → `Core/Theme/DesignTokens.swift` |
| 2 | 创建 `TypographyModifiers.swift` | `Core/Theme/TypographyModifiers.swift` |
| 3 | 创建 `ComponentLibrary.swift` | `Core/Theme/ComponentLibrary.swift` |
| 4 | 更新 `View+Extensions.swift` | 移除旧的硬编码值，迁移到令牌 |

### UI 重构 Phase（2-3 天）

按优先级逐个页面重构，每个页面重构后立即编译验证。

### 翻译修复 Phase（1 天）

单点修复 + 测试验证。

---

## 四、风险评估

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 重构引入功能回归 | 高 | 每个页面单独重构，重构后立即验证功能 |
| 设计令牌迁移遗漏 | 中 | 使用 grep 搜索硬编码颜色值，确保无遗漏 |
| 深色模式兼容性 | 中 | 开发过程中频繁切换模式测试 |
| 编译错误 | 低 | 每次改动后 swift build |

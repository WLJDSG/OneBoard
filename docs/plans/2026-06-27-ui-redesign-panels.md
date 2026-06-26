# 方案：全界面 UI 重新设计（现代简约风格）

**日期**：2026-06-27 | **版本**：v1.0
**风格方向**：现代简约（参照 Linear / Raycast 的 macOS 设计）

---

## 一、设计基调

### 设计关键词
**干净 · 克制 · 层次 · 一致**

### 统一规范（覆盖所有面板）

| 属性 | 统一值 |
|------|--------|
| 材料 | `.regularMaterial` |
| 圆角 | `OneBoardRadius.xl` (12pt) |
| 边框 | `OneBoardColors.accent.opacity(0.08)` 1pt |
| 阴影 | `OneBoardShadow.lg` (black 12%, r16, y4) |
| 内边距 | `OneBoardSpacing.sm` (12pt) 水平 |
| Header 高度 | 40pt |
| Header 字体 | `OneBoardFont.headline` (14pt semibold) |
| 内容字体 | `OneBoardFont.body` (13pt) |
| 辅助字体 | `OneBoardFont.caption` (11pt) |
| 列表行高 | 40pt |
| 选中态 | accent 8% 背景 + 2pt accent 左侧指示条 |
| Hover 态 | accent 6% 背景 |

### 间距规则（强制 4pt 网格）
所有 margin/padding/gap 必须是 {4, 8, 12, 16, 20, 24, 32} 之一。

---

## 二、面板逐一设计

### 2.1 剪贴板面板（Clipboard Popover）

```
┌──────────────────────────────────┐
│ 🔍 搜索剪贴板...           ⌘F   │  ← 搜索栏（内嵌面板内，40pt）
├──────────────────────────────────┤
│ 📌 已置顶                        │  ← 分区 header（仅当有置顶项时）
│ ┃ 📋 这是一条置顶的文字... 2分钟 │  ← 置顶行（淡 accent 左边条）
│ ─────────────────────────────── │
│ 📋 昨天的文字内容...    昨天     │  ← 普通行
│ 🖼️ 屏幕截图.png          1小时   │  
│ 📄 文档.pdf              2小时   │
│ ...                              │
│                                  │
│ 共 128 条  ·  保留 30 天    清空 │  ← 底部状态栏（30pt）
└──────────────────────────────────┘
```

**关键改进**：
- 搜索栏融入面板（不再是突兀的独立区块）
- 置顶项有明确分区 + 左侧 accent 指示条（不再用黄色背景）
- 固定宽度时间列缩小为 44pt
- 行高统一 40pt
- 底部状态栏显示记录数和保留策略
- 选中行：accent 8% 背景 + 左侧 2pt accent 条
- Hover 操作按钮：显示在行右侧，36pt 宽，图标 14pt

**删除/简化**：
- 删除 pin 图标的黄色背景 → 改为淡 accent 左边条
- 删除 action buttons 42pt 死空间 → 改为 hover 出现 36pt 紧凑按钮
- 删除冗余的 context menu（与 hover 按钮重复）

### 2.2 待办面板（Todo Panel）

```
┌──────────────────────────────────┐
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  │  ← 拖拽手柄（5x36pt，40% 透明度）
│ ✓ 待办事项                 3 项  │  ← header（40pt）
├──────────────────────────────────┤
│ ＋ 添加待办事项...               │  ← 快速输入行（40pt，点击展开表单）
├──────────────────────────────────┤
│ ● 高优先级                      │  ← 分区（仅当有对应项时显示）
│ ┃ 🔴 买咖啡豆          Safari   │  ← 行（40pt，checkbox + 标题 + 来源）
│ ┃ 🔴 写完周报          VSCode   │
│ ● 进行中                        │
│   🟡 重构代码           Xcode   │
│ ✓ 已完成                        │  ← 折叠分区
│   完成重构 (2 项)               │
├──────────────────────────────────┤
│ 🕐 历史                 ⌘H     │  ← 底部栏（30pt）
└──────────────────────────────────┘
```

**关键改进**：
- 单行快速输入（不是展开的复杂表单）→ 点击后展开内联表单
- 高/中/低优先级合并为「高优先级」和「进行中」两个有效分区
- 已完成分区默认折叠（点击展开）
- 删除 4 个独立的 section header → 统一为一个 list 内的轻量分组
- 行高 40pt（当前各不同）
- 选中/悬停态与其他面板统一

**删除/简化**：
- 删除 `feedbackView` 独立区块 → 改为轻量 toast 通知
- 删除 `inlineAddView` 的复杂 4 行表单 → 简化为 2 行（内容 + 优先级）
- 删除多个 redundant Divider → 只在 section header 前有分割
- 删除统计卡片（占空间，信息冗余）

### 2.3 翻译面板（Translation Panel）

```
┌──────────────────────────────────┐
│ 🌐 翻译工作台            [×]    │  ← header（40pt，可拖拽）
│ Google 翻译 · 中→英            │  ← 副标题
├──────────────────────────────────┤
│                                  │
│ ┌──────────────────────────────┐│
│ │ 输入要翻译的文字...          ││  ← 源文本区（120pt min）
│ │                              ││
│ └──────────────────────────────┘│
│              ⇣                   │  ← 视觉箭头
│ ┌──────────────────────────────┐│
│ │ Translation result...        ││  ← 翻译结果（120pt min，等比）
│ │                              ││
│ └──────────────────────────────┘│
│                                  │
│ 源语言: [自动检测 ▼]  目标: [简体中文 ▼]  [⇄] │  ← 语言控制栏
│                                  │
│ [重新翻译]        [复制译文] [复制原文] │  ← 操作栏
└──────────────────────────────────┘
```

**关键改进**：
- 源文本区和翻译区等高（不再 128 vs 132）
- 翻译区有 typing 动画（逐字显示或 loading shimmer）
- 服务选择器移到 header 副标题（不再占一整行）
- 语言选择器移到操作栏同一行（紧凑）
- 窗口高度自适应内容（`minHeight: 300`, `maxHeight: 700`）
- 交换按钮放在语言选择器旁边（不再独立飘浮）

**删除/简化**：
- 删除顶部全宽 segmented 服务选择器
- 删除 status bar 的 30pt 固定死空间 → 改为 inline error
- 删除半透明 textBackgroundColor → 改为不透明卡片
- 删除自定义 drag handle → 使用标准 NSWindow titlebar 拖拽

### 2.4 网关切换面板（Gateway Switcher）

```
┌──────────────────────────────────┐
│ 🔗 网关切换              [🔄]   │  ← header（40pt）
│ 当前：192.168.1.1               │  ← 副标题
├──────────────────────────────────┤
│ ┃ ● Profile A           ✓ 当前  │  ← 选中行（accent 左条 + 背景）
│   ○ Profile B                   │  ← 普通行
│   ○ Profile C                   │
│   ○ Profile D（已暂停）          │  ← 暂停的灰色行
├──────────────────────────────────┤
│ DNS: 8.8.8.8, 1.1.1.1          │  ← 信息条
├──────────────────────────────────┤
│         [管理配置...]            │  ← 底部按钮（居中）
└──────────────────────────────────┘
```

**关键改进**：
- 选中行：accent 8% 背景 + 左侧 2pt accent 条
- 当前行：明确标记（绿色勾而非灰色 disabled）
- DNS 信息放进 info callout（圆角背景 + 小图标）
- 管理按钮居中（不再孤零零在右下角）
- 刷新时 header 的 🔄 按钮转动

**删除/简化**：
- 删除 interpunct 分隔符 → 使用逗号
- 删除 summary 的复杂格式化 → 简化

---

## 三、统一 Header 模式

所有浮动面板使用相同的 header 结构：

```
┌──────────────────────────────────┐
│ [图标] 标题             [操作们] │  ← 40pt
│        副标题（可选）            │  ← 12pt（仅翻译/网关有）
├──────────────────────────────────┤  ← Divider
│ 内容区                           │
```

实现为统一的 `PanelHeaderView` 组件：
```swift
struct PanelHeaderView: View {
    let icon: String          // SF Symbol
    let title: String
    let subtitle: String?     // 可选
    let actions: AnyView?     // 右侧操作按钮
}
```

## 四、统一列表行模式

所有面板的列表行使用统一结构：

```
┌──────────────────────────────────┐
│ [图标区] 标题文字         [元数据]│  ← 40pt
│          次要文字（可选）         │  ← 高度自适应
└──────────────────────────────────┘
```

实现为统一的 `PanelRowView` 组件：
```swift
struct PanelRowView<Icon: View, Metadata: View>: View {
    let icon: Icon
    let title: String
    let subtitle: String?
    let metadata: Metadata
    let isSelected: Bool
    let action: () -> Void
}
```

## 五、键盘导航

所有面板添加基本键盘支持：

| 面板 | 按键 | 操作 |
|------|------|------|
| 剪贴板 | ↑↓ | 选择条目 |
| 剪贴板 | Enter | 粘贴选中的条目 |
| 剪贴板 | ⌘F | 聚焦搜索 |
| 剪贴板 | Esc | 关闭面板 / 清除搜索 |
| 待办 | ↑↓ | 选择条目 |
| 待办 | Enter | 编辑选中的条目 |
| 待办 | ⌘N | 新建待办 |
| 待办 | Esc | 关闭面板 |
| 翻译 | ⌘C | 复制译文 |
| 翻译 | ⌘Enter | 重新翻译 |
| 翻译 | Esc | 关闭面板 |
| 网关 | ↑↓ | 选择配置 |
| 网关 | Enter | 切换配置 |
| 网关 | Esc | 关闭面板 |

## 六、深色模式一致性

- 所有背景使用 `.regularMaterial`（自动适配）
- 所有文字使用 `OneBoardColors.textPrimary/Second/Tertiary`（自动适配）
- 阴影在深色模式下减轻（`OneBoardShadow` 中自动处理）
- 不需要任何 `@Environment(\.colorScheme)` 判断

---

## 七、实施顺序

| 阶段 | 内容 | 预计时间 |
|------|------|---------|
| Phase 1 | 统一 Header + Row 组件 + 面板壳模板 | 1h |
| Phase 2 | 剪贴板面板重构 | 1h |
| Phase 3 | 待办面板重构 | 1.5h |
| Phase 4 | 翻译面板重构 | 1h |
| Phase 5 | 网关面板重构 | 0.5h |
| Phase 6 | 键盘导航 | 1h |
| Phase 7 | 全量测试 + 深色模式 | 0.5h |

---

## 八、改动文件清单

| 文件 | 改动量 | 说明 |
|------|--------|------|
| `ComponentLibrary.swift` | 新增 | PanelHeaderView + PanelRowView + 面板壳 |
| `ClipboardPopoverView.swift` | 中改 | 重构为现代风格 |
| `ClipboardRowView.swift` | 中改 | 使用统一 PanelRowView |
| `ClipboardSearchBar.swift` | 小改 | 融入面板内 |
| `TodoSlidePanelView.swift` | 大改 | 重构 |
| `TodoRowView.swift` | 中改 | 使用统一 PanelRowView |
| `TodoHistoryView.swift` | 不改 | 保持 |
| `TranslationPanelView.swift` | 中改 | 重构布局 |
| `TranslationPanelWindowManager.swift` | 小改 | 窗口尺寸调整 |
| `GatewaySwitcherPanelView.swift` | 中改 | 重构 |

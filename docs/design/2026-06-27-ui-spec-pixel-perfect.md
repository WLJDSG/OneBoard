# OneBoard UI 精确规范（按 HTML 设计图还原）

**基准**：用户选择的 HTML 设计图
**设计选择**：系统原生 · 天空蓝 #4A9EF7 · SF Symbols · 8pt 圆角 · 毛玻璃 · 标准分割线 · 左竖条选中 · 胶囊按钮

---

## 全局统一规范

### 面板壳
```
background: .regularMaterial, in: RoundedRectangle(cornerRadius: 8)
shadow: Color.black.opacity(0.08), radius: 14, y: 4
无边框（material 自带层次）
```

### Header（所有面板一致）
```
高度: 40pt
左边: SF Symbol 图标 14pt accent + 标题 14pt semibold
右边: xmark 按钮 28×28pt, textSecondary, borderless
底部分割线: Divider
背景: surface.opacity(0.5)
水平内边距: 14pt
垂直内边距: 8pt
```

### 关闭按钮（所有面板统一）
```
SF Symbol: "xmark"
字体: system(size:12, weight:.medium)
frame: 28×28
颜色: textSecondary
buttonStyle: .borderless
```

### 搜索栏
```
背景: accent.opacity(0.06)
圆角: 8pt (OneBoardRadius.md)
内边距: h12 v8
图标: magnifyingglass 12pt textSecondary
文字: system(size:13) textPrimary
```

---

## 面板逐一规范

### 1. 剪贴板 ClipboardPopoverView（350×520）

```
┌────────────────────────────────┐
│ 📋 剪贴板                 [×]  │  header (40pt)
├────────────────────────────────┤
│ 🔍 搜索剪贴板...              │  search (36pt)
├────────────────────────────────┤
│ 已置顶                         │  section label (11pt, textTertiary, uppercase)
│ ┃ 📋 置顶文字...      2分钟   │  row (38pt, accentLight bg)
│ 📋 普通文字...        1小时前  │  row (38pt)
│ 🖼️ 图片.png           3小时前  │
├────────────────────────────────┤
│ 128 条记录 · 保留 30 天       │  status bar (28pt, 10pt textTertiary)
└────────────────────────────────┘
```

### 2. 待办 TodoSlidePanelView（320×480）

```
┌────────────────────────────────┐
│ ━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │  drag handle (36×4, warmGray30%)
│ ✓ 待办                   3    │  header (40pt) + count badge
├────────────────────────────────┤
│ ＋ 添加待办...                 │  quick-add row (36pt)
├────────────────────────────────┤
│ ● 买咖啡豆            Safari   │  row (38pt) + priority dot
│ ● 写完周报           VS Code   │
│ ○ 重构代码（已完成）   Xcode   │  completed = textTertiary + strikethrough
├────────────────────────────────┤
│ 🕐 历史                       │  bottom bar (28pt)
└────────────────────────────────┘
```

### 3. 翻译 TranslationPanelView（480×min400~max650）

```
┌──────────────────────────────────────┐
│ 🌐 翻译   [自动检测] → [中文]   [×]  │  header (40pt) + language bar
├──────────────────────────────────────┤
│ ┌──────────────────────────────────┐ │
│ │ 输入要翻译的文字...              │ │  source (min100pt, surface bg, 8pt radius)
│ └──────────────────────────────────┘ │
│                ↓                     │  arrow
│ ┌──────────────────────────────────┐ │
│ │ 翻译结果...                      │ │  target (min100pt, same style)
│ └──────────────────────────────────┘ │
│                                      │
│ [Apple ▼] · 使用系统翻译 · 支持离线  │  service + status
│ [翻译]              [复制原文][复制] │  pill buttons
└──────────────────────────────────────┘
```

### 4. 网关 GatewaySwitcherPanelView（340×380）

```
┌────────────────────────────────┐
│ 🔗 网关切换               [×]  │  header (40pt)
│     当前：192.168.1.1          │  subtitle (11pt textSecondary)
├────────────────────────────────┤
│ ┃ ● Profile A          ✓ 当前  │  selected row (44pt, accentLight bg + left bar)
│   ○ Profile B                  │  row (44pt)
│   ○ Profile C（暂停）          │  disabled row (44pt, opacity 0.5)
├────────────────────────────────┤
│ ⓘ DNS: 8.8.8.8, 1.1.1.1      │  info callout
│         管理配置...             │  center button
└────────────────────────────────┘
```

### 5. 暂存架 FileStagingView（320×400）

```
┌────────────────────────────────┐
│ 📁 暂存架              3  [×]  │  header (40pt) + count
├────────────────────────────────┤
│ ┌──────┐ ┌──────┐ ┌──────┐   │
│ │ 📄   │ │ 🖼️   │ │ 📦   │   │  file grid (88×100 tiles)
│ │ doc  │ │ img  │ │ arch │   │
│ └──────┘ └──────┘ └──────┘   │
└────────────────────────────────┘
```

### 6. 菜单栏图标
```
手绘 NSBezierPath 双方块 18×18pt
isTemplate = true → 跟随系统色
squareLength → 精确正方形
```

---

## 验收标准（自检清单）

- [ ] 所有面板使用 .regularMaterial 背景，8pt 圆角
- [ ] 所有面板 header 结构一致：图标(accent) + 标题(14pt semibold) + 关闭按钮(xmark 28×28)
- [ ] 所有关闭按钮样式一致
- [ ] 所有面板无边框（material 自带层次）
- [ ] 所有按钮使用胶囊 20pt 圆角
- [ ] 所有选中行使用 accent 左竖条 + accentLight 背景
- [ ] 所有颜色使用 OneBoardColors tokens
- [ ] 所有字体使用固定大小（system(size:)），不用动态 .font(.caption) 等
- [ ] SF Symbols 统一使用，无 emoji
- [ ] 深色/浅色模式均可用

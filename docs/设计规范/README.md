# OneBoard 设计规范

## 色彩系统

### 主色调 - 淡蓝色

| 色值 | 名称 | 用途 |
|------|------|------|
| `#59A6F2` | primary | 主色调，按钮、选中状态 |
| `#8CC7F8` | primaryLight | 浅色变体，背景色 |
| `#408CD9` | primaryDark | 深色变体，hover/按下状态 |

### 功能色

| 色值 | 名称 | 用途 |
|------|------|------|
| `#FFD980` | pinnedHighlight | 置顶条目高亮背景 |
| `#F25959` | destructive | 删除按钮 |
| 系统色 | background | 窗口背景 |
| 系统色 | textPrimary | 主要文字 |
| 系统色 | textSecondary | 次要文字 |

## 布局规范

### Popover（剪贴板列表）

- 宽度：350pt
- 高度：500pt
- 圆角：系统默认
- 行为：.transient（点击外部自动关闭）

### 列表项

- 内边距：水平 10pt，垂直 7pt
- 图标尺寸：28×28pt
- 预览文字：12pt，最多 2 行
- 时间标签：10pt，右对齐，宽度 55pt
- 行间距：2pt

### 搜索栏

- 背景：主色调 8% 透明度
- 圆角：8pt
- 内边距：水平 10pt，垂直 6pt

## 图标

- 应用图标：`square.on.square`（SF Symbol）
- 类型图标：使用 SF Symbol 系统图标
- 置顶图标：`pin.fill` / `pin.slash`
- 删除图标：`trash`

## 交互规范

1. **悬停效果**：列表行悬停时显示主色调 8% 背景 + 操作按钮
2. **点击粘贴**：点击条目 → 写入剪贴板 → 模拟 Cmd+V → 关闭 Popover
3. **右键菜单**：支持右键操作（粘贴、置顶、删除）
4. **搜索防抖**：输入后 300ms 触发搜索
5. **快捷键**：可自定义，默认 Cmd+Shift+C（剪贴板）、Cmd+Shift+A（截图）、Cmd+Shift+D（暂存架）

## 动画

- 悬停过渡：0.15s easeInOut
- Popover 弹出：系统默认动画
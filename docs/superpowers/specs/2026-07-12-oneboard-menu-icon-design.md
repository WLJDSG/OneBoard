# OneBoard 菜单栏图标设计

## 目标

将现有的双小方块图标替换为更完整的“One Board”单色品牌符号，并在 macOS 菜单栏 18×18pt 的浅色、深色背景上保持清晰。

## 视觉方向

使用已确认的 B 方案：

- 主面板是较完整的圆角矩形，表达 OneBoard 的主工作台。
- 右上方露出第二层面板，保留“多项收集、暂存”的含义。
- 主面板内放置两条长短不同的横线，暗示剪贴内容，不加对勾或文字。
- 线端、面板转角使用圆角，视觉更柔和。

## 实现

`MenuBarManager.createMenuBarIcon()` 使用 AppKit `NSBezierPath` 绘制，不依赖 SF Symbol 的 baseline 和版本差异。

- 画布：18×18pt。
- 图标占用画布中间约 14×14pt，四周保留 2pt 安全边距。
- 线宽：1.5pt，小数坐标对齐 Retina 像素。
- 图形使用黑色绘制后设为 `isTemplate = true`，由 macOS 自动着色。
- `NSStatusItem.squareLength` 和 `button.imagePosition = .imageOnly` 保持不变。

## 验证

- `swift build` 通过。
- 使用 `com.oneboard.mac.dev2` 构建开发包并启动。
- 实际截取菜单栏，确认图标持续显示、轮廓清晰、不含 `OB` 文字。
- 打开菜单确认点击区域和原有功能不变。
- 正式打包后运行 `hdiutil verify build/OneBoard.dmg`。

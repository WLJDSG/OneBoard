# OneBoard

macOS 原生截图 + 剪贴板 + 文件暂存一体化工具。

## 功能

### 截图模块
- **自定义遮罩截图**：半透明暗色遮罩，框选区域显示原图，按 Enter 确认 / Esc 取消
- **像素尺寸预览**：选区右上角实时 W×H
- **方向键微调**：方向键 1px，Shift+10px 调整选区
- **智能窗口截图**：鼠标悬浮自动高亮窗口轮廓，单击截取
- **标注工具**：矩形、椭圆、箭头、直线、文字（微信风格）、编号圆圈、马赛克
- **粗细循环**：± 按钮到达边界自动循环
- **OCR 文字识别**：弹性弹窗 + 智能定位
- **翻译**：Apple Translation / DeepSeek AI
- **贴图置顶**：截图悬浮在所有窗口之上
- **撤销/重做**：无限步操作历史

### 剪贴板模块
- 全类型记录（文字/图片/文件）
- 搜索、置顶、删除
- 时间倒序 + 保留策略（按天数/条数）

### 文件暂存模块
- 拖拽文件晃动触发暂存区
- 文件暂存 + 全局置顶 + 拖出发送

### 其他
- 全局快捷键自定义
- 菜单栏常驻图标
- 开机自启

## 技术栈

- Swift 5.9+ / SwiftUI + AppKit
- macOS 14.0+
- SQLite (GRDB.swift)
- SPM 依赖管理

## 构建

\`\`\`bash
cd OneBoard && swift build -c release
bash script/package_app.sh
\`\`\`

## 项目结构

\`\`\`
OneBoard/
├── App/              # 应用入口
├── Core/             # 核心基础设施
├── Modules/
│   ├── Clipboard/    # 剪贴板模块
│   ├── Screenshot/   # 截图模块
│   ├── FileStaging/  # 文件暂存模块
│   └── Gateway/      # 网关切换模块
├── Shared/           # 共享服务
└── Resources/        # 资源文件
\`\`\`

## 文档

- [需求文档](docs/需求文档/README.md)
- [技术规范](docs/技术规范/README.md)
- [设计规范](docs/设计规范/README.md)
- [开发步骤](docs/开发步骤/README.md)
- [开发日志](开发日志/)

# OneBoard

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014.0+-blue" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift%205.9-orange" alt="Language">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
</p>

**OneBoard** 是一款 macOS 原生应用，整合**截图工具**、**历史剪贴板**、**文件暂存**和**翻译工作台**，提供简洁高效的日常工作流体验。

## 功能

### 📸 截图工具
- **区域截图** — 框选屏幕任意区域
- **贴图置顶** — 截图后贴在屏幕上，置顶不遮挡
- **标注工具** — 文字、直线、矩形、箭头、马赛克、高亮
- **OCR 文字识别** — 基于 Apple Vision，离线免费
- **截图翻译** — OCR 后可进入独立翻译工作台

### 📋 历史剪贴板
- **全类型记录** — 文字、图片、文件、HTML/RTF
- **时间倒序** — 置顶优先，一目了然
- **全文搜索** — FTS5 搜索引擎
- **中文友好搜索** — 支持子串模糊匹配
- **点击粘贴** — 一键回贴到任意应用
- **存储策略** — 按条数/天数自动清理

### 📁 文件暂存
- **摇动触发** — 拖拽文件晃动即可唤出暂存区
- **悬浮置顶** — 文件暂存后浮在屏幕上，随时拖出发送
- **拖出即发** — 切换应用后拖出文件即可发送

### 🌐 翻译工作台
- **独立浮框** — 支持编辑原文、查看译文和复制结果
- **多服务切换** — 支持 Apple、Google Web、DeepSeek
- **语言控制** — 支持源语言/目标语言选择、交换和重新翻译
- **快捷入口** — 支持截图翻译和选中文字翻译统一进入工作台

### 🛜 网关切换
- **一键切换** — 支持当前默认网络服务的网关和 DNS 切换
- **仅 DNS 模式** — 可创建只修改 DNS、不改默认网关的配置
- **配置管理** — 支持新增、编辑、删除网关 Profile
- **快捷小窗** — 默认 `Cmd+Shift+G` 唤出网关切换面板
- **免密 Helper** — 可安装 OneBoard 专属 helper，减少重复管理员授权

## 截图

> *快捷键：`Cmd+Shift+C` 剪贴板 · `Cmd+Shift+A` 截图 · `Cmd+Shift+D` 暂存架*

## 安装

### 下载 DMG

从 [Releases](https://github.com/WLJDSG/OneBoard/releases) 页面下载最新 DMG，拖入 `/Applications` 即可。

### 从源码构建

```bash
git clone https://github.com/WLJDSG/OneBoard.git
cd OneBoard/OneBoard
swift build -c release
```

### 首次启动

由于应用未签名，首次启动需在终端运行：

```bash
xattr -cr /Applications/OneBoard.app
```

## 权限

| 权限 | 用途 |
|------|------|
| 辅助功能 | 自动粘贴到其他应用、拖拽检测 |
| 屏幕录制 | 截图功能 |
| 网关 Helper | 免密切换网关和 DNS |

首次使用对应功能时会自动弹出引导。

## 技术栈

| 层级 | 技术 |
|------|------|
| UI | SwiftUI + AppKit |
| 数据库 | SQLite（GRDB.swift） |
| 快捷键 | KeyboardShortcuts |
| OCR | Apple Vision |
| 翻译 | Apple Translation / Google Web / DeepSeek |
| 架构 | MVVM + Service Layer |

## 项目结构

```
OneBoard/
├── App/              # 应用入口 + 设置窗口
├── Core/             # 数据库、主题、工具类
├── Shared/           # 快捷键、菜单栏、权限管理
└── Modules/
    ├── Clipboard/    # 历史剪贴板模块
    ├── Screenshot/   # 截图模块
    ├── FileStaging/  # 文件暂存模块
    └── Gateway/      # 网关切换模块
```

## 开发

```bash
cd OneBoard
swift build          # 编译
swift build -c release  # 编译 Release 版本
```

## 参考

- [Snipaste](https://www.snipaste.com/) — 截图工具参考
- [Maccy](https://maccy.app/) — 剪贴板工具参考
- [Dropover](https://dropoverapp.com/) — 文件暂存参考

## 许可

MIT License

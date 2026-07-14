# OneBoard 打包与修复流程

本文档记录 OneBoard 的标准打包方法，以及以后修复 bug 时必须遵循的闭环流程。

## 打包产物

- 标准安装包只交付 `build/OneBoard.dmg`
- DMG 内应包含 `OneBoard.app` 和 `Applications` 软链接
- 不额外交付 `.app`、`.pkg`、zip 或其他安装产物，除非用户明确要求

## 标准打包命令

在仓库根目录执行：

```bash
script/package_app.sh
```

脚本会自动完成：

1. 执行 `script/build_app_bundle.sh`
2. 使用 SwiftPM 编译 Release 版本
3. 生成 `build/OneBoard.app`
4. 放入 LaunchAtLogin helper
5. 对 helper 和主 App 签名
6. 校验 app bundle 签名
7. 生成 `build/OneBoard.dmg`

## 签名身份

默认情况下，脚本会尝试查找可用的 `Developer ID Application` 或 `Apple Development` 签名身份。

如果自动选择到的证书不可用，或只是本地测试安装包，可以显式使用 ad-hoc 签名：

```bash
ONEBOARD_CODESIGN_IDENTITY=- script/package_app.sh
```

在 Codex 沙盒环境里，如果 `hdiutil create` 报“设备未配置”，需要在获得用户许可后在沙盒外执行同一个打包命令。不要绕过脚本手工拼装 DMG。

## 打包后验证

打包前先从 `OneBoard/` 目录执行全量测试和 Release 构建：

```bash
cd OneBoard
swift test --disable-sandbox
swift build -c release --disable-sandbox
cd ..
```

打包完成后必须验证 DMG：

```bash
hdiutil verify build/OneBoard.dmg
```

看到类似以下结果才算安装包有效：

```text
hdiutil: verify: checksum of "build/OneBoard.dmg" is VALID
```

可选检查产物大小：

```bash
ls -lh build/OneBoard.dmg
```

涉及 Finder 扩展或跨进程功能时，还必须挂载最终 DMG 检查真实产物，不能只检查打包过程中短暂存在的 `build/OneBoard.app`：

```bash
hdiutil attach -readonly -nobrowse build/OneBoard.dmg
codesign --verify --deep --strict --verbose=2 /Volumes/OneBoard/OneBoard.app
test -x /Volumes/OneBoard/OneBoard.app/Contents/PlugIns/OneBoardFinderSync.appex/Contents/MacOS/OneBoardFinderSync
```

Finder 新建文件链路可在临时目录做端到端验证：启动 DMG 内 App 后，打开 `oneboard://new-file` URL，确认目标目录出现 `未命名.txt`。测试目录必须使用临时路径，不要污染用户桌面或文档目录。

## 修 bug 标准流程

每次修 bug 都必须按以下闭环执行：

1. **确定范围**：先明确 bug 影响的功能、入口、模块和复现条件，不扩大到无关重构。
2. **查清原因**：阅读相关需求、技术规范和代码；用日志、构建错误、复现结果或代码路径说明 bug 为什么发生。
3. **最小修复**：只修改必要文件，优先沿用现有架构和代码风格，避免顺手重构。
4. **验证修复**：先让针对真实症状的回归测试失败，再修复并运行定向测试、全量 `swift test` 和 Release 构建。
5. **未修复则继续**：如果验证失败，回到原因分析，继续修复和验证，直到确认修复为止。
6. **重新打包**：确认 bug 修复后，重新执行标准打包命令生成 `build/OneBoard.dmg`。
7. **验证安装包**：执行 `hdiutil verify build/OneBoard.dmg`，确认 DMG 有效。
8. **记录结果**：在开发日志中记录修复范围、根因、改动、测试数量、验证命令、DMG checksum 和无法自动完成的肉眼验收项。

涉及真实 macOS 手势的修复还必须列出人工验收项。例如截图框选需要验证顶部/中央/底部位置、移动、八方向缩放和标注后锁定；文件暂存需要验证普通文件可触发，而应用窗口、目录和 `.app` 不触发。自动化测试只能证明坐标与状态逻辑，不能代替真实鼠标手势验收。

## Codex 执行要求

以后 Codex 处理本项目 bug 或打包请求时，必须先阅读：

- `AGENTS.md`
- `docs/打包与修复流程/README.md`
- 与本次修改相关的需求、技术或设计文档

涉及代码修改时，必须在最终回复中说明：

- bug 范围
- 根因
- 最小修复内容
- 验证结果
- 新安装包路径

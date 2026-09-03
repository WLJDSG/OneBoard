import AppKit
import Darwin
import OneBoardKit

if CommandLine.arguments.contains("--import-cc-switch") {
    do {
        print(try OneBoardCommandLine.importCCSwitch())
        exit(EXIT_SUCCESS)
    } catch {
        fputs("CC Switch import failed: \(error.localizedDescription)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

// 模块隔离架构：NSStatusItem 必须在入口模块创建，确保 macOS 26 兼容性
// 业务代码全部在 OneBoardKit 独立模块中
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
MenuBarManager.shared.configure(statusItem: statusItem)

let delegate = AppDelegate()
app.delegate = delegate

app.run()

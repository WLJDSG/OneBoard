import AppKit
import OneBoardKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.async {
    SettingsWindowManager.shared.show()
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        guard let window = app.windows.first(where: { $0.title == "OneBoard 设置" }), window.isVisible else { exit(1) }
        window.contentView?.layoutSubtreeIfNeeded()
        SettingsWindowManager.shared.show()
        guard window.isVisible else { exit(2) }
        print("PASS: cold settings open, layout and reopen")
        exit(0)
    }
}
app.run()

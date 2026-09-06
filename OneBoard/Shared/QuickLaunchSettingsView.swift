import SwiftUI
import AppKit
import KeyboardShortcuts

struct QuickLaunchBinding: Codable {
    var kind = "app"
    var target = ""
    var title = ""
}

@MainActor
enum QuickLaunchBindings {
    static let rows = [Array("1234567890-="), Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]
    static let storageKey = "quickLaunch.bindings"
    static func load() -> [String: QuickLaunchBinding] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: QuickLaunchBinding].self, from: data)) ?? [:]
    }
    static func name(_ key: String) -> KeyboardShortcuts.Name { .init("quickLaunch." + key) }
    static func register() {
        for key in rows.flatMap({ $0 }).map(String.init) {
            KeyboardShortcuts.onKeyDown(for: name(key)) {
                Task { @MainActor in
                    guard let binding = load()[key] else { return }
                    run(binding)
                }
            }
        }
    }
    static func run(_ binding: QuickLaunchBinding) {
        switch binding.kind {
        case "app", "file", "folder":
            NSWorkspace.shared.open(URL(fileURLWithPath: binding.target))
        case "web":
            if let url = URL(string: binding.target), ["https", "http"].contains(url.scheme ?? "") { NSWorkspace.shared.open(url) }
        case "shortcut":
            var url = URLComponents()
            url.scheme = "shortcuts"; url.host = "run-shortcut"
            url.queryItems = [URLQueryItem(name: "name", value: binding.target)]
            if let target = url.url { NSWorkspace.shared.open(target) }
        case "tool":
            switch binding.target {
            case "clipboard": MenuBarManager.shared.showClipboardAsFloatingWindow()
            case "calendar": CalendarPanelWindowManager.shared.show()
            case "status": MacStatusWindowManager.shared.card.toggle()
            case "shelf": FileStagingViewModel.shared.toggleFloatingShelf()
            case "todo": TodoSlidePanelWindowManager.shared.toggle()
            case "screenshot": Task { await ScreenshotViewModel.shared.startCapture() }
            case "translate": Task { await ScreenshotViewModel.shared.translateSelectedText() }
            default: break
            }
        default: break
        }
    }
}

struct QuickLaunchSettingsView: View {
    @State private var bindings = QuickLaunchBindings.load()
    @State private var editing: String?
    @State private var draft = QuickLaunchBinding()
    private let tools = [("clipboard", "剪贴板"), ("calendar", "日历"), ("status", "Mac 状态"), ("shelf", "暂存区"), ("todo", "待办"), ("screenshot", "截图"), ("translate", "翻译选中文字")]
    var body: some View {
        VStack(spacing: 12) {
            Text("点击键位配置动作与快捷键").font(.headline)
            Text("键位用于整理动作；请录制带修饰键的全局快捷键，不会占用普通字母输入。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<QuickLaunchBindings.rows.count, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(QuickLaunchBindings.rows[row].map(String.init), id: \.self) { key in
                        Button {
                            draft = bindings[key] ?? QuickLaunchBinding()
                            editing = key
                        } label: {
                            VStack(spacing: 5) {
                                Text(key).font(.system(size: 17, weight: .semibold))
                                Text(bindings[key]?.title.isEmpty == false ? bindings[key]!.title : "绑定")
                                    .font(.system(size: 9)).lineLimit(1)
                            }.frame(maxWidth: .infinity).frame(height: 57)
                                .background(bindings[key] == nil ? Color.primary.opacity(0.035) : Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, CGFloat(row) * 18)
            }
        }.padding(.vertical, 12)
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let key = editing {
                VStack(alignment: .leading, spacing: 16) {
                    Text("配置键位 " + key).font(.title2)
                    Picker("动作类型", selection: $draft.kind) {
                        Text("应用").tag("app"); Text("文件").tag("file"); Text("文件夹").tag("folder")
                        Text("网页").tag("web"); Text("快捷指令").tag("shortcut"); Text("OneBoard 工具").tag("tool")
                    }.onChange(of: draft.kind) { _, kind in draft.target = kind == "tool" ? "clipboard" : "" }
                    TextField("显示名称", text: $draft.title)
                    if draft.kind == "tool" {
                        Picker("工具", selection: $draft.target) {
                            ForEach(tools, id: \.0) { value in Text(value.1).tag(value.0) }
                        }
                    } else {
                        TextField(draft.kind == "shortcut" ? "快捷指令名称" : "路径或完整网页地址", text: $draft.target)
                        if ["app", "file", "folder"].contains(draft.kind) {
                            Button("选择…") { chooseFile() }
                        }
                    }
                    KeyboardShortcuts.Recorder("全局快捷键", name: QuickLaunchBindings.name(key))
                    Text("快捷键录制立即保存；动作在点击保存后生效。删除绑定不会删除文件。")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("删除绑定") { bindings.removeValue(forKey: key); save(); KeyboardShortcuts.reset(QuickLaunchBindings.name(key)); editing = nil }
                        Spacer()
                        Button("取消") { editing = nil }
                        Button("保存") { bindings[key] = draft; save(); editing = nil }.disabled(draft.target.isEmpty)
                    }
                }.textFieldStyle(.roundedBorder).padding(24).frame(width: 440)
            }
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(bindings) { UserDefaults.standard.set(data, forKey: QuickLaunchBindings.storageKey) }
    }
    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = draft.kind == "folder"
        panel.canChooseFiles = draft.kind != "folder"
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            draft.target = url.path
            if draft.title.isEmpty { draft.title = url.deletingPathExtension().lastPathComponent }
        }
    }
}

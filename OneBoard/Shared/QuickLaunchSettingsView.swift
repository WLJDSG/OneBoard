import SwiftUI
import AppKit
import KeyboardShortcuts

struct QuickLaunchBinding: Codable {
    var kind = "app"
    var target = ""
    var title = ""
    var imageData: Data?
    var displayTitle: String {
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
        if ["app", "file", "folder"].contains(kind) { return URL(fileURLWithPath: target).deletingPathExtension().lastPathComponent }
        return target
    }
}

@MainActor
enum QuickLaunchBindings {
    static let rows = [Array("1234567890"), Array("QWERTYUIOP"), Array("ASDFGHJKL"), Array("ZXCVBNM")]
    static let storageKey = "quickLaunch.bindings"
    static func load(defaults: UserDefaults = .standard) -> [String: QuickLaunchBinding] {
        guard let data = defaults.data(forKey: storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: QuickLaunchBinding].self, from: data)) ?? [:]
    }
    static func name(_ key: String) -> KeyboardShortcuts.Name { .init("quickLaunch." + key) }
    static let keys: [KeyboardShortcuts.Key] = [.one,.two,.three,.four,.five,.six,.seven,.eight,.nine,.zero,.q,.w,.e,.r,.t,.y,.u,.i,.o,.p,.a,.s,.d,.f,.g,.h,.j,.k,.l,.z,.x,.c,.v,.b,.n,.m]
    static let legacyNames: [KeyboardShortcuts.Name] = [.showClipboard, .captureScreenshot, .translateSelectedText, .showFileShelf, .showGatewaySwitcher, .toggleTodoPanel, .addSelectedTextToTodo]
    static let tools = [("clipboard", "剪贴板", "doc.on.clipboard"), ("screenshot", "截图", "camera.viewfinder"), ("translate", "翻译", "character.bubble"), ("shelf", "暂存区", "tray.full"), ("gateway", "网关", "network"), ("todo", "待办", "checklist"), ("addTodo", "选文到待办", "text.badge.plus"), ("calendar", "日历", "calendar"), ("status", "Mac 状态", "gauge.with.dots.needle.50percent")]
    static func migrate(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: "quickLaunch.optionMigration") else { return }
        var bindings = load(defaults: defaults)
        let preferred = ["V", "A", "T", "D", "G", "N", "B"]
        let letters = rows.flatMap { $0 }.map(String.init)
        for symbol in ["-", "="] {
            if let binding = bindings[symbol], let slot = letters.first(where: { bindings[$0] == nil }) {
                bindings[slot] = binding
                bindings.removeValue(forKey: symbol)
            }
        }
        for (index, legacy) in legacyNames.enumerated() {
            let target = tools[index]
            guard !bindings.values.contains(where: { $0.kind == "tool" && $0.target == target.0 }) else { continue }
            let oldKey = KeyboardShortcuts.getShortcut(for: legacy)?.key
            let oldLetter = oldKey.flatMap { keys.firstIndex(of: $0) }.map { letters[$0] }
            let candidates = [oldLetter, Optional(preferred[index])].compactMap { $0 } + letters
            if let slot = candidates.first(where: { bindings[$0] == nil }) {
                bindings[slot] = QuickLaunchBinding(kind: "tool", target: target.0, title: target.1)
            }
        }
        if let data = try? JSONEncoder().encode(bindings) { defaults.set(data, forKey: storageKey) }
        defaults.set(true, forKey: "quickLaunch.optionMigration")
    }
    private static var handlersRegistered = false
    static func register() {
        migrate()
        for legacy in legacyNames { KeyboardShortcuts.setShortcut(nil, for: legacy) }
        for symbol in ["-", "="] { KeyboardShortcuts.setShortcut(nil, for: name(symbol)) }
        let bindings = load()
        for (index, key) in rows.flatMap({ $0 }).map(String.init).enumerated() {
            KeyboardShortcuts.setShortcut(bindings[key] == nil ? nil : .init(keys[index], modifiers: [.option]), for: name(key))
        }
        guard !handlersRegistered else { return }
        handlersRegistered = true
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
            case "gateway": MenuBarManager.shared.toggleGatewaySwitcherPanel()
            case "addTodo": TodoListViewModel.shared.addSelectedTextFromFrontmostApp()
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
    @State private var menuKey: String?
    @State private var draft = QuickLaunchBinding()
    @State private var shortcutNames: [String] = []
    private let tools = QuickLaunchBindings.tools.map { ($0.0, $0.1) }
    var body: some View {
        VStack(spacing: 12) {
            Text("点击键位配置动作与快捷键").font(.headline)
            Text("按 Option ＋ 字母或数字即可执行。点击键位选择或更换绑定。")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(0..<QuickLaunchBindings.rows.count, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(QuickLaunchBindings.rows[row].map(String.init), id: \.self) { key in
                        Button {
                            draft = bindings[key] ?? QuickLaunchBinding()
                            menuKey = key
                        } label: {
                            VStack(spacing: 5) {
                                if let binding = bindings[key] {
                                    if binding.kind == "app" {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: binding.target)).resizable().frame(width: 30, height: 30)
                                    } else if binding.kind == "web" {
                                        webThumbnail(binding)
                                    } else {
                                        Image(systemName: toolIcon(binding.target)).font(.system(size: 23)).foregroundStyle(.blue).frame(height: 30)
                                    }
                                } else { Text(key).font(.system(size: 19, weight: .semibold)).frame(height: 30) }
                                Text("⌥" + key).font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                                Text(bindings[key]?.displayTitle ?? "绑定")
                                    .font(.system(size: 9)).lineLimit(1)
                            }.frame(maxWidth: .infinity).frame(height: 82)
                                .background(bindings[key] == nil ? Color.primary.opacity(0.035) : Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                        }.buttonStyle(.plain)
                        .popover(isPresented: Binding(get: { menuKey == key }, set: { if !$0 { menuKey = nil } }), arrowEdge: .bottom) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let binding = bindings[key] {
                                    Text("⌥\(key) · \(binding.displayTitle)").font(.caption).foregroundStyle(.secondary).padding(8)
                                    Divider()
                                }
                                ForEach([("app","应用","app.dashed"),("file","文件","doc"),("folder","文件夹","folder"),("web","网页","globe"),("shortcut","快捷指令","sparkles"),("tool","OneBoard 工具","square.grid.2x2")], id: \.0) { kind in
                                    Button {
                                        draft = QuickLaunchBinding(kind: kind.0)
                                        menuKey = nil
                                        if kind.0 == "file" || kind.0 == "folder" {
                                            DispatchQueue.main.async { chooseFile(for: key, kind: kind.0) }
                                        } else {
                                            if kind.0 == "shortcut" { loadShortcuts() }
                                            DispatchQueue.main.async { editing = key }
                                        }
                                    } label: {
                                        Label(kind.1, systemImage: kind.2).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                    }.buttonStyle(.plain)
                                }
                                if bindings[key] != nil {
                                    Divider()
                                    Button("解除绑定") { bindings.removeValue(forKey: key); save(); menuKey = nil }.padding(9)
                                }
                            }.padding(8).frame(width: 210)
                        }
                    }
                }.padding(.horizontal, CGFloat(row) * 18)
            }
        }.padding(.vertical, 12)
        .onAppear { QuickLaunchBindings.migrate(); bindings = QuickLaunchBindings.load() }
        .sheet(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            if let key = editing {
                switch draft.kind {
                case "app": applicationPicker
                case "tool": toolPicker
                case "shortcut": shortcutPicker
                default:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("绑定网页 · Option ＋ " + key).font(.title2)
                        TextField("显示名称", text: $draft.title)
                        TextField("https://example.com", text: $draft.target)
                        HStack {
                            webThumbnail(draft)
                            Button(draft.imageData == nil ? "选择图片…" : "更换图片…") { chooseWebImage() }
                            if draft.imageData != nil { Button("使用默认缩略图") { draft.imageData = nil } }
                        }
                        HStack {
                            Spacer()
                            Button("取消") { editing = nil }
                            Button("绑定") { commitDraft() }
                                .buttonStyle(SettingsActionStyle(prominent: true))
                                .disabled(!["https", "http"].contains(URL(string: draft.target)?.scheme ?? ""))
                        }
                    }.textFieldStyle(.roundedBorder).padding(24).frame(width: 440)
                }
            }
        }
    }
    private func save() {
        if let data = try? JSONEncoder().encode(bindings) { UserDefaults.standard.set(data, forKey: QuickLaunchBindings.storageKey) }
        QuickLaunchBindings.register()
    }
    private func chooseFile(for key: String, kind: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = kind == "folder"
        panel.canChooseFiles = kind == "file"
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bindings[key] = QuickLaunchBinding(
            kind: kind,
            target: url.path,
            title: url.deletingPathExtension().lastPathComponent
        )
        save()
    }

    private func chooseWebImage() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = ["png", "jpg", "jpeg", "heic", "webp"]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.imageData = try? Data(contentsOf: url)
    }

    @ViewBuilder
    private func webThumbnail(_ binding: QuickLaunchBinding) -> some View {
        if let data = binding.imageData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
            let host = URL(string: binding.target)?.host?.replacingOccurrences(of: "www.", with: "") ?? binding.target
            let name = host.split(separator: ".").first.map(String.init) ?? "WEB"
            Text(String(name.prefix(2)).uppercased())
                .font(.system(size: 10, weight: .bold))
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private func commitDraft() {
        guard let key = editing, !draft.target.isEmpty else { return }
        bindings[key] = draft
        save()
        editing = nil
    }

    private var applicationPicker: some View {
        TargetPicker(title: "选择应用", items: installedApplications.map { ($0.path, $0.deletingPathExtension().lastPathComponent, "app.fill") }) { item in
            draft.target = item.0; draft.title = item.1; commitDraft()
        }
    }
    private var toolPicker: some View {
        TargetPicker(title: "选择 OneBoard 工具", items: tools.map { ($0.0, $0.1, toolIcon($0.0)) }) { item in
            draft.target = item.0; draft.title = item.1; commitDraft()
        }
    }
    private var shortcutPicker: some View {
        TargetPicker(title: "选择快捷指令", items: shortcutNames.map { ($0, $0, "sparkles") }) { item in
            draft.target = item.0; draft.title = item.1; commitDraft()
        }
    }

    private func loadShortcuts() {
        Task {
            let names = await Task.detached(priority: .userInitiated) { () -> [String] in
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = ["list"]
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do { try process.run(); process.waitUntilExit() } catch { return [] }
                guard process.terminationStatus == 0 else { return [] }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)?
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty } ?? []
            }.value
            shortcutNames = names
        }
    }
    private var installedApplications: [URL] {
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications"), URL(fileURLWithPath: "/System/Applications/Utilities"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var applications: [URL] = []
        for root in roots {
            let contents = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            applications.append(contentsOf: contents.filter { $0.pathExtension.lowercased() == "app" })
        }
        return applications.sorted { $0.lastPathComponent.localizedCompare($1.lastPathComponent) == .orderedAscending }
    }
    private func toolIcon(_ id: String) -> String {
        QuickLaunchBindings.tools.first { $0.0 == id }?.2 ?? "doc"
    }
}

private struct TargetPicker: View {
    let title: String
    let items: [(String, String, String)]
    let select: ((String, String, String)) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text(title).font(.title2.bold()); Spacer(); Button("取消") { dismiss() } }
            TextField("搜索", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 10)], spacing: 10) {
                    ForEach(Array(filtered.enumerated()), id: \.offset) { _, item in
                        Button { select(item) } label: {
                            VStack(spacing: 8) {
                                if item.0.hasSuffix(".app") {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.0)).resizable().frame(width: 38, height: 38)
                                } else { Image(systemName: item.2).font(.system(size: 28)).frame(height: 38) }
                                Text(item.1).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            }.frame(maxWidth: .infinity).padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(22).frame(width: 520, height: 430)
    }
    private var filtered: [(String, String, String)] { query.isEmpty ? items : items.filter { $0.1.localizedCaseInsensitiveContains(query) } }
}

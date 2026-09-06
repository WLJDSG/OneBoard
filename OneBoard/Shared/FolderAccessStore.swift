import AppKit
import SwiftUI

enum OneBoardFolderAccess: String, CaseIterable, Identifiable {
    case desktop, iCloud
    var id: String { rawValue }
    var title: String { self == .desktop ? "桌面文件夹" : "iCloud Drive" }
    var purpose: String { self == .desktop ? "截图保存与桌面新建文件" : "配置备份与重装恢复，仅写入 app/oneboard" }
    var expectedURL: URL {
        if self == .iCloud { return ICloudBackupStore.driveRoot }
        return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }
    var bookmarkKey: String { "local.folderAccess." + rawValue }
}

final class AuthorizedFolder {
    let url: URL
    private let scoped: Bool
    init(url: URL) { self.url = url; scoped = url.startAccessingSecurityScopedResource() }
    deinit { if scoped { url.stopAccessingSecurityScopedResource() } }
}

/// 本机书签不参与云备份；启动仅检查本地记录，不探测未授权的用户目录。
struct FolderAccessStore {
    var defaults: UserDefaults = .standard
    func hasRecord(_ kind: OneBoardFolderAccess) -> Bool { defaults.data(forKey: kind.bookmarkKey) != nil }
    func resolve(_ kind: OneBoardFolderAccess) throws -> AuthorizedFolder {
        guard let data = defaults.data(forKey: kind.bookmarkKey) else { throw FolderAccessError.required(kind.title) }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let access = AuthorizedFolder(url: url)
        if stale { try save(url, for: kind) }
        return access
    }
    static func matchesDirectory(_ url: URL, expected: URL) -> Bool {
        url.resolvingSymlinksInPath().standardizedFileURL.path == expected.resolvingSymlinksInPath().standardizedFileURL.path
    }
    func save(_ url: URL, for kind: OneBoardFolderAccess) throws {
        let access = AuthorizedFolder(url: url)
        defer { withExtendedLifetime(access) {} }
        let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: kind.bookmarkKey)
    }
    func remove(_ kind: OneBoardFolderAccess) { defaults.removeObject(forKey: kind.bookmarkKey) }
}

enum FolderAccessError: LocalizedError {
    case required(String)
    var errorDescription: String? {
        switch self { case .required(let title): return "请在设置 → 授权中选择\(title)，不会在启动时弹出文件夹请求" }
    }
}

struct FolderAuthorizationView: View {
    @State private var saved: Set<OneBoardFolderAccess> = []
    @State private var messages: [OneBoardFolderAccess: String] = [:]
    var body: some View {
        ForEach(OneBoardFolderAccess.allCases) { kind in
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: kind == .iCloud ? "icloud" : "folder")
                    .font(.system(size: 18)).foregroundStyle(SettingsPalette.accent)
                    .frame(width: 40, height: 40)
                    .background(SettingsPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(kind.title).fontWeight(.medium)
                        if saved.contains(kind) {
                            Label("已连接", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(SettingsPalette.teal)
                        }
                    }
                    Text(kind.purpose).font(.caption).foregroundStyle(.secondary)
                    if let message = messages[kind] {
                        Text(message).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button(saved.contains(kind) ? "更改文件夹" : "允许访问") { choose(kind) }
                    .buttonStyle(SettingsActionStyle(prominent: !saved.contains(kind)))
                if saved.contains(kind) {
                    Button {
                        FolderAccessStore().remove(kind)
                        saved.remove(kind)
                        messages[kind] = nil
                        if kind == .iCloud { CloudSyncViewModel.shared.setEnabled(false) }
                    } label: { Image(systemName: "xmark").frame(width: 16, height: 16) }
                    .buttonStyle(SettingsActionStyle()).help("断开文件夹访问")
                }
            }.padding(.vertical, 4)
        }
        Text("文件访问用于保存截图与备份；本地网络用于局域网连接；App 管理用于应用内彻底卸载。以下权限由系统按实际操作请求，授权状态请在系统设置中查看。")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Button("文件与文件夹权限") { openPrivacy("Privacy_FilesAndFolders") }
            Button("App 管理") { openPrivacy("Privacy_AppBundles") }
            Button("本地网络权限") { openPrivacy("Privacy_LocalNetwork") }
        }
        Text("移除书签会停止 OneBoard 复用该目录访问；如需撤销系统授权，请前往系统设置。")
            .font(.caption).foregroundStyle(.secondary)
        .onAppear { saved = Set(OneBoardFolderAccess.allCases.filter { FolderAccessStore().hasRecord($0) }) }
    }
    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
    private func choose(_ kind: OneBoardFolderAccess) {
        let panel = NSOpenPanel()
        panel.title = "授权 " + kind.title
        panel.message = "选择\(kind.title)，用于\(kind.purpose)。"
        panel.prompt = "允许访问"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = kind.expectedURL
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard FolderAccessStore.matchesDirectory(url, expected: kind.expectedURL) else {
                    messages[kind] = "请选择\(kind.title)，备份与截图位置保持不变。"; return
                }
                try FolderAccessStore().save(url, for: kind)
                saved.insert(kind)
                messages[kind] = nil
                if kind == .iCloud { CloudSyncViewModel.shared.folderAuthorizationDidChange() }
            } catch { messages[kind] = error.localizedDescription }
        }
    }
}

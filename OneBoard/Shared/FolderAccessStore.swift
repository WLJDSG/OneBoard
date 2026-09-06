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
    func save(_ url: URL, for kind: OneBoardFolderAccess) throws {
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
    @State private var message: String?
    var body: some View {
        ForEach(OneBoardFolderAccess.allCases) { kind in
            HStack(alignment: .top) {
                Image(systemName: kind == .iCloud ? "icloud" : "folder").frame(width: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(kind.title).fontWeight(.medium)
                    Text(kind.purpose).font(.caption).foregroundStyle(.secondary)
                    Text(saved.contains(kind) ? "已保存本机访问书签" : "尚未选择文件夹").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(saved.contains(kind) ? "重新选择" : "选择文件夹") { choose(kind) }
                if saved.contains(kind) {
                    Button("移除") {
                        FolderAccessStore().remove(kind)
                        saved.remove(kind)
                        if kind == .iCloud { CloudSyncViewModel.shared.setEnabled(false) }
                    }.buttonStyle(.borderless)
                }
            }.padding(.vertical, 4)
        }
        Text("其他文件、文件夹、自动化与本地网络访问由 macOS 按实际使用请求；系统没有公开的通用授权状态查询接口。")
            .font(.caption).foregroundStyle(.secondary)
        HStack {
            Button("文件与文件夹权限") { openPrivacy("Privacy_FilesAndFolders") }
            Button("自动化权限") { openPrivacy("Privacy_Automation") }
            Button("本地网络权限") { openPrivacy("Privacy_LocalNetwork") }
        }
        if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
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
                guard url.resolvingSymlinksInPath().standardizedFileURL == kind.expectedURL.resolvingSymlinksInPath().standardizedFileURL else {
                    message = "请选择\(kind.title)，备份与截图位置保持不变。"; return
                }
                try FolderAccessStore().save(url, for: kind)
                saved.insert(kind)
                message = "已保存\(kind.title)访问，下次无需重复选择。"
                if kind == .iCloud { CloudSyncViewModel.shared.startIfEnabled() }
            } catch { message = error.localizedDescription }
        }
    }
}

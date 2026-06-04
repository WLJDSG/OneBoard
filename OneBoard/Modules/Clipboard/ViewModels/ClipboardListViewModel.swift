import Foundation
import AppKit
import CoreGraphics
import Combine

/// 剪贴板列表 ViewModel
@MainActor
final class ClipboardListViewModel: ObservableObject {
    @Published var entries: [ClipboardEntry] = []
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var selectedEntry: ClipboardEntry?

    private let repository: ClipboardRepository
    private var maxItems: Int {
        UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.maxClipboardItems)
    }

    private var pasteboardObserver: NSObjectProtocol?

    init(repository: ClipboardRepository = ClipboardRepository()) {
        self.repository = repository

        // 监听剪贴板变化，自动刷新列表
        pasteboardObserver = NotificationCenter.default.addObserver(
            forName: PasteboardMonitor.didDetectNewContent,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.loadEntries()
            }
        }
    }

    deinit {
        if let observer = pasteboardObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 数据加载

    func loadEntries() async {
        let effectiveMax = maxItems > 0 ? maxItems : Constants.defaultMaxClipboardItems

        do {
            if searchText.isEmpty {
                entries = try await repository.fetchAll(limit: effectiveMax).filter(isSupportedEntry)
            } else {
                entries = try await repository.search(query: searchText, limit: effectiveMax).filter(isSupportedEntry)
            }
        } catch {
            print("[ClipboardListViewModel] 加载失败: \(error)")
        }
    }

    func loadMore() async {
        // 分页加载（暂不实现，后续扩展）
    }

    // MARK: - 搜索

    func performSearch() async {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            await loadEntries()
            return
        }

        isSearching = true
        defer { isSearching = false }

        do {
            entries = try await repository.search(query: searchText).filter(isSupportedEntry)
        } catch {
            print("[ClipboardListViewModel] 搜索失败: \(error)")
        }
    }

    func clearSearch() {
        searchText = ""
        Task { await loadEntries() }
    }

    // MARK: - 操作

    func togglePin(_ entry: ClipboardEntry) async {
        guard let id = entry.id else { return }
        do {
            try await repository.togglePin(id: id)
            await loadEntries()
        } catch {
            print("[ClipboardListViewModel] 置顶切换失败: \(error)")
        }
    }

    func delete(_ entry: ClipboardEntry) async {
        guard let id = entry.id else { return }
        do {
            try await repository.delete(id: id)
            await loadEntries()
        } catch {
            print("[ClipboardListViewModel] 删除失败: \(error)")
        }
    }

    func clearAll() async {
        do {
            let count = try await repository.clearAll()
            print("[ClipboardListViewModel] 已清空 \(count) 条记录")
            await loadEntries()
        } catch {
            print("[ClipboardListViewModel] 清空失败: \(error)")
        }
    }

    /// 点击条目 - 复制回剪贴板并粘贴
    func selectAndPaste(_ entry: ClipboardEntry) {
        guard isSupportedEntry(entry) else { return }

        selectedEntry = entry
        PasteboardMonitor.shared.isPasting = true

        // 1. 写入剪贴板
        writeToPasteboard(entry)

        // 2. 保存当前前台应用，关闭浮动窗口
        let previousApp = NSWorkspace.shared.frontmostApplication
        MenuBarManager.shared.closeClipboardFloatingWindow()

        // 3. 恢复前台应用 + 粘贴
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            previousApp?.activate()
            self?.simulatePaste()
            PasteboardMonitor.shared.isPasting = false
        }
    }

    // MARK: - 粘贴

    /// 将条目内容写入剪贴板（不执行粘贴操作）
    private func writeToPasteboard(_ entry: ClipboardEntry) {
        print("[ViewModel] writeToPasteboard: contentType=\(entry.contentType), plainText=\(entry.plainText?.prefix(50) ?? "nil")..., dataSize=\(entry.data.count)")

        guard let contentType = entry.contentTypeEnum else {
            print("[ViewModel] ⚠️ 无法解析 contentType: \(entry.contentType)")
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch contentType {
        case .text:
            let writeText: String
            if let text = entry.plainText, !text.isEmpty {
                writeText = text
            } else if let decoded = String(data: entry.data, encoding: .utf8), !decoded.isEmpty {
                print("[ViewModel] plainText 为空，从 data 解码: \(decoded.prefix(50))...")
                writeText = decoded
            } else {
                print("[ViewModel] ⚠️ 文本条目无内容可写入 (plainText为空, data无法解码)")
                return
            }
            pasteboard.setString(writeText, forType: NSPasteboard.PasteboardType.string)
            // 验证写入成功
            if let written = pasteboard.string(forType: .string) {
                print("[ViewModel] ✅ 已写入剪贴板(\(written.count)字符): \(written.prefix(80))")
            } else {
                print("[ViewModel] ⚠️ 写入剪贴板后读回失败!")
            }
        case .rtf:
            pasteboard.setData(entry.data, forType: NSPasteboard.PasteboardType.rtf)
            // 同时写入纯文本，确保文本编辑器也能粘贴
            if let plainText = entry.plainText, !plainText.isEmpty {
                pasteboard.setString(plainText, forType: NSPasteboard.PasteboardType.string)
            }
            print("[ViewModel] ✅ 已写入剪贴板(RTF+text): \(entry.data.count) bytes")
        case .html:
            pasteboard.setData(entry.data, forType: NSPasteboard.PasteboardType.html)
            // 同时写入纯文本，确保文本编辑器也能粘贴
            if let plainText = entry.plainText, !plainText.isEmpty {
                pasteboard.setString(plainText, forType: NSPasteboard.PasteboardType.string)
            }
            print("[ViewModel] ✅ 已写入剪贴板(HTML+text): \(entry.data.count) bytes")
        case .image:
            pasteboard.setData(entry.data, forType: NSPasteboard.PasteboardType.png)
            print("[ViewModel] ✅ 已写入剪贴板(图片): \(entry.data.count) bytes")
        case .fileURL:
            if let rawString = String(data: entry.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !rawString.isEmpty {
                // 兼容两种存储格式：直接路径 vs URL 字符串（旧数据）
                let url: URL
                if rawString.hasPrefix("file://") || rawString.hasPrefix("/.file/") {
                    // URL 字符串（含文件引用），尝试解析并标准化
                    if let parsed = URL(string: rawString) {
                        url = parsed.standardizedFileURL
                    } else {
                        url = URL(fileURLWithPath: rawString)
                    }
                } else {
                    // 直接文件路径
                    url = URL(fileURLWithPath: rawString)
                }
                // 检查文件是否存在（避免写入无效引用）
                let fileExists = FileManager.default.fileExists(atPath: url.path)
                // 写入多种格式以确保兼容性
                pasteboard.setString(url.path, forType: NSPasteboard.PasteboardType.string)  // 文件路径文本
                pasteboard.setString(url.absoluteString, forType: NSPasteboard.PasteboardType.fileURL)  // file:// URL
                // 写入实际文件引用（NSURL 对象，Finder 可识别）
                pasteboard.writeObjects([url as NSURL])
                print("[ViewModel] ✅ 已写入剪贴板(文件): \(url.path) exists: \(fileExists)")
            } else {
                print("[ViewModel] ⚠️ 文件路径解析失败")
            }
        }
    }

    private func isSupportedEntry(_ entry: ClipboardEntry) -> Bool {
        guard entry.contentTypeEnum == .fileURL else { return true }
        guard let rawString = String(data: entry.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawString.isEmpty else {
            return false
        }
        let url: URL
        if rawString.hasPrefix("file://"), let parsed = URL(string: rawString) {
            url = parsed.standardizedFileURL
        } else {
            url = URL(fileURLWithPath: rawString)
        }
        return PasteboardTypeMapper.isSupportedFileURL(url)
    }

    /// 模拟 Cmd+V 按键（需要辅助功能权限）
    private func simulatePaste() {
        // 检查辅助功能权限
        guard PermissionManager.shared.hasAccessibilityPermission else {
            print("[ViewModel] ⚠️ 缺少辅助功能权限，无法自动粘贴")
            PermissionManager.shared.promptAccessibilityPermission()
            return
        }

        let source = CGEventSource(stateID: CGEventSourceStateID.combinedSessionState)

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)  // V key
        keyDown?.flags = CGEventFlags.maskCommand
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)

        // 短暂延迟后发送 keyUp
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
            keyUp?.flags = CGEventFlags.maskCommand
            keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }

    }

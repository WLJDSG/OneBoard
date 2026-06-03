import AppKit

/// 剪贴板监控服务 - 轮询 NSPasteboard 变化，直接保存到数据库
final class PasteboardMonitor {
    static let shared = PasteboardMonitor()

    /// 剪贴板变化通知（通知 ViewModel 刷新 UI）
    static let didDetectNewContent = Notification.Name(Constants.NotificationNames.pasteboardDidChange)

    private var timer: Timer?
    private var lastChangeCount: Int = -1
    private var lastContentHash: Int = 0  // 用于去重
    private let repository = ClipboardRepository()

    /// 标记是否正在执行粘贴操作（暂停监控，避免重复记录）
    var isPasting: Bool = false

    private init() {}

    // MARK: - Start / Stop

    func start() {
        lastChangeCount = NSPasteboard.general.changeCount
        timer = Timer.scheduledTimer(
            withTimeInterval: Constants.pasteboardPollInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkPasteboard()
        }
        // 允许计时器在 Popover 打开时也运行
        if let timer = timer {
            RunLoop.current.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Polling

    private func checkPasteboard() {
        // 粘贴操作期间跳过监控，避免重复记录
        guard !isPasting else { return }

        let pasteboard = NSPasteboard.general
        let currentCount = pasteboard.changeCount

        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return }

        for item in items {
            guard let entry = extractEntry(from: item, pasteboard: pasteboard) else { continue }

            // 去重：与上一次内容比较
            let contentHash = entry.data.hashValue
            guard contentHash != lastContentHash else { continue }
            lastContentHash = contentHash

            // 直接保存到数据库
            saveEntryToDatabase(entry)
            break  // 每次轮询只处理第一个有效条目
        }
    }

    /// 直接保存条目到数据库
    private func saveEntryToDatabase(_ entry: ClipboardEntry) {
        Task {
            do {
                let id = try await repository.insert(entry)
                print("[PasteboardMonitor] 新记录已保存, id=\(id)")

                // 应用保留策略
                await repository.applyRetentionPolicy()

                // 通知 ViewModel 刷新 UI
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Self.didDetectNewContent,
                        object: self
                    )
                }
            } catch {
                print("[PasteboardMonitor] 保存失败: \(error)")
            }
        }
    }

    /// 手动将当前剪贴板内容写入历史（用于"强制记录"场景）
    func forceRecordCurrent() -> ClipboardEntry? {
        let pasteboard = NSPasteboard.general
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return nil }

        for item in items {
            if let entry = extractEntry(from: item, pasteboard: pasteboard) {
                return entry
            }
        }
        return nil
    }

    // MARK: - Data Extraction

    private func extractEntry(from item: NSPasteboardItem, pasteboard: NSPasteboard) -> ClipboardEntry? {
        guard let contentType = PasteboardTypeMapper.inferContentType(from: item) else {
            return nil
        }

        let plainText = PasteboardTypeMapper.readPlainText(from: item)
        guard let data = PasteboardTypeMapper.readRawData(from: item, contentType: contentType) else {
            return nil
        }

        // 获取来源应用
        let sourceAppBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        return ClipboardEntry(
            contentType: contentType.rawValue,
            plainText: plainText,
            data: data,
            sourceAppBundleId: sourceAppBundleId,
            createdAt: Date()
        )
    }
}
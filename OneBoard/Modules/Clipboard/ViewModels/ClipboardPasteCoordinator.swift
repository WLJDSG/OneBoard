import AppKit

@MainActor
final class ClipboardPasteCoordinator {
    private let monitor: PasteboardMonitor
    private let pasteboardWriter: (ClipboardEntry) -> Void
    private let targetAppProvider: () -> NSRunningApplication?
    private let closeClipboardWindow: () -> Void
    private let pasteAction: (NSRunningApplication?) async -> Void

    init(
        monitor: PasteboardMonitor = .shared,
        pasteboardWriter: @escaping (ClipboardEntry) -> Void,
        targetAppProvider: @escaping () -> NSRunningApplication? = { MenuBarManager.shared.targetApplicationForClipboardPaste() },
        closeClipboardWindow: @escaping () -> Void = { MenuBarManager.shared.closeClipboardFloatingWindow() },
        pasteAction: @escaping (NSRunningApplication?) async -> Void
    ) {
        self.monitor = monitor
        self.pasteboardWriter = pasteboardWriter
        self.targetAppProvider = targetAppProvider
        self.closeClipboardWindow = closeClipboardWindow
        self.pasteAction = pasteAction
    }

    func paste(_ entry: ClipboardEntry) {
        Task { @MainActor in
            await monitor.performIgnoringChanges {
                pasteboardWriter(entry)
                let previousApp = targetAppProvider()
                closeClipboardWindow()
                try? await Task.sleep(nanoseconds: 120_000_000)
                await pasteAction(previousApp)
            }
        }
    }
}

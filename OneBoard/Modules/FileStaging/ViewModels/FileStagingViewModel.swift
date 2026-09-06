import Foundation
import AppKit
import SwiftUI

/// 刘海面板允许贴到物理屏幕顶边，不受菜单栏可用区域约束。
private final class NotchShelfPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// 文件暂存 ViewModel - 统一管理悬浮窗口
@MainActor
final class FileStagingViewModel: ObservableObject {
    static let shared = FileStagingViewModel()

    @Published var stagedFiles: [StagedFile] = []
    @Published var isShelfVisible: Bool = false
    @Published var sharingError: String?

    private let repository = FileStagingRepository()
    private var floatingWindow: NSPanel?
    private var notchTimer: Timer?
    private var outsideSince: Date?
    private var sharingService: NSSharingService?
    private var shakeObserver: NSObjectProtocol?
    private var pendingFilePaths: Set<String> = []  // 正在处理的文件路径，防止重复添加

    static let shelfSize = CGSize(width: 348, height: 434)

    private init() {
        notchTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNotchPointer() }
        }
        shakeObserver = NotificationCenter.default.addObserver(
            forName: DragDetector.fileDragDetected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showFloatingShelf()
            }
        }
    }

    deinit {
        if let observer = shakeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 数据

    private func checkNotchPointer() {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return }
        let hotspot = CGRect(x: screen.frame.midX - 110, y: screen.frame.maxY - 8, width: 220, height: 8)
        if hotspot.contains(point) { outsideSince = nil; showFloatingShelf(); return }
        guard isShelfVisible else { return }
        if floatingWindow?.frame.contains(point) == true || NSEvent.pressedMouseButtons != 0 { outsideSince = nil; return }
        if let since = outsideSince, Date().timeIntervalSince(since) > 0.65 { hideFloatingShelf() }
        else if outsideSince == nil { outsideSince = Date() }
    }

    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty else { sharingError = "请先拖入需要投送的文件"; return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            sharingError = "隔空投送暂不可用，请检查无线网络、蓝牙及文件是否存在"
            return
        }
        sharingError = nil
        sharingService = service
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    func reloadFiles() async {
        do {
            stagedFiles = try await repository.fetchAll()
        } catch {
            print("[FileStaging] 加载失败: \(error)")
        }
    }

    func addFile(url: URL) {
        let normalizedURL = url.standardizedFileURL
        let path = normalizedURL.path

        guard !DragDetector.supportedDraggedFileURLs([normalizedURL]).isEmpty else {
            print("[FileStaging] 仅支持暂存普通文件，已忽略: \(url.lastPathComponent)")
            return
        }

        // 检查是否已在暂存列表中或正在处理中
        guard !stagedFiles.contains(where: { $0.fileURL == path }),
              !pendingFilePaths.contains(path) else {
            print("[FileStaging] 文件已存在或正在处理，跳过: \(url.lastPathComponent)")
            return
        }

        // 标记为正在处理
        pendingFilePaths.insert(path)

        do {
            let stagedFile = try StagedFile(url: normalizedURL)
            Task { [weak self] in
                guard let self else { return }
                defer { self.pendingFilePaths.remove(path) }
                do {
                    _ = try await self.repository.insert(stagedFile)
                    await self.reloadFiles()
                    print("[FileStaging] 文件已暂存: \(url.lastPathComponent)")
                } catch {
                    print("[FileStaging] 暂存失败: \(error)")
                }
            }
        } catch {
            pendingFilePaths.remove(path)
            print("[FileStaging] 暂存失败: \(error)")
        }
    }

    func removeFile(_ file: StagedFile) async {
        guard let id = file.id else { return }
        do {
            try await repository.delete(id: id)
            await reloadFiles()
        } catch {
            print("[FileStaging] 删除失败: \(error)")
        }
    }

    // MARK: - 悬浮窗口

    func toggleFloatingShelf() {
        if isShelfVisible {
            hideFloatingShelf()
        } else {
            showFloatingShelf()
        }
    }

    func showFloatingShelf() {
        guard !isShelfVisible else { return }
        isShelfVisible = true
        createFloatingWindow()
        Task { [weak self] in
            guard let self else { return }
            await self.reloadFiles()
            guard self.isShelfVisible else { return }
        }
    }

    func hideFloatingShelf() {
        floatingWindow?.close()
        floatingWindow = nil
        isShelfVisible = false
    }

    private func createFloatingWindow() {
        let hostingView = NSHostingView(
            rootView: NotchShelfView(viewModel: self)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = true

        let size = CGSize(width: 440, height: 220)

        if floatingWindow == nil {
            let panel = NotchShelfPanel(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .statusBar
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false  // shadow 由 SwiftUI 层控制
            panel.contentView = hostingView
            panel.isMovableByWindowBackground = false
            let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            if let screen { panel.setFrameOrigin(CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)) }
            panel.orderFrontRegardless()
            floatingWindow = panel
        }
    }
}

import Foundation
import AppKit
import SwiftUI

/// 刘海面板允许贴到物理屏幕顶边，不受菜单栏可用区域约束。
private final class NotchShelfPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum NotchShelfAnimationLayout {
    static let expandedSize = CGSize(width: 440, height: 250)
    static let showDuration = InterfaceMotion.revealDuration
    static let hideDuration = InterfaceMotion.dismissDuration
    static let collapsedScale = CGSize(width: 150 / expandedSize.width, height: 8 / expandedSize.height)

    /// 包含刘海下方可抵达的区域，鼠标无需进入物理摄像头遮挡区。
    static func hotspotFrame(on screenFrame: CGRect, notchHeight: CGFloat, notchWidth: CGFloat = 220, notchCenterX: CGFloat? = nil) -> CGRect {
        let height = max(24, notchHeight) + 2
        let width = notchWidth > 0 ? notchWidth : 220
        return CGRect(x: (notchCenterX ?? screenFrame.midX) - width / 2, y: screenFrame.maxY - height, width: width + 0.5, height: height + 1)
    }

    static func expandedFrame(on screenFrame: CGRect) -> CGRect {
        CGRect(
            x: screenFrame.midX - expandedSize.width / 2,
            y: screenFrame.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }


}

/// 连续悬停才展开；离开刘海和卡片后收起。时间由调用者注入，测试不依赖真实等待。
struct NotchShelfHoverState {
    enum Action { case none, show, hide }
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?
    mutating func update(now: TimeInterval, inHotspot: Bool, inShelf: Bool, visible: Bool, sharing: Bool, draggingFile: Bool = false) -> Action {
        if draggingFile {
            enteredAt = nil
            exitedAt = nil
            return visible ? .none : .show
        }
        if visible {
            enteredAt = nil
            if inHotspot || inShelf || sharing { exitedAt = nil; return .none }
            if exitedAt == nil { exitedAt = now }
            return now - (exitedAt ?? now) >= 0.15 ? .hide : .none
        }
        exitedAt = nil
        guard inHotspot else { enteredAt = nil; return .none }
        if enteredAt == nil { enteredAt = now }
        if now - (enteredAt ?? now) >= 0.5 { enteredAt = nil; return .show }
        return .none
    }
}

/// 文件暂存 ViewModel - 统一管理悬浮窗口
@MainActor
final class FileStagingViewModel: NSObject, ObservableObject {
    static let shared = FileStagingViewModel()

    @Published var stagedFiles: [StagedFile] = []
    @Published var isShelfVisible: Bool = false
    @Published private(set) var isShelfExpanded = false
    @Published var sharingError: String?
    @Published var stagingError: String?

    private let repository = FileStagingRepository()
    private var floatingWindow: NSPanel?
    private var notchTimer: Timer?
    private var hoverState = NotchShelfHoverState()
    private var sharingService: NSSharingService?
    private var animationGeneration = 0
    private var isSharing = false
    private var shakeObserver: NSObjectProtocol?
    private var pendingFilePaths: Set<String> = []  // 正在处理的文件路径，防止重复添加

    static let shelfSize = CGSize(width: 348, height: 434)
    nonisolated static let notchShelfSize = NotchShelfAnimationLayout.expandedSize

    private override init() {
        super.init()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkNotchPointer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        notchTimer = timer
        shakeObserver = NotificationCenter.default.addObserver(
            forName: DragDetector.fileDragDetected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard DragDetector.shared.isFileDragActive else { return }
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
        guard let screen = NSScreen.screens.first(where: {
            point.x >= $0.frame.minX && point.x <= $0.frame.maxX && point.y >= $0.frame.minY && point.y <= $0.frame.maxY
        }) else { return }
        let notchWidth = screen.auxiliaryTopRightArea.flatMap { right in
            screen.auxiliaryTopLeftArea.map { right.minX - $0.maxX }
        } ?? 220
        let hotspot = NotchShelfAnimationLayout.hotspotFrame(on: screen.frame,
            notchHeight: screen.safeAreaInsets.top, notchWidth: notchWidth,
            notchCenterX: screen.auxiliaryTopLeftArea.map { $0.maxX + notchWidth / 2 })
        let action = hoverState.update(now: Date.timeIntervalSinceReferenceDate,
            inHotspot: hotspot.contains(point), inShelf: floatingWindow?.frame.contains(point) == true,
            visible: isShelfVisible, sharing: isSharing, draggingFile: DragDetector.shared.isFileDragActive)
        switch action {
        case .show: showFloatingShelf()
        case .hide: hideFloatingShelf()
        case .none: break
        }
    }

    func airDrop(_ urls: [URL]) {
        let validURLs = DragDetector.supportedDraggedFileURLs(urls)
        guard !validURLs.isEmpty else { sharingError = "请先拖入需要投送的文件"; return }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: validURLs) else {
            sharingError = "隔空投送暂不可用，请检查无线网络、蓝牙及文件是否存在"
            return
        }
        sharingError = nil
        isSharing = true
        sharingService = service
        service.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: validURLs)
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

        do {
            guard normalizedURL.isFileURL, normalizedURL.pathExtension.lowercased() != "app",
                  try normalizedURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                stagingError = "无法暂存“\(url.lastPathComponent)”：请选择普通文件"
                return
            }
        } catch {
            stagingError = "暂存失败：\(error.localizedDescription)"
            PermissionManager.shared.handleFileAccessError(error)
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
                    self.stagingError = "暂存失败：\(error.localizedDescription)"
                    print("[FileStaging] 暂存失败: \(error)")
                }
            }
        } catch {
            pendingFilePaths.remove(path)
            PermissionManager.shared.handleFileAccessError(error)
            stagingError = "暂存失败：\(error.localizedDescription)"
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
        animationGeneration += 1
        isShelfVisible = true
        isShelfExpanded = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        floatingWindow?.close()
        floatingWindow = nil
        createFloatingWindow()
        Task { [weak self] in
            guard let self else { return }
            await self.reloadFiles()
            guard self.isShelfVisible else { return }
        }
    }

    func hideFloatingShelf() {
        isShelfVisible = false
        hoverState = NotchShelfHoverState()
        animationGeneration += 1
        let generation = animationGeneration
        guard let panel = floatingWindow else {
            floatingWindow = nil
            return
        }
        let duration = InterfaceMotion.panelDuration(presenting: false, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        withAnimation(duration == 0 ? nil : .timingCurve(0.3, 0, 0.8, 0.15, duration: duration)) {
            isShelfExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak panel] in
            guard let self, self.animationGeneration == generation else { return }
            panel?.close()
            self.floatingWindow = nil
        }
    }

    private func createFloatingWindow() {
        let hostingView = FileShelfHostingView(
            rootView: NotchShelfView(viewModel: self, animatesPresentation: true)
        )
        hostingView.receiveFiles = { [weak self] urls in urls.forEach { self?.addFile(url: $0) } }
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.masksToBounds = true

        let size = Self.notchShelfSize

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
            panel.animationBehavior = .none  // 禁止系统出场缩放叠加，顶边只由内容动画控制。
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false  // shadow 由 SwiftUI 层控制
            panel.contentView = hostingView
            panel.isMovableByWindowBackground = false
            let point = NSEvent.mouseLocation
            let screen = NSScreen.screens.first {
                point.x >= $0.frame.minX && point.x <= $0.frame.maxX && point.y >= $0.frame.minY && point.y <= $0.frame.maxY
            } ?? NSScreen.main
            guard let screen else { return }
            // 原生窗口始终贴住顶边；仅缩放内容，避免窗口逐帧取整产生顶部闪缝。
            panel.setFrame(NotchShelfAnimationLayout.expandedFrame(on: screen.frame), display: false)
            panel.alphaValue = 1
            hostingView.layoutSubtreeIfNeeded()
            hostingView.displayIfNeeded()
            panel.orderFrontRegardless()
            floatingWindow = panel
            let generation = animationGeneration
            DispatchQueue.main.async { [weak self] in
                guard let self, self.animationGeneration == generation, self.isShelfVisible else { return }
                let duration = InterfaceMotion.panelDuration(presenting: true, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
                withAnimation(duration == 0 ? nil : .timingCurve(0.05, 0.7, 0.1, 1, duration: duration)) {
                    self.isShelfExpanded = true
                }
            }
        }
    }
}

extension FileStagingViewModel: NSSharingServiceDelegate {
    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor [weak self] in self?.finishSharing() }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        Task { @MainActor [weak self] in
            self?.sharingError = "隔空投送失败：\(error.localizedDescription)"
            self?.finishSharing()
        }
    }

    private func finishSharing() {
        isSharing = false
        sharingService = nil
        hoverState = NotchShelfHoverState()
    }
}

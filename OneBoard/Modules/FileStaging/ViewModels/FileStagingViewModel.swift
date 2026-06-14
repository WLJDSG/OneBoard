import Foundation
import AppKit
import SwiftUI

/// 文件暂存 ViewModel - 统一管理悬浮窗口
@MainActor
final class FileStagingViewModel: ObservableObject {
    static let shared = FileStagingViewModel()

    @Published var stagedFiles: [StagedFile] = []
    @Published var isShelfVisible: Bool = false

    private let repository = FileStagingRepository()
    private var floatingWindow: NSPanel?
    private var shakeObserver: NSObjectProtocol?
    private var pendingFilePaths: Set<String> = []  // 正在处理的文件路径，防止重复添加

    private init() {
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
                    if self.isShelfVisible {
                        self.updateFloatingWindow()
                    }
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
            if isShelfVisible {
                updateFloatingWindow()
            }
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
        Task { [weak self] in
            guard let self else { return }
            await self.reloadFiles()
            guard self.isShelfVisible else { return }
            self.createFloatingWindow()
        }
    }

    func hideFloatingShelf() {
        floatingWindow?.close()
        floatingWindow = nil
        isShelfVisible = false
    }

    private func createFloatingWindow() {
        updateFloatingWindow()
    }

    private func updateFloatingWindow() {
        let hostingView = NSHostingView(
            rootView: FileStagingView(
                viewModel: self,
                onClose: { [weak self] in
                    self?.hideFloatingShelf()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = 24
        hostingView.layer?.masksToBounds = true

        let width: CGFloat = 348
        let rows = max(1, Int(ceil(Double(max(stagedFiles.count, 1)) / 3.0)))
        let height = stagedFiles.isEmpty ? CGFloat(192) : min(CGFloat(rows) * 126 + 64, 434)

        if let existingWindow = floatingWindow {
            existingWindow.contentView = hostingView
            var frame = existingWindow.frame
            let topRight = NSPoint(x: frame.maxX, y: frame.maxY)
            frame.size.width = width
            frame.size.height = height
            frame.origin.x = topRight.x - width
            frame.origin.y = topRight.y - height
            existingWindow.setFrame(frame, display: true, animate: false)
        } else {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                styleMask: [.nonactivatingPanel, .borderless],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false  // shadow 由 SwiftUI 层控制
            panel.contentView = hostingView
            panel.isMovableByWindowBackground = false
            FloatingWindowManager.positionAtTopRight(panel)
            panel.makeKeyAndOrderFront(nil)
            floatingWindow = panel
        }
    }
}

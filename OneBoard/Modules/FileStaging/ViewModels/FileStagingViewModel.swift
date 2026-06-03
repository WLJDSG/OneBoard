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

    private init() {
        shakeObserver = NotificationCenter.default.addObserver(
            forName: DragDetector.shakeGestureDetected,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.showFloatingShelf()
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
        do {
            let stagedFile = try StagedFile(url: url)
            Task {
                try? await repository.insert(stagedFile)
                await reloadFiles()
                print("[FileStaging] 文件已暂存: \(url.lastPathComponent)")
            }
        } catch {
            print("[FileStaging] 暂存失败: \(error)")
        }
    }

    func removeFile(_ file: StagedFile) async {
        guard let id = file.id else { return }
        do {
            try await repository.delete(id: id)
            await reloadFiles()
            // 如果没有文件了，变成空状态提示
            if stagedFiles.isEmpty {
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
        Task { await reloadFiles() }
        createFloatingWindow()
        isShelfVisible = true
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

        // 计算窗口高度：空状态小，有文件时根据文件数
        let height: CGFloat = stagedFiles.isEmpty ? 120 : CGFloat(min(stagedFiles.count * 44 + 40, 300))

        if let existingWindow = floatingWindow {
            existingWindow.contentView = hostingView
            var frame = existingWindow.frame
            frame.size.height = height
            existingWindow.setFrame(frame, display: true, animate: true)
        } else {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 240, height: height),
                styleMask: [.nonactivatingPanel, .titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isFloatingPanel = true
            panel.titlebarAppearsTransparent = true
            panel.title = "暂存"
            panel.contentView = hostingView
            panel.isMovableByWindowBackground = true
            FloatingWindowManager.positionAtTopRight(panel)
            panel.makeKeyAndOrderFront(nil)
            floatingWindow = panel
        }
    }
}
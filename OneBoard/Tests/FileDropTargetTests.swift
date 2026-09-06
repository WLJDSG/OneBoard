import AppKit
import SwiftUI
import XCTest
@testable import OneBoardKit

final class FileDropTargetTests: XCTestCase {
    @MainActor
    func testNativeShelfWindowNeverResizesDuringPresentation() throws {
        let model = FileStagingViewModel.shared
        model.showFloatingShelf()
        defer { model.hideFloatingShelf() }
        let window = try XCTUnwrap(NSApp.windows.first { $0.contentView is FileShelfHostingView<NotchShelfView> })
        let screen = try XCTUnwrap(window.screen)
        let frame = NotchShelfAnimationLayout.expandedFrame(on: screen.frame)
        XCTAssertEqual(window.animationBehavior, .none, "系统出场动画不能叠加到自定义顶部缩放")
        XCTAssertEqual(window.frame, frame, "第一帧原生窗口即贴满最终范围，不能从小窗口开始放大")
        XCTAssertEqual(window.alphaValue, 1)
        model.hideFloatingShelf()
        XCTAssertEqual(window.frame, frame, "收起只缩放内容，原生窗口顶边保持不动")
    }

    func testFileDragOpensAndKeepsShelfVisibleUntilRelease() {
        var state = NotchShelfHoverState()
        XCTAssertEqual(state.update(now: 0, inHotspot: false, inShelf: false, visible: false, sharing: false, draggingFile: true), .show)
        for time in [0.2, 1.0, 5.0] {
            XCTAssertEqual(state.update(now: time, inHotspot: false, inShelf: false, visible: true, sharing: false, draggingFile: true), .none)
        }
        XCTAssertEqual(state.update(now: 6, inHotspot: false, inShelf: false, visible: true, sharing: false), .none)
        XCTAssertEqual(state.update(now: 6.16, inHotspot: false, inShelf: false, visible: true, sharing: false), .hide)
        // 没有文件会话的普通鼠标拖动不能自动打开。
        XCTAssertEqual(state.update(now: 7, inHotspot: false, inShelf: false, visible: false, sharing: false), .none)
    }

    func testHotspotIncludesAreaBelowPhysicalNotchOnEachScreen() {
        for screen in [CGRect(x: 0, y: 0, width: 1710, height: 1112), CGRect(x: -1512, y: 100, width: 1512, height: 982)] {
            let rect = NotchShelfAnimationLayout.hotspotFrame(on: screen, notchHeight: 38, notchWidth: 240)
            XCTAssertTrue(rect.contains(CGPoint(x: screen.midX, y: screen.maxY - 39)))
            XCTAssertFalse(rect.contains(CGPoint(x: screen.midX, y: screen.maxY - 41)))
            XCTAssertTrue(rect.contains(CGPoint(x: screen.midX + 119, y: screen.maxY - 39)))
            XCTAssertTrue(rect.contains(CGPoint(x: screen.midX - 120, y: screen.maxY)))
            XCTAssertTrue(rect.contains(CGPoint(x: screen.midX + 120, y: screen.maxY)))
            XCTAssertTrue(rect.contains(CGPoint(x: screen.midX, y: screen.maxY)))
            XCTAssertFalse(rect.contains(CGPoint(x: screen.midX, y: screen.maxY - 60)))
            XCTAssertFalse(rect.contains(CGPoint(x: screen.midX + 121, y: screen.maxY - 39)))
        }
    }

    func testNotchRequiresContinuousHalfSecondAndClosesOnExit() {
        var state = NotchShelfHoverState()
        XCTAssertEqual(state.update(now: 0, inHotspot: true, inShelf: false, visible: false, sharing: false), .none)
        XCTAssertEqual(state.update(now: 0.49, inHotspot: true, inShelf: false, visible: false, sharing: false), .none)
        XCTAssertEqual(state.update(now: 0.5, inHotspot: true, inShelf: false, visible: false, sharing: false), .show)
        XCTAssertEqual(state.update(now: 0.6, inHotspot: false, inShelf: true, visible: true, sharing: false), .none)
        XCTAssertEqual(state.update(now: 1, inHotspot: false, inShelf: false, visible: true, sharing: false), .none)
        XCTAssertEqual(state.update(now: 1.16, inHotspot: false, inShelf: false, visible: true, sharing: false), .hide)
        state = NotchShelfHoverState()
        _ = state.update(now: 0, inHotspot: true, inShelf: false, visible: false, sharing: false)
        _ = state.update(now: 0.3, inHotspot: false, inShelf: false, visible: false, sharing: false)
        XCTAssertEqual(state.update(now: 0.6, inHotspot: true, inShelf: false, visible: false, sharing: false), .none)
        XCTAssertEqual(state.update(now: 1, inHotspot: true, inShelf: false, visible: false, sharing: false), .none)
        XCTAssertEqual(state.update(now: 1.11, inHotspot: true, inShelf: false, visible: false, sharing: false), .show)
        XCTAssertEqual(state.update(now: 2, inHotspot: false, inShelf: false, visible: true, sharing: true), .none)
    }

    @MainActor
    func testDraggingOutProvidesFinderFileURLAndNativeHitTarget() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        try Data("staging regression".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = FileDragSource.Source.draggingItem(url: url, at: .zero)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.writeObjects([try XCTUnwrap(item.item as? NSURL)]))
        XCTAssertEqual(FileDropTarget.Destination.urls(board), [url])
        let host = FileShelfHostingView(rootView: Text("文件").frame(width: 120, height: 40)
            .overlay(FileDragSource(url: url)))
        host.frame = CGRect(x: 0, y: 0, width: 120, height: 40)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(host.hitTest(CGPoint(x: 60, y: 20)) is FileDragSource.Source)
    }

    @MainActor
    func testShelfDropZonesHaveUsableNativeHitTargets() throws {
        let host = FileShelfHostingView(rootView: NotchShelfView(viewModel: .shared))
        let container = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
        container.addSubview(host)
        host.frame = CGRect(x: 0, y: 0, width: 440, height: 250)
        host.layoutSubtreeIfNeeded()
        func destinations(_ view: NSView) -> [FileDropTarget.Destination] {
            (view as? FileDropTarget.Destination).map { [$0] } ?? view.subviews.flatMap(destinations)
        }
        let targets = destinations(host)
        XCTAssertEqual(targets.count, 2)
        for target in targets {
            XCTAssertGreaterThan(target.bounds.width, 110)
            XCTAssertGreaterThan(target.bounds.height, 40)
            let center = target.convert(CGPoint(x: target.bounds.midX, y: target.bounds.midY), to: container)
            XCTAssertTrue(host.hitTest(center) === target, "Drop zone must hit its native receiver; got \(String(describing: host.hitTest(center)))")
        }
    }

    @MainActor
    func testNativeFinderFileURLsAndPlainTextRejection() throws {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = [directory.appendingPathComponent("文件 A.png"), directory.appendingPathComponent("B.pdf")]
        for url in urls { try Data().write(to: url) }
        let items = urls.map { url -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(url.absoluteString, forType: .fileURL)
            return item
        }
        XCTAssertEqual(FileDropTarget.Destination.urls(from: items), urls)
        board.clearContents()
        board.setString("/tmp/not-a-file-drag", forType: .string)
        XCTAssertTrue(FileDropTarget.Destination.urls(board).isEmpty)
    }

    @MainActor
    func testFinderLegacyFilenamePayloadIsAccepted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = [directory.appendingPathComponent("文件 A.png").path, directory.appendingPathComponent("B.pdf").path]
        for path in paths { try Data().write(to: URL(fileURLWithPath: path)) }
        XCTAssertEqual(FileDropTarget.Destination.urls(fromLegacyPropertyList: paths).map(\.path), paths)
    }

    func testNotchShelfFrameAlignsWithScreenTopCenter() {
        let screen = CGRect(x: 100, y: 50, width: 1512, height: 982)
        let expanded = NotchShelfAnimationLayout.expandedFrame(on: screen)

        XCTAssertEqual(expanded.size, FileStagingViewModel.notchShelfSize)
        XCTAssertEqual(expanded.midX, screen.midX)
        XCTAssertEqual(expanded.maxY, screen.maxY)
        XCTAssertGreaterThan(NotchShelfAnimationLayout.showDuration, 0)
        XCTAssertGreaterThan(NotchShelfAnimationLayout.hideDuration, 0)
    }
}

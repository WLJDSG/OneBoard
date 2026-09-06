import AppKit
import XCTest
import SwiftUI
@testable import OneBoardKit

final class MenuCalendarInteractionTests: XCTestCase {
    @MainActor
    func testHoverCrossingPinAndClickSuppression() throws {
        let anchorWindow = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 30, height: 24), styleMask: .borderless, backing: .buffered, defer: false)
        let anchor = NSView(frame: CGRect(x: 0, y: 0, width: 30, height: 24))
        anchorWindow.contentView = anchor
        let card = HoverCardController(title: "Test card", size: CGSize(width: 100, height: 100)) { AnyView(Text("Test")) }
        card.attach(to: anchor)
        let now = Date()
        card.updatePointer(CGPoint(x: 110, y: 110), now: now)
        XCTAssertNil(card.panel, "经过图标不应立即打开")
        card.updatePointer(CGPoint(x: 110, y: 110), now: now.addingTimeInterval(0.69))
        XCTAssertNil(card.panel)
        card.updatePointer(CGPoint(x: 110, y: 110), now: now.addingTimeInterval(0.71))
        let panel = try XCTUnwrap(card.panel)
        XCTAssertTrue(panel.isVisible)
        let outside = CGPoint(x: -10_000, y: -10_000)
        card.updatePointer(outside, now: now)
        card.updatePointer(CGPoint(x: panel.frame.midX, y: panel.frame.midY), now: now.addingTimeInterval(0.2))
        XCTAssertTrue(panel.isVisible)
        card.setPinned(true)
        card.updatePointer(outside, now: now.addingTimeInterval(2))
        XCTAssertTrue(panel.isVisible)
        card.toggle()
        XCTAssertFalse(panel.isVisible)
        card.updatePointer(CGPoint(x: 110, y: 110), now: now.addingTimeInterval(3))
        XCTAssertFalse(panel.isVisible)
        card.updatePointer(outside, now: now.addingTimeInterval(4))
        card.updatePointer(CGPoint(x: 110, y: 110), now: now.addingTimeInterval(5))
        XCTAssertFalse(panel.isVisible)
        card.updatePointer(CGPoint(x: 110, y: 110), now: now.addingTimeInterval(5.71))
        XCTAssertTrue(panel.isVisible)
        card.setPinned(false)
        card.updatePointer(outside, now: now.addingTimeInterval(6))
        card.updatePointer(outside, now: now.addingTimeInterval(7))
        XCTAssertFalse(panel.isVisible)
    }
    @MainActor
    func testCalendarIsBorderlessAndSecondClickCloses() throws {
        let manager = CalendarPanelWindowManager.shared
        manager.show()
        let window = try XCTUnwrap(NSApp.windows.first { $0.title == "日历" && $0.isVisible })
        XCTAssertFalse(window.styleMask.contains(.titled))
        XCTAssertFalse(window.styleMask.contains(.closable))
        manager.setPinned(true)
        XCTAssertGreaterThanOrEqual(window.level.rawValue, NSWindow.Level.floating.rawValue)
        manager.show()
        XCTAssertFalse(window.isVisible)
        window.orderOut(nil)
    }
}

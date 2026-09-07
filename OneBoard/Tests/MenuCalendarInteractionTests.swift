import AppKit
import XCTest
import SwiftUI
@testable import OneBoardKit

final class MenuCalendarInteractionTests: XCTestCase {
    @MainActor
    func testDisablingStatusIconsKeepsOtherAnchorAndClearsDisabledAnchor() async throws {
        let defaults = UserDefaults.standard
        let calendarKey = Constants.UserDefaultsKeys.calendarShowInMenuBar
        let statusKey = Constants.UserDefaultsKeys.macStatusShowInMenuBar
        let savedCalendar = defaults.object(forKey: calendarKey)
        let savedStatus = defaults.object(forKey: statusKey)
        let manager = MenuBarManager.shared
        let calendarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer {
            defaults.set(false, forKey: calendarKey)
            defaults.set(false, forKey: statusKey)
            manager.updateCalendarStatusItemVisibility()
            manager.updateMacStatusItemVisibility()
            NSStatusBar.system.removeStatusItem(calendarItem)
            NSStatusBar.system.removeStatusItem(statusItem)
            defaults.set(savedCalendar, forKey: calendarKey)
            defaults.set(savedStatus, forKey: statusKey)
        }
        defaults.set(true, forKey: calendarKey)
        defaults.set(true, forKey: statusKey)
        manager.configureAuxiliaryStatusItems(calendar: calendarItem, macStatus: statusItem)
        await Task.yield()
        let calendar = CalendarPanelWindowManager.shared.card
        let status = MacStatusWindowManager.shared.card
        let calendarAnchor = try XCTUnwrap(calendar.anchor)
        let statusAnchor = try XCTUnwrap(status.anchor)
        XCTAssertFalse(calendarAnchor === statusAnchor)
        defaults.set(false, forKey: calendarKey)
        manager.updateCalendarStatusItemVisibility()
        await Task.yield()
        XCTAssertFalse(calendarItem.isVisible)
        XCTAssertTrue(statusItem.isVisible)
        XCTAssertNil(calendar.anchor, "移除日历图标必须解除旧按钮监听，防止菜单栏重排后误触发")
        XCTAssertTrue(status.anchor === statusAnchor)
        XCTAssertTrue(defaults.bool(forKey: statusKey))
        defaults.set(true, forKey: calendarKey)
        manager.updateCalendarStatusItemVisibility()
        await Task.yield()
        let replacement = try XCTUnwrap(calendar.anchor)
        defaults.set(false, forKey: statusKey)
        manager.updateMacStatusItemVisibility()
        await Task.yield()
        XCTAssertFalse(statusItem.isVisible)
        XCTAssertTrue(calendarItem.isVisible)
        XCTAssertNil(status.anchor)
        XCTAssertTrue(calendar.anchor === replacement)
        XCTAssertTrue(defaults.bool(forKey: calendarKey))
        // 同一主线程周期内快速开关，不能在异步任务恢复时重新绑定已移除按钮。
        for _ in 0..<5 {
            defaults.set(true, forKey: statusKey)
            manager.updateMacStatusItemVisibility()
            defaults.set(false, forKey: statusKey)
            manager.updateMacStatusItemVisibility()
        }
        await Task.yield()
        XCTAssertFalse(statusItem.isVisible)
        XCTAssertTrue(calendarItem.isVisible)
        XCTAssertNil(status.anchor)
        XCTAssertTrue(calendar.anchor === replacement)
    }

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

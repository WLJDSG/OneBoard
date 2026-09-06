import AppKit
import SwiftUI

@MainActor
final class CalendarPanelWindowManager {
    static let shared = CalendarPanelWindowManager()
    let card = HoverCardController(title: "日历", size: CGSize(width: 960, height: 590)) { AnyView(CalendarPanelView()) }
    func show() { card.toggle() }
    func attach(to view: NSView) { card.attach(to: view) }
    func setPinned(_ pinned: Bool) { card.setPinned(pinned) }
}

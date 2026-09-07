import AppKit
import SwiftUI

/// 滚轮每次一月；触控板每个手势一月，惯性事件不继续翻页。
struct CalendarMonthScrollState {
    private var accumulated: CGFloat = 0
    private var didMove = false
    private var lastTimestamp: TimeInterval = -.infinity

    mutating func monthOffset(deltaX: CGFloat, deltaY: CGFloat, precise: Bool,
                              phase: NSEvent.Phase, momentum: NSEvent.Phase,
                              timestamp: TimeInterval) -> Int? {
        guard momentum.isEmpty else { return nil }
        if phase.contains(.began) || (phase.isEmpty && timestamp - lastTimestamp > 0.25) {
            accumulated = 0
            didMove = false
        }
        lastTimestamp = timestamp
        if phase.contains(.ended) || phase.contains(.cancelled) { return nil }
        guard abs(deltaY) > abs(deltaX), deltaY != 0 else { return nil }
        if !precise { return deltaY > 0 ? -1 : 1 }
        guard !didMove else { return nil }
        accumulated += deltaY
        guard abs(accumulated) >= 12 else { return nil }
        didMove = true
        return accumulated > 0 ? -1 : 1
    }
}

struct CalendarMonthScrollView: NSViewRepresentable {
    let onMove: (Int) -> Void
    func makeNSView(context: Context) -> ScrollRegion { ScrollRegion(onMove: onMove) }
    func updateNSView(_ view: ScrollRegion, context: Context) { view.onMove = onMove }

    final class ScrollRegion: NSView {
        var onMove: (Int) -> Void
        private var monitor: Any?
        private var state = CalendarMonthScrollState()
        init(onMove: @escaping (Int) -> Void) {
            self.onMove = onMove
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { fatalError() }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            state = CalendarMonthScrollState()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window,
                      self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                if let offset = self.state.monthOffset(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                                      precise: event.hasPreciseScrollingDeltas, phase: event.phase,
                                                      momentum: event.momentumPhase, timestamp: event.timestamp) {
                    self.onMove(offset)
                }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

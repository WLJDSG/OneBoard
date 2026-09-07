import AppKit
import XCTest
@testable import OneBoardKit

final class CalendarMonthScrollTests: XCTestCase {
    func testWheelMovesExactlyOneMonthRegardlessOfDelta() {
        var state = CalendarMonthScrollState()
        XCTAssertEqual(state.monthOffset(deltaX: 0, deltaY: -1, precise: false, phase: [], momentum: [], timestamp: 1), 1)
        XCTAssertEqual(state.monthOffset(deltaX: 0, deltaY: -30, precise: false, phase: [], momentum: [], timestamp: 1.02), 1)
        XCTAssertEqual(state.monthOffset(deltaX: 0, deltaY: 1, precise: false, phase: [], momentum: [], timestamp: 1.04), -1)
        XCTAssertNil(state.monthOffset(deltaX: 10, deltaY: 1, precise: false, phase: [], momentum: [], timestamp: 1.06))
    }

    func testTrackpadMovesOncePerGestureAndIgnoresMomentum() {
        var state = CalendarMonthScrollState()
        XCTAssertNil(state.monthOffset(deltaX: 0, deltaY: -4, precise: true, phase: .began, momentum: [], timestamp: 1))
        XCTAssertEqual(state.monthOffset(deltaX: 0, deltaY: -10, precise: true, phase: .changed, momentum: [], timestamp: 1.01), 1)
        XCTAssertNil(state.monthOffset(deltaX: 0, deltaY: -40, precise: true, phase: .changed, momentum: [], timestamp: 1.35))
        XCTAssertNil(state.monthOffset(deltaX: 0, deltaY: -40, precise: true, phase: [], momentum: .changed, timestamp: 1.4))
        XCTAssertEqual(state.monthOffset(deltaX: 0, deltaY: 20, precise: true, phase: .began, momentum: [], timestamp: 1.5), -1)
    }
}

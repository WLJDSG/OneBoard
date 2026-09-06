import XCTest
@testable import OneBoardKit

final class MacStatusTests: XCTestCase {
    @MainActor
    func testLiveSystemSamplingReturnsRealCapacityAndHistory() async throws {
        let model = MacStatusModel()
        XCTAssertGreaterThan(model.usedMemory, 0)
        XCTAssertGreaterThan(model.totalDisk, 0)
        XCTAssertGreaterThan(model.freeDisk, 0)
        XCTAssertLessThanOrEqual(model.freeDisk, model.totalDisk)
        model.start()
        try await Task.sleep(nanoseconds: 1_200_000_000)
        model.stop()
        XCTAssertFalse(model.history.isEmpty)
        XCTAssertTrue((0...1).contains(model.cpu))
        XCTAssertTrue((0...1).contains(model.memory))
    }
}

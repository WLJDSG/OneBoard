import XCTest
@testable import OneBoardKit

final class MacStatusTests: XCTestCase {
    func testDiskCapacityUsesDecimalUnits() {
        XCTAssertEqual(MacStatusView.diskBytes(494_384_795_648), ByteCountFormatter.string(fromByteCount: 494_384_795_648, countStyle: .file))
        XCTAssertEqual(MacStatusView.diskBytes(216_584_196_096), ByteCountFormatter.string(fromByteCount: 216_584_196_096, countStyle: .file))
    }

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

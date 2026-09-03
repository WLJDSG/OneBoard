import XCTest
@testable import OneBoardKit

@MainActor
final class CodexAccountEditorViewModelTests: XCTestCase {
    func testValidatedTitleTrimsWhitespace() throws {
        let viewModel = CodexAccountEditorViewModel()
        viewModel.title = "  工作账号  "

        XCTAssertEqual(try viewModel.validatedTitle(), "工作账号")
    }

    func testValidatedTitleRejectsBlankValue() {
        let viewModel = CodexAccountEditorViewModel()
        viewModel.title = "   "

        XCTAssertThrowsError(try viewModel.validatedTitle()) { error in
            XCTAssertEqual(error as? CodexAccountError, .invalidTitle)
        }
    }
}

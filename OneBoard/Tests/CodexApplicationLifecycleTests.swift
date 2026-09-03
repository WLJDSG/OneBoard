import Darwin
import XCTest
@testable import OneBoardKit

@MainActor
final class CodexApplicationLifecycleTests: XCTestCase {
    func testParserCapturesOnlyDirectCodexAppServerChildren() {
        let processList = """
          101     1 /Applications/ChatGPT.app/Contents/MacOS/ChatGPT
          202   101 /Applications/ChatGPT.app/Contents/Resources/codex app-server
          203   101 /Applications/ChatGPT.app/Contents/Frameworks/ChatGPT Helper.app/Contents/MacOS/ChatGPT Helper
          204   999 /Applications/ChatGPT.app/Contents/Resources/codex app-server
          205   101 /usr/local/bin/unrelated app-server
        """

        let result = SystemCodexApplicationLifecycleController.parseDirectAppServerChildren(
            processList,
            rootPIDs: [101]
        )

        XCTAssertEqual(result, [202])
    }
}

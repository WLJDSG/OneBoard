import XCTest
@testable import OneBoardKit

final class SensitiveOperationAuthorizerTests: XCTestCase {
    func testUnavailableErrorExplainsBiometricAndPasswordFallback() {
        let error = SensitiveOperationAuthorizationError.unavailable("策略不可用")

        XCTAssertEqual(
            error.errorDescription,
            "无法使用 Touch ID 或登录密码验证身份：策略不可用"
        )
    }

    func testFailedErrorPreservesSystemFailureReason() {
        let error = SensitiveOperationAuthorizationError.failed("用户取消")

        XCTAssertEqual(error.errorDescription, "身份验证未通过：用户取消")
    }
}

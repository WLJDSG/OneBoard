import Foundation
import LocalAuthentication

protocol SensitiveOperationAuthorizing: Sendable {
    func authorize(reason: String) async throws
}

struct SensitiveOperationAuthorizer: SensitiveOperationAuthorizing {
    func authorize(reason: String) async throws {
        let context = LAContext()
        context.localizedCancelTitle = "取消"

        var evaluationError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &evaluationError) else {
            throw SensitiveOperationAuthorizationError.unavailable(
                evaluationError?.localizedDescription ?? "此 Mac 无法验证当前用户身份"
            )
        }

        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw SensitiveOperationAuthorizationError.failed(error.localizedDescription)
        }
    }
}

enum SensitiveOperationAuthorizationError: LocalizedError, Equatable, Sendable {
    case unavailable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message):
            return "无法使用 Touch ID 或登录密码验证身份：\(message)"
        case .failed(let message):
            return "身份验证未通过：\(message)"
        }
    }
}

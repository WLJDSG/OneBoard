@testable import OneBoardKit

final class RecordingGatewayCommandRunner: GatewayCommandRunning {
    var commands: [String] = []

    func run(_ launchPath: String, arguments: [String]) throws -> GatewayCommandResult {
        commands.append(([launchPath] + arguments).joined(separator: " "))
        return GatewayCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)
    }
}

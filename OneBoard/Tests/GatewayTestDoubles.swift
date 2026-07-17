@testable import OneBoardKit

final class RecordingGatewayCommandRunner: GatewayCommandRunning {
    var commands: [String] = []
    private var results: [GatewayCommandResult]

    init(results: [GatewayCommandResult] = []) {
        self.results = results
    }

    func run(_ launchPath: String, arguments: [String]) throws -> GatewayCommandResult {
        commands.append(([launchPath] + arguments).joined(separator: " "))
        if !results.isEmpty {
            return results.removeFirst()
        }
        return GatewayCommandResult(standardOutput: "", standardError: "", terminationStatus: 0)
    }
}

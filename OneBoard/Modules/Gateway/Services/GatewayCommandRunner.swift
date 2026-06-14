import Foundation

struct GatewayCommandResult: Equatable, Sendable {
    var standardOutput: String
    var standardError: String
    var terminationStatus: Int32
}

protocol GatewayCommandRunning {
    func run(_ launchPath: String, arguments: [String]) throws -> GatewayCommandResult
}

struct ProcessGatewayCommandRunner: GatewayCommandRunning {
    func run(_ launchPath: String, arguments: [String]) throws -> GatewayCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderr.fileHandleForReading.readDataToEndOfFile()

        return GatewayCommandResult(
            standardOutput: String(data: outputData, encoding: .utf8) ?? "",
            standardError: String(data: errorData, encoding: .utf8) ?? "",
            terminationStatus: process.terminationStatus
        )
    }
}

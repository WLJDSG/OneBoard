import AppKit
import Darwin
import Foundation

@MainActor
protocol CodexApplicationLifecycleControlling {
    var isRunning: Bool { get }
    func closeAndWait() async throws
    func launch() async throws
}

@MainActor
final class SystemCodexApplicationLifecycleController: CodexApplicationLifecycleControlling {
    private let gracefulWaitNanoseconds: UInt64 = 2_000_000_000
    private let totalWaitNanoseconds: UInt64 = 20_000_000_000
    private let pollNanoseconds: UInt64 = 120_000_000

    var isRunning: Bool {
        !runningApplications.isEmpty
    }

    func closeAndWait() async throws {
        let applications = runningApplications
        guard !applications.isEmpty else { return }

        let rootPIDs = applications.map(\.processIdentifier)
        let appServerPIDs = directAppServerChildren(of: Set(rootPIDs))

        for application in applications {
            _ = application.terminate()
        }

        let gracefulDeadline = DispatchTime.now().uptimeNanoseconds + gracefulWaitNanoseconds
        if await waitUntilExited(rootPIDs, deadline: gracefulDeadline) {
            try await closeCapturedAppServers(appServerPIDs)
            return
        }

        let remaining = (rootPIDs + appServerPIDs).filter(isProcessRunning)
        for pid in remaining {
            _ = Darwin.kill(pid, SIGTERM)
        }

        let finalDeadline = DispatchTime.now().uptimeNanoseconds + totalWaitNanoseconds
        guard await waitUntilExited(rootPIDs + appServerPIDs, deadline: finalDeadline) else {
            throw CodexAccountError.applicationCloseFailed
        }
    }

    func launch() async throws {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: Constants.codexDesktopBundleIdentifier
        ) else {
            throw CodexAccountError.applicationLaunchFailed
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = true
            NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { _, error in
                if error == nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CodexAccountError.applicationLaunchFailed)
                }
            }
        }
    }

    private var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: Constants.codexDesktopBundleIdentifier
        )
    }

    private func closeCapturedAppServers(_ pids: [pid_t]) async throws {
        let remaining = pids.filter(isProcessRunning)
        guard !remaining.isEmpty else { return }
        for pid in remaining {
            _ = Darwin.kill(pid, SIGTERM)
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + totalWaitNanoseconds
        guard await waitUntilExited(remaining, deadline: deadline) else {
            throw CodexAccountError.applicationCloseFailed
        }
    }

    private func waitUntilExited(_ pids: [pid_t], deadline: UInt64) async -> Bool {
        while pids.contains(where: isProcessRunning) {
            guard DispatchTime.now().uptimeNanoseconds < deadline else { return false }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return true
    }

    private func isProcessRunning(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid, 0) == 0 { return true }
        return errno != ESRCH
    }

    /// Electron 退出后子进程可能被重托管，所以必须在主进程退出前记住它们。
    private func directAppServerChildren(of rootPIDs: Set<pid_t>) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,command="]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return Self.parseDirectAppServerChildren(text, rootPIDs: rootPIDs)
    }

    static func parseDirectAppServerChildren(_ text: String, rootPIDs: Set<pid_t>) -> [pid_t] {
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 2, whereSeparator: \Character.isWhitespace)
            guard fields.count == 3,
                  let pid = pid_t(fields[0]),
                  let parentPID = pid_t(fields[1]),
                  rootPIDs.contains(parentPID) else { return nil }
            let command = fields[2].lowercased()
            guard command.contains("app-server"), command.contains("codex") else { return nil }
            return pid
        }
    }
}

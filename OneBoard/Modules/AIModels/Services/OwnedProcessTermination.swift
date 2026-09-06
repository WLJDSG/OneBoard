import Foundation
import Darwin

enum OwnedProcessTermination {
    /// 仅终止本应用创建并持有的 Process，给代理机会输出尾部计数，拒绝无限等待。
    static func stop(_ process: Process, gracePeriod: TimeInterval = 3) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(gracePeriod)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        let finalDeadline = Date().addingTimeInterval(1)
        while process.isRunning && Date() < finalDeadline { Thread.sleep(forTimeInterval: 0.01) }
    }
}

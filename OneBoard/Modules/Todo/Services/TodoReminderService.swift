import Foundation
import UserNotifications

/// 待办事项提醒服务
final class TodoReminderService {
    static let shared = TodoReminderService()
    private let center = UNUserNotificationCenter.current()

    private init() {}

    // MARK: - 权限

    /// 请求通知权限
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            print("[TodoReminderService] 通知权限请求失败: \(error)")
            return false
        }
    }

    /// 检查通知权限状态
    var hasPermission: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    // MARK: - 提醒

    /// 为待办事项调度提醒通知
    func scheduleReminder(for item: TodoItem) {
        guard let dueDate = item.dueDate, !item.isCompleted, let id = item.id else { return }

        let content = UNMutableNotificationContent()
        content.title = "待办提醒"
        content.body = item.text
        content.sound = .default
        content.userInfo = ["todoId": id]

        let triggerDate = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dueDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(
            identifier: "todo-\(id)",
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            if let error {
                print("[TodoReminderService] 调度提醒失败 #\(id): \(error)")
            }
        }
    }

    /// 取消某条待办的提醒
    func cancelReminder(for itemId: Int64) {
        center.removePendingNotificationRequests(withIdentifiers: ["todo-\(itemId)"])
    }

    /// 批量通知过期待办（启动时调用）
    func notifyOverdue(items: [TodoItem]) {
        guard !items.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.title = "过期待办"
        content.body = "有 \(items.count) 个待办事项已过期，请及时处理"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "todo-overdue-batch",
            content: content,
            trigger: nil  // 立即发送
        )
        center.add(request)
    }
}

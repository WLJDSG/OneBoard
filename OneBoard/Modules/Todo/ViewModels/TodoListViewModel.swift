import AppKit
import ApplicationServices
import Combine
import SwiftUI

/// 待办列表 ViewModel
@MainActor
final class TodoListViewModel: ObservableObject {
    static let shared = TodoListViewModel()

    @Published var activeItems: [TodoItem] = []
    @Published var recentlyCompleted: [TodoItem] = []
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
    @Published var feedbackMessage: String?
    @Published var manualAddRequestID = 0

    /// 正在淡出的条目 ID 集合
    @Published var fadingOutIds: Set<Int64> = []

    private let repository = TodoRepository()
    private var searchTask: Task<Void, Never>?

    private init() {
        Task { await loadActive() }
    }

    // MARK: - 加载

    func loadActive() async {
        do {
            activeItems = try await repository.fetchActive()
        } catch {
            print("[TodoListViewModel] 加载活跃待办失败: \(error)")
        }
    }

    func loadRecentlyCompleted() async {
        do {
            recentlyCompleted = try await repository.fetchRecentlyCompleted(limit: 20)
        } catch {
            print("[TodoListViewModel] 加载历史失败: \(error)")
        }
    }

    // MARK: - 添加

    func addTodo(
        text: String,
        sourceAppBundleId: String? = nil,
        priority: Priority = .medium,
        dueDate: Date? = nil,
        showsFeedback: Bool = false
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = TodoItem(
            text: trimmed,
            priority: priority,
            sourceAppBundleId: sourceAppBundleId,
            dueDate: dueDate
        )

        Task {
            do {
                let id = try await repository.insert(item)
                if dueDate != nil {
                    var reminderItem = item
                    reminderItem.id = id
                    TodoReminderService.shared.scheduleReminder(for: reminderItem)
                }
                await loadActive()
                if showsFeedback {
                    showFeedback("已添加到待办")
                }
                print("[TodoListViewModel] 已添加待办 #\(id): \(trimmed.prefix(30))")
            } catch {
                if showsFeedback {
                    showFeedback("添加失败：\(error.localizedDescription)")
                }
                print("[TodoListViewModel] 添加待办失败: \(error)")
            }
        }
    }

    // MARK: - 完成

    func toggleComplete(_ item: TodoItem) {
        guard let id = item.id else { return }
        if item.isCompleted {
            // 取消完成
            Task {
                do {
                    try await repository.markUncompleted(id: id)
                    await loadActive()
                } catch {
                    print("[TodoListViewModel] 取消完成失败: \(error)")
                }
            }
        } else {
            // 标记完成，淡出动画
            fadingOutIds.insert(id)
            Task {
                // 先给用户看到勾选状态，再用短动画移出列表。
                try? await Task.sleep(nanoseconds: 650_000_000)

                do {
                    try await repository.markCompleted(id: id)
                    fadingOutIds.remove(id)
                    await loadActive()
                    await loadRecentlyCompleted()
                    print("[TodoListViewModel] 已完成待办 #\(id)")
                } catch {
                    print("[TodoListViewModel] 完成待办失败: \(error)")
                    fadingOutIds.remove(id)
                }
            }
        }
    }

    // MARK: - 删除

    func delete(_ item: TodoItem) {
        guard let id = item.id else { return }
        Task {
            do {
                try await repository.delete(id: id)
                await loadActive()
                print("[TodoListViewModel] 已删除待办 #\(id)")
            } catch {
                print("[TodoListViewModel] 删除失败: \(error)")
            }
        }
    }

    // MARK: - 优先级

    func setPriority(_ item: TodoItem, priority: Priority) {
        guard let id = item.id else { return }
        Task {
            do {
                try await repository.updatePriority(id: id, priority: priority)
                await loadActive()
            } catch {
                print("[TodoListViewModel] 更新优先级失败: \(error)")
            }
        }
    }

    // MARK: - 截止日期

    func setDueDate(_ item: TodoItem, dueDate: Date?) {
        guard let id = item.id else { return }
        Task {
            do {
                try await repository.updateDueDate(id: id, dueDate: dueDate)
                await loadActive()
                // 如果设置了提醒，调度通知
                if let dueDate {
                    var updated = item
                    updated.dueDate = dueDate
                    updated.id = id
                    TodoReminderService.shared.scheduleReminder(for: updated)
                }
            } catch {
                print("[TodoListViewModel] 更新截止日期失败: \(error)")
            }
        }
    }

    // MARK: - 搜索

    func performSearch() {
        searchTask?.cancel()
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !query.isEmpty else {
            isSearching = false
            Task { await loadActive() }
            return
        }

        isSearching = true
        searchTask = Task {
            // 防抖 300ms
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }

            do {
                let results = try await repository.search(query: query)
                if !Task.isCancelled {
                    activeItems = results
                }
            } catch {
                print("[TodoListViewModel] 搜索失败: \(error)")
            }
        }
    }

    // MARK: - 获取选中文字（通过 AX API）

    func addSelectedTextFromFrontmostApp() {
        let sourceBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        Task {
            let copiedText = await SelectedTextReader.readSelectedText()
            if !copiedText.isEmpty {
                TodoSlidePanelWindowManager.shared.show()
                addTodo(text: copiedText, sourceAppBundleId: sourceBundleId, showsFeedback: true)
                return
            }

            addSelectedTextUsingAccessibility(sourceBundleId: sourceBundleId)
        }
    }

    private func addSelectedTextUsingAccessibility(sourceBundleId: String?) {
        guard PermissionManager.shared.hasAccessibilityPermission else {
            print("[TodoListViewModel] 缺少辅助功能权限，无法读取选中文字")
            TodoSlidePanelWindowManager.shared.show()
            showFeedback("需要辅助功能权限才能读取选中文字")
            PermissionManager.shared.promptAccessibilityPermission()
            return
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &focusedApp)

        guard let app = focusedApp else {
            print("[TodoListViewModel] 无法获取前台应用")
            showManualAddPrompt("未检测到前台应用，可手动输入待办")
            return
        }

        let appElement = app as! AXUIElement

        // 获取焦点元素
        var focusedElement: CFTypeRef?
        AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard let element = focusedElement else {
            print("[TodoListViewModel] 无法获取焦点元素")
            showManualAddPrompt("未检测到可读取的选中文字，可手动输入")
            return
        }

        let focusedEl = element as! AXUIElement

        // 获取选中文字
        var selectedTextValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(focusedEl, kAXSelectedTextAttribute as CFString, &selectedTextValue)

        guard result == .success, let text = selectedTextValue as? String, !text.isEmpty else {
            print("[TodoListViewModel] 未选中文字")
            showManualAddPrompt("未检测到选中文字，可手动输入待办")
            return
        }

        TodoSlidePanelWindowManager.shared.show()
        addTodo(text: text, sourceAppBundleId: sourceBundleId, showsFeedback: true)
    }

    private func showManualAddPrompt(_ message: String) {
        TodoSlidePanelWindowManager.shared.show()
        showFeedback(message)
        manualAddRequestID += 1
    }

    func showFeedback(_ message: String) {
        feedbackMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if feedbackMessage == message {
                feedbackMessage = nil
            }
        }
    }
}

import SwiftUI

/// 单条待办事项行视图
struct TodoRowView: View {
    let item: TodoItem
    let isFadingOut: Bool
    let isCompleting: Bool
    var onToggleComplete: () -> Void
    var onDelete: () -> Void
    var onPriorityChange: (Priority) -> Void

    @State private var showPriorityMenu = false
    @State private var showDueDatePicker = false

    var body: some View {
        HStack(spacing: 8) {
            // 勾选框
            Button(action: onToggleComplete) {
                Image(systemName: isVisuallyCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isVisuallyCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            // 优先级色标
            Circle()
                .fill(item.priority.color)
                .frame(width: 8, height: 8)
                .onTapGesture { showPriorityMenu = true }
                .popover(isPresented: $showPriorityMenu) {
                    priorityMenu
                }

            // 文字内容
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .strikethrough(isVisuallyCompleted)
                    .foregroundColor(isVisuallyCompleted ? .secondary : .primary)

                // 元信息行
                HStack(spacing: 6) {
                    // 来源应用
                    if let appName = item.sourceAppName {
                        HStack(spacing: 2) {
                            Image(systemName: "app.badge")
                                .font(.system(size: 9))
                            Text(appName)
                                .font(.system(size: 10))
                        }
                        .foregroundColor(.secondary)
                    }

                    // 截止日期
                    if let dueDate = item.dueDate {
                        HStack(spacing: 2) {
                            Image(systemName: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                .font(.system(size: 9))
                                .foregroundColor(item.isOverdue ? .red : .secondary)
                            Text(formatDueDate(dueDate))
                                .font(.system(size: 10))
                                .foregroundColor(item.isOverdue ? .red : .secondary)
                        }
                        .onTapGesture { showDueDatePicker = true }
                    }
                }
            }

            Spacer()

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(item.isOverdue ? Color.red.opacity(0.08) : Color.clear)
        )
        .opacity(isFadingOut ? 0 : 1)
        .animation(.easeOut(duration: 2.5), value: isFadingOut)
        .popover(isPresented: $showDueDatePicker) {
            dueDatePicker
        }
    }

    private var isVisuallyCompleted: Bool {
        item.isCompleted || isCompleting
    }

    private var priorityMenu: some View {
        VStack(spacing: 0) {
            ForEach(Priority.allCases, id: \.self) { p in
                Button(action: { onPriorityChange(p); showPriorityMenu = false }) {
                    HStack {
                        Circle().fill(p.color).frame(width: 8, height: 8)
                        Text(p.displayName)
                            .font(.system(size: 12))
                        Spacer()
                        if item.priority == p {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 100)
    }

    private var dueDatePicker: some View {
        VStack(spacing: 8) {
            DatePicker(
                "截止日期",
                selection: Binding(
                    get: { item.dueDate ?? Date() },
                    set: { TodoListViewModel.shared.setDueDate(item, dueDate: $0) }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .frame(width: 250)

            if item.dueDate != nil {
                Button("清除截止日期") {
                    TodoListViewModel.shared.setDueDate(item, dueDate: nil)
                    showDueDatePicker = false
                }
                .font(.system(size: 12))
                .foregroundColor(.red)
            }

            Button("完成") { showDueDatePicker = false }
                .font(.system(size: 12))
        }
        .padding()
    }

    private func formatDueDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return "今天 \(formatter.string(from: date))"
        } else if calendar.isDateInTomorrow(date) {
            formatter.dateFormat = "HH:mm"
            return "明天 \(formatter.string(from: date))"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MM/dd HH:mm"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "yyyy/MM/dd"
            return formatter.string(from: date)
        }
    }
}

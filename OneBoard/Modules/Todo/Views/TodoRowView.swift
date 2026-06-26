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
                    .oneBoardFont(.title)
                    .foregroundColor(isVisuallyCompleted ? OneBoardColors.success : OneBoardColors.textSecondary)
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
                    .oneBoardFont(.body)
                    .lineLimit(2)
                    .strikethrough(isVisuallyCompleted)
                    .foregroundColor(isVisuallyCompleted ? OneBoardColors.textSecondary : OneBoardColors.textPrimary)

                // 元信息行
                HStack(spacing: 6) {
                    // 来源应用
                    if let appName = item.sourceAppName {
                        HStack(spacing: 2) {
                            Image(systemName: "app.badge")
                                .oneBoardFont(.captionSmall)
                            Text(appName)
                                .oneBoardFont(.captionSmall)
                        }
                        .foregroundColor(OneBoardColors.textSecondary)
                    }

                    // 截止日期
                    if let dueDate = item.dueDate {
                        HStack(spacing: 2) {
                            Image(systemName: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                .oneBoardFont(.captionSmall)
                                .foregroundColor(item.isOverdue ? OneBoardColors.destructive : OneBoardColors.textSecondary)
                            Text(formatDueDate(dueDate))
                                .oneBoardFont(.captionSmall)
                                .foregroundColor(item.isOverdue ? OneBoardColors.destructive : OneBoardColors.textSecondary)
                        }
                        .onTapGesture { showDueDatePicker = true }
                    }
                }
            }

            Spacer()

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .oneBoardFont(.callout)
                    .foregroundColor(OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: OneBoardRadius.md)
                .fill(item.isOverdue ? OneBoardColors.destructive.opacity(0.08) : Color.clear)
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
                            .oneBoardFont(.callout)
                        Spacer()
                        if item.priority == p {
                            Image(systemName: "checkmark")
                                .oneBoardFont(.caption)
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
                .oneBoardFont(.callout)
                .foregroundColor(OneBoardColors.destructive)
            }

            Button("完成") { showDueDatePicker = false }
                .oneBoardFont(.callout)
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

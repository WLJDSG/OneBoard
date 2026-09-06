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
        HStack(spacing: OneBoardSpacing.xs) {
            // 勾选框
            Button(action: onToggleComplete) {
                Image(systemName: isVisuallyCompleted ? "checkmark.circle.fill" : "circle")
                    .oneBoardFont(.title)
                    .foregroundColor(isVisuallyCompleted ? OneBoardColors.success : FeaturePalette.secondary)
            }
            .buttonStyle(.plain)

            // 优先级色标
            Circle()
                .fill(item.priority.color)
                .frame(width: 10, height: 10)
                .onTapGesture { showPriorityMenu = true }
                .popover(isPresented: $showPriorityMenu) {
                    priorityMenu
                }

            // 文字内容
            VStack(alignment: .leading, spacing: OneBoardSpacing.twoXS) {
                Text(item.text)
                    .oneBoardFont(.body)
                    .lineLimit(2)
                    .strikethrough(isVisuallyCompleted)
                    .foregroundColor(isVisuallyCompleted ? FeaturePalette.secondary : FeaturePalette.text)

                // 元信息行
                HStack(spacing: OneBoardSpacing.xs) {
                    // 来源应用
                    if let appName = item.sourceAppName {
                        HStack(spacing: OneBoardSpacing.twoXS) {
                            Image(systemName: "app.badge")
                                .oneBoardFont(.captionSmall)
                            Text(appName)
                                .oneBoardFont(.captionSmall)
                        }
                        .foregroundColor(FeaturePalette.secondary)
                    }

                    // 截止日期
                    if let dueDate = item.dueDate {
                        HStack(spacing: OneBoardSpacing.twoXS) {
                            Image(systemName: item.isOverdue ? "exclamationmark.triangle.fill" : "calendar")
                                .oneBoardFont(.captionSmall)
                                .foregroundColor(item.isOverdue ? OneBoardColors.destructive : FeaturePalette.secondary)
                            Text(formatDueDate(dueDate))
                                .oneBoardFont(.captionSmall)
                                .foregroundColor(item.isOverdue ? OneBoardColors.destructive : FeaturePalette.secondary)
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
                    .foregroundColor(FeaturePalette.secondary)
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, OneBoardSpacing.sm)
        .padding(.vertical, OneBoardSpacing.xs)
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
                    .padding(.horizontal, OneBoardSpacing.sm)
                    .padding(.vertical, OneBoardSpacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, OneBoardSpacing.twoXS)
        .frame(width: 100)
    }

    private var dueDatePicker: some View {
        VStack(spacing: OneBoardSpacing.xs) {
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

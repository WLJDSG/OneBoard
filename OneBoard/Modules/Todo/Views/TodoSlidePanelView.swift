import SwiftUI

/// 待办滑动面板主体视图
struct TodoSlidePanelView: View {
    @ObservedObject var viewModel = TodoListViewModel.shared
    @State private var isAddingTodo = false
    @State private var newTodoText = ""
    @State private var newTodoPriority: Priority = .medium
    @State private var newTodoHasDueDate = false
    @State private var newTodoDueDate = Date().addingTimeInterval(3600)
    @State private var showHistory = false
    @State private var isPinned = false
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 拖拽手柄
            dragHandle

            // 头部
            headerView

            Divider()

            // 搜索栏
            searchBar

            if isAddingTodo {
                inlineAddView
                Divider()
            }

            if let feedbackMessage = viewModel.feedbackMessage {
                feedbackView(feedbackMessage)
                Divider()
            }

            // 列表
            listView

            Divider()

            // 底部操作栏
            bottomBar
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: OneBoardRadius.xl)
                .stroke(OneBoardColors.textPrimary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: OneBoardShadow.lg.color, radius: OneBoardShadow.lg.radius, x: 0, y: OneBoardShadow.lg.y)
        .onChange(of: viewModel.manualAddRequestID) { _ in
            beginAddingTodo()
        }
    }

    // MARK: - 拖拽手柄

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: OneBoardRadius.sm)
            .fill(OneBoardColors.textSecondary.opacity(0.3))
            .frame(width: 32, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - 头部

    private var headerView: some View {
        HStack {
            Image(systemName: "checklist")
                .oneBoardFont(.headline)
                .foregroundColor(OneBoardColors.accent)

            Text("待办事项")
                .oneBoardFont(.headline)

            Spacer()

            // 未完成数量
            let count = viewModel.activeItems.filter { !viewModel.fadingOutIds.contains($0.id ?? 0) }.count
            if count > 0 {
                Text("\(count)")
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(OneBoardColors.textSecondary.opacity(0.15)))
            }

            // 添加按钮
            Button(action: {
                if isAddingTodo {
                    cancelAddingTodo()
                } else {
                    beginAddingTodo()
                }
            }) {
                Image(systemName: "plus.circle.fill")
                    .oneBoardFont(.title)
                    .foregroundColor(OneBoardColors.accent)
            }
            .buttonStyle(.plain)
            .help("手动添加待办")

            Button(action: {
                isPinned.toggle()
                TodoSlidePanelWindowManager.shared.setPinned(isPinned)
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .oneBoardFont(.headline)
                    .foregroundColor(isPinned ? OneBoardColors.accent : OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "取消固定" : "固定在屏幕上")

            // 关闭按钮
            Button(action: { TodoSlidePanelWindowManager.shared.hide() }) {
                Image(systemName: "xmark.circle.fill")
                    .oneBoardFont(.headline)
                    .foregroundColor(OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - 搜索栏

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .oneBoardFont(.caption)
                .foregroundColor(OneBoardColors.textSecondary)
            TextField("搜索待办...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .oneBoardFont(.callout)
                .onChange(of: viewModel.searchQuery) { _ in
                    viewModel.performSearch()
                }
            if !viewModel.searchQuery.isEmpty {
                Button(action: {
                    viewModel.searchQuery = ""
                    viewModel.isSearching = false
                    Task { await viewModel.loadActive() }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .oneBoardFont(.caption)
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(OneBoardColors.accent.opacity(0.06))
    }

    // MARK: - 列表

    private var listView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                let items = viewModel.activeItems

                if items.isEmpty {
                    emptyView
                } else {
                    // 高优先级（未过期）
                    let highActive = items.filter { $0.priority == .high && !$0.isOverdue }
                    if !highActive.isEmpty {
                        sectionHeader("高优先级", color: OneBoardColors.destructive)
                        ForEach(highActive) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }

                    // 过期项
                    let overdue = items.filter { $0.isOverdue }
                    if !overdue.isEmpty {
                        sectionHeader("已过期", color: OneBoardColors.destructive)
                        ForEach(overdue) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }

                    // 中优先级（未过期）
                    let medActive = items.filter { $0.priority == .medium && !$0.isOverdue }
                    if !medActive.isEmpty {
                        sectionHeader("中优先级", color: OneBoardColors.warning)
                        ForEach(medActive) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }

                    // 低优先级 + 无截止日期（未过期）
                    let lowActive = items.filter { ($0.priority == .low || $0.dueDate == nil) && !$0.isOverdue && $0.priority != .high && $0.priority != .medium }
                    if !lowActive.isEmpty {
                        sectionHeader("其他", color: OneBoardColors.textTertiary)
                        ForEach(lowActive) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxHeight: 420)
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title)
                .oneBoardFont(.captionSmall)
                .foregroundColor(OneBoardColors.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func todoRow(_ item: TodoItem) -> some View {
        TodoRowView(
            item: item,
            isFadingOut: viewModel.fadingOutIds.contains(item.id ?? 0),
            isCompleting: viewModel.fadingOutIds.contains(item.id ?? 0),
            onToggleComplete: { viewModel.toggleComplete(item) },
            onDelete: { viewModel.delete(item) },
            onPriorityChange: { viewModel.setPriority(item, priority: $0) }
        )
    }

    private var emptyView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36))
                .foregroundColor(OneBoardColors.textSecondary.opacity(0.4))
            Text(viewModel.isSearching ? "未找到匹配的待办" : "暂无待办事项")
                .oneBoardFont(.callout)
                .foregroundColor(OneBoardColors.textSecondary)
            if !viewModel.isSearching {
                Text("选中文字后按 Cmd+Shift+Option+T 添加")
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.textSecondary.opacity(0.6))
            }
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 底部操作栏

    private var bottomBar: some View {
        HStack {
            Button(action: { showHistory = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "clock.arrow.circlepath")
                        .oneBoardFont(.caption)
                    Text("历史")
                        .oneBoardFont(.caption)
                }
                .foregroundColor(OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // 过期提醒
            let overdueCount = viewModel.activeItems.filter { $0.isOverdue }.count
            if overdueCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .oneBoardFont(.captionSmall)
                    Text("\(overdueCount) 项已过期")
                        .oneBoardFont(.captionSmall)
                }
                .foregroundColor(OneBoardColors.destructive.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .sheet(isPresented: $showHistory) {
            TodoHistoryView()
        }
    }

    // MARK: - 添加

    private var inlineAddView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextEditor(text: $newTodoText)
                .oneBoardFont(.callout)
                .frame(height: 76)
                .padding(6)
                .focused($isNewTodoFocused)
                .onChange(of: isNewTodoFocused) { focused in
                    TodoSlidePanelWindowManager.shared.setEditing(focused || isAddingTodo)
                }
                .background(RoundedRectangle(cornerRadius: OneBoardRadius.md).fill(OneBoardColors.background.opacity(0.75)))
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.md)
                        .stroke(OneBoardColors.textSecondary.opacity(0.25), lineWidth: 1)
                )

            HStack(spacing: 8) {
                Picker("", selection: $newTodoPriority) {
                    ForEach(Priority.allCases, id: \.self) { priority in
                        Text(priority.displayName).tag(priority)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 92)

                Toggle("截止", isOn: $newTodoHasDueDate)
                    .toggleStyle(.checkbox)
                    .oneBoardFont(.caption)

                Spacer()

                Button("取消") {
                    cancelAddingTodo()
                }
                .buttonStyle(.borderless)

                Button("添加") {
                    submitNewTodo()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if newTodoHasDueDate {
                DatePicker("到期", selection: $newTodoDueDate, displayedComponents: [.date, .hourAndMinute])
                    .oneBoardFont(.caption)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(OneBoardColors.accent.opacity(0.04))
    }

    private func feedbackView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .oneBoardFont(.caption)
            Text(message)
                .oneBoardFont(.caption)
                .lineLimit(2)
            Spacer()
        }
        .foregroundColor(OneBoardColors.textSecondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(OneBoardColors.accent.opacity(0.05))
    }

    private func beginAddingTodo() {
        TodoSlidePanelWindowManager.shared.focusForEditing()
        isAddingTodo = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isNewTodoFocused = true
        }
    }

    private func submitNewTodo() {
        viewModel.addTodo(
            text: newTodoText,
            priority: newTodoPriority,
            dueDate: newTodoHasDueDate ? newTodoDueDate : nil,
            showsFeedback: true
        )
        newTodoText = ""
        newTodoPriority = .medium
        newTodoHasDueDate = false
        newTodoDueDate = Date().addingTimeInterval(3600)
        isAddingTodo = false
        isNewTodoFocused = false
        TodoSlidePanelWindowManager.shared.setEditing(false)
    }

    private func cancelAddingTodo() {
        newTodoText = ""
        newTodoPriority = .medium
        newTodoHasDueDate = false
        newTodoDueDate = Date().addingTimeInterval(3600)
        isAddingTodo = false
        isNewTodoFocused = false
        TodoSlidePanelWindowManager.shared.setEditing(false)
    }
}

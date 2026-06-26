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
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        .onChange(of: viewModel.manualAddRequestID) { _ in
            beginAddingTodo()
        }
    }

    // MARK: - 拖拽手柄

    private var dragHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 32, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - 头部

    private var headerView: some View {
        HStack {
            Image(systemName: "checklist")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)

            Text("待办事项")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            // 未完成数量
            let count = viewModel.activeItems.filter { !viewModel.fadingOutIds.contains($0.id ?? 0) }.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
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
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.plain)
            .help("手动添加待办")

            Button(action: {
                isPinned.toggle()
                TodoSlidePanelWindowManager.shared.setPinned(isPinned)
            }) {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 14))
                    .foregroundColor(isPinned ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(isPinned ? "取消固定" : "固定在屏幕上")

            // 关闭按钮
            Button(action: { TodoSlidePanelWindowManager.shared.hide() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
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
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("搜索待办...", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
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
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
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
                        sectionHeader("高优先级", color: .red)
                        ForEach(highActive) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }

                    // 过期项
                    let overdue = items.filter { $0.isOverdue }
                    if !overdue.isEmpty {
                        sectionHeader("已过期", color: .red)
                        ForEach(overdue) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }

                    // 中优先级（未过期）
                    let medActive = items.filter { $0.priority == .medium && !$0.isOverdue }
                    if !medActive.isEmpty {
                        sectionHeader("中优先级", color: .orange)
                        ForEach(medActive) { item in
                            todoRow(item)
                            Divider().padding(.leading, 44)
                        }
                    }

                    // 低优先级 + 无截止日期（未过期）
                    let lowActive = items.filter { ($0.priority == .low || $0.dueDate == nil) && !$0.isOverdue && $0.priority != .high && $0.priority != .medium }
                    if !lowActive.isEmpty {
                        sectionHeader("其他", color: .gray)
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
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
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
                .foregroundColor(.secondary.opacity(0.4))
            Text(viewModel.isSearching ? "未找到匹配的待办" : "暂无待办事项")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            if !viewModel.isSearching {
                Text("选中文字后按 Cmd+Shift+Option+T 添加")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
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
                        .font(.system(size: 11))
                    Text("历史")
                        .font(.system(size: 11))
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            // 过期提醒
            let overdueCount = viewModel.activeItems.filter { $0.isOverdue }.count
            if overdueCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                    Text("\(overdueCount) 项已过期")
                        .font(.system(size: 10))
                }
                .foregroundColor(.red.opacity(0.7))
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
                .font(.system(size: 12))
                .frame(height: 76)
                .padding(6)
                .focused($isNewTodoFocused)
                .onChange(of: isNewTodoFocused) { focused in
                    TodoSlidePanelWindowManager.shared.setEditing(focused || isAddingTodo)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor).opacity(0.75)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
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
                    .font(.system(size: 11))

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
                    .font(.system(size: 11))
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accentColor.opacity(0.04))
    }

    private func feedbackView(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 11))
            Text(message)
                .font(.system(size: 11))
                .lineLimit(2)
            Spacer()
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.05))
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

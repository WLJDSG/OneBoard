import SwiftUI

/// 待办滑动面板 — 现代简约风格
struct TodoSlidePanelView: View {
    @ObservedObject var viewModel = TodoListViewModel.shared
    @State private var isAddingTodo = false
    @State private var newTodoText = ""
    @State private var newTodoPriority: Priority = .medium
    @State private var showHistory = false
    @State private var isPinned: Bool = TodoSlidePanelWindowManager.shared.pinned
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 拖拽手柄
            RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                .fill(FeaturePalette.secondary.opacity(0.3))
                .frame(width: 32, height: 4)
                .padding(.top, OneBoardSpacing.xs)
                .padding(.bottom, OneBoardSpacing.twoXS)

            // 头部
            header

            // 搜索 + 添加
            searchAndAddBar

            // 列表
            todoList

            Divider()

            // 底部
            bottomBar
        }
        .frame(
            width: TodoSlidePanelWindowManager.panelSize.width,
            height: TodoSlidePanelWindowManager.panelSize.height
        )
        .featurePanelStyle()
        .onChange(of: viewModel.manualAddRequestID) { _ in
            beginAddingTodo()
        }
        .onChange(of: showHistory) { newValue in
            TodoSlidePanelWindowManager.shared.shouldSuppressRetract = newValue
        }
    }

    // MARK: - Header

    private var header: some View {
        FeaturePanelHeader(title: "待办", subtitle: "\(viewModel.activeItems.count) 项待完成", icon: "checklist") {
            FeaturePanelIconButton(icon: isPinned ? "pin.fill" : "pin", title: isPinned ? "取消固定" : "固定面板") {
                isPinned.toggle()
                TodoSlidePanelWindowManager.shared.setPinned(isPinned)
            }
            FeaturePanelIconButton(icon: "xmark", title: "关闭") {
                TodoSlidePanelWindowManager.shared.hide()
            }
        }
    }

    // MARK: - 搜索 + 添加

    private var searchAndAddBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: OneBoardSpacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(FeaturePalette.secondary)
                TextField("搜索或添加待办...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .oneBoardFont(.body)
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
                            .font(.system(size: 12))
                            .foregroundColor(FeaturePalette.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: { beginAddingTodo() }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(FeaturePalette.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, OneBoardSpacing.sm)
            .padding(.vertical, OneBoardSpacing.xs - 1)

            // 内联添加表单
            if isAddingTodo {
                Divider()
                HStack(spacing: OneBoardSpacing.xs) {
                    TextField("输入待办内容", text: $newTodoText)
                        .textFieldStyle(.plain)
                        .oneBoardFont(.body)
                        .focused($isNewTodoFocused)
                        .onSubmit { submitNewTodo() }

                    Picker("", selection: $newTodoPriority) {
                        ForEach(Priority.allCases, id: \.self) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 110)

                    Button("取消") { cancelAddingTodo() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 11))
                        .foregroundColor(FeaturePalette.secondary)
                }
                .padding(.horizontal, OneBoardSpacing.sm)
                .padding(.vertical, OneBoardSpacing.xs)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OneBoardRadius.md)
                .fill(FeaturePalette.accent.opacity(0.04))
        )
        .padding(.horizontal, OneBoardSpacing.sm)
        .padding(.vertical, OneBoardSpacing.xs)
    }

    // MARK: - 列表

    @ViewBuilder
    private var todoList: some View {
        Group {
            if viewModel.activeItems.isEmpty {
                VStack(spacing: OneBoardSpacing.sm) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(FeaturePalette.secondary.opacity(0.3))
                    Text(viewModel.isSearching ? "无匹配结果" : "暂无待办")
                        .oneBoardFont(.body)
                        .foregroundColor(FeaturePalette.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
            } else {
                let items = sortedItems(viewModel.activeItems)
                VStack(spacing: 0) {
                    List {
                        ForEach(items) { item in
                            TodoRowView(
                                item: item,
                                isFadingOut: viewModel.fadingOutIds.contains(item.id ?? 0),
                                isCompleting: viewModel.fadingOutIds.contains(item.id ?? 0),
                                onToggleComplete: { viewModel.toggleComplete(item) },
                                onDelete: { viewModel.delete(item) },
                                onPriorityChange: { viewModel.setPriority(item, priority: $0) }
                            )
                            .padding(.horizontal, OneBoardSpacing.sm)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                        }
                        .onMove(perform: viewModel.moveItem)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity)

                    if let msg = viewModel.feedbackMessage {
                        Text(msg)
                            .font(.system(size: 10))
                            .foregroundColor(FeaturePalette.secondary)
                            .padding(.horizontal, OneBoardSpacing.sm)
                            .padding(.bottom, OneBoardSpacing.twoXS)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sortedItems(_ items: [TodoItem]) -> [TodoItem] {
        items.sorted { a, b in
            if a.isOverdue != b.isOverdue { return a.isOverdue }
            if a.priority.sortOrder != b.priority.sortOrder { return a.priority.sortOrder < b.priority.sortOrder }
            return a.sortOrder < b.sortOrder
        }
    }

    // MARK: - 底部

    private var bottomBar: some View {
        HStack {
            Button(action: { showHistory = true }) {
                HStack(spacing: OneBoardSpacing.twoXS) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11))
                    Text("历史")
                        .font(.system(size: 11))
                }
                .foregroundColor(FeaturePalette.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            let overdueCount = viewModel.activeItems.filter { $0.isOverdue }.count
            if overdueCount > 0 {
                HStack(spacing: OneBoardSpacing.twoXS) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("\(overdueCount) 项已过期")
                        .font(.system(size: 10))
                }
                .foregroundColor(OneBoardColors.destructive.opacity(0.7))
            }
        }
        .padding(.horizontal, OneBoardSpacing.sm)
        .padding(.vertical, OneBoardSpacing.xs)
        .sheet(isPresented: $showHistory) {
            TodoHistoryView()
        }
    }

    // MARK: - 添加逻辑

    private func beginAddingTodo() {
        TodoSlidePanelWindowManager.shared.focusForEditing()
        isAddingTodo = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            isNewTodoFocused = true
        }
    }

    private func submitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.addTodo(text: trimmed, priority: newTodoPriority, dueDate: nil, showsFeedback: true)
        newTodoText = ""
        newTodoPriority = .medium
        isAddingTodo = false
        isNewTodoFocused = false
        TodoSlidePanelWindowManager.shared.suppressRetract(for: 3.0)
        TodoSlidePanelWindowManager.shared.setEditing(false)
    }

    private func cancelAddingTodo() {
        newTodoText = ""
        newTodoPriority = .medium
        isAddingTodo = false
        isNewTodoFocused = false
        TodoSlidePanelWindowManager.shared.setEditing(false)
    }
}

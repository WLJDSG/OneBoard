import SwiftUI

/// 剪贴板 Popover 根视图
struct ClipboardPopoverView: View {
    @StateObject private var viewModel = ClipboardListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // 顶部标题栏
            headerView

            Divider()

            // 搜索栏
            ClipboardSearchBar(
                searchText: $viewModel.searchText,
                onSearch: { Task { await viewModel.performSearch() } },
                onClear: { viewModel.clearSearch() }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // 列表
            ClipboardListView(viewModel: viewModel)

            // 底部状态栏
            footerView
        }
        .frame(minWidth: Constants.popoverWidth - 50)
        .background(OneBoardColors.background)
        .task {
            await viewModel.loadEntries()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("历史剪贴板")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(OneBoardColors.textPrimary)

            Spacer()

            Button(action: {
                Task { await viewModel.clearAll() }
            }) {
                Text("清空")
                    .font(.system(size: 11))
                    .foregroundColor(OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("清空所有非置顶记录")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Text("共 \(viewModel.entries.count) 条记录")
                .font(.system(size: 10))
                .foregroundColor(OneBoardColors.textSecondary)

            Spacer()

            Text("点击条目可直接粘贴")
                .font(.system(size: 10))
                .foregroundColor(OneBoardColors.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(OneBoardColors.secondaryBackground)
    }
}
import SwiftUI

/// 剪贴板 Popover 根视图（无标题栏，失焦自动关闭）
struct ClipboardPopoverView: View {
    @StateObject private var viewModel = ClipboardListViewModel()

    var body: some View {
        VStack(spacing: 0) {
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
        }
        .frame(minWidth: Constants.popoverWidth - 50, minHeight: 250)
        .oneBoardPanelStyle()
        .task {
            await viewModel.loadEntries()
        }
    }
}

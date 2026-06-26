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
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: OneBoardRadius.xl)
                .stroke(OneBoardColors.accent.opacity(0.08), lineWidth: 1)
        )
        .shadow(
            color: OneBoardShadow.lg.color,
            radius: OneBoardShadow.lg.radius,
            x: 0,
            y: OneBoardShadow.lg.y
        )
        .task {
            await viewModel.loadEntries()
        }
    }
}

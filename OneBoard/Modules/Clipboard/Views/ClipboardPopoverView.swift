import SwiftUI

/// 剪贴板 Popover — 精确还原设计规范

struct ClipboardPopoverView: View {
    @StateObject private var viewModel = ClipboardListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header: 📋 剪贴板 [×]
            HStack(spacing: 8) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OneBoardColors.accent)
                Text("剪贴板")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button(action: { MenuBarManager.shared.closeClipboardFloatingWindow() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(OneBoardColors.surface.opacity(0.5))

            Divider()

            // Search
            ClipboardSearchBar(
                searchText: $viewModel.searchText,
                onSearch: { Task { await viewModel.performSearch() } },
                onClear: { viewModel.clearSearch() }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // List
            ClipboardListView(viewModel: viewModel)

            // Status bar
            HStack {
                Text("\(viewModel.entries.count) 条记录")
                    .font(.system(size: 10))
                    .foregroundColor(OneBoardColors.textTertiary)
                Spacer()
                Text("保留 30 天")
                    .font(.system(size: 10))
                    .foregroundColor(OneBoardColors.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 300, minHeight: 250)
        .oneBoardPanelStyle()
        .task { await viewModel.loadEntries() }
    }
}

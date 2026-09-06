import SwiftUI

/// 剪贴板 Popover — 精确还原设计规范

struct ClipboardPopoverView: View {
    @AppStorage(Constants.UserDefaultsKeys.retentionDays) private var retentionDays = Constants.defaultRetentionDays
    @StateObject private var viewModel = ClipboardListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            FeaturePanelHeader(title: "剪贴板", subtitle: "分类筛选 · 点击预览 · 复制或粘贴", icon: "doc.on.clipboard") {
                EmptyView()
            }

            // Search
            ClipboardSearchBar(
                searchText: $viewModel.searchText,
                onSearch: { Task { await viewModel.performSearch() } },
                onClear: { viewModel.clearSearch() }
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // List
            ClipboardBrowserView(viewModel: viewModel)

            // Status bar
            HStack {
                Text("\(viewModel.entries.count) 条记录")
                    .font(.system(size: 10))
                    .foregroundColor(FeaturePalette.secondary)
                Spacer()
                Text(retentionDays < 0 ? "永久保留" : "保留 \(retentionDays) 天")
                    .font(.system(size: 10))
                    .foregroundColor(FeaturePalette.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 720, minHeight: 480)
        .featurePanelStyle()
        .task { await viewModel.loadEntries() }
    }
}

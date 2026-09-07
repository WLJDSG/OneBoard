import SwiftUI

/// 剪贴板面板

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
            .padding(.horizontal, InterfaceMetrics.panelInset)
            .padding(.vertical, 8)

            // List
            ClipboardBrowserView(viewModel: viewModel)

            // Status bar
            HStack {
                Text("\(viewModel.entries.count) 条记录")
                    .font(.system(size: 11))
                    .foregroundColor(FeaturePalette.secondary)
                Spacer()
                Text(retentionDays < 0 ? "永久保留" : "保留 \(retentionDays) 天")
                    .font(.system(size: 11))
                    .foregroundColor(FeaturePalette.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(minWidth: 720, minHeight: 480)
        .featurePanelStyle()
        .task { await viewModel.loadEntries() }
    }
}

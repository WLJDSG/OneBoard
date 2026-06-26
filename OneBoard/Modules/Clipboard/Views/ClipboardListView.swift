import SwiftUI

/// 剪贴板列表
struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardListViewModel

    var body: some View {
        if viewModel.entries.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.entries) { entry in
                        ClipboardRowView(
                            entry: entry,
                            onTap: { viewModel.selectAndPaste(entry) },
                            onPin: { Task { await viewModel.togglePin(entry) } },
                            onDelete: { Task { await viewModel.delete(entry) } }
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .oneBoardFont(.titleLarge)
                .foregroundColor(OneBoardColors.textSecondary.opacity(0.4))

            if viewModel.searchText.isEmpty {
                Text("暂无剪贴板记录")
                    .oneBoardFont(.body)
                    .foregroundColor(OneBoardColors.textSecondary)
                Text("复制任意内容后自动记录")
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.textSecondary.opacity(0.6))
            } else {
                Text("未找到匹配结果")
                    .oneBoardFont(.body)
                    .foregroundColor(OneBoardColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}
import SwiftUI

/// 剪贴板列表
struct ClipboardListView: View {
    @ObservedObject var viewModel: ClipboardListViewModel

    private var pinnedEntries: [ClipboardEntry] { viewModel.entries.filter { $0.isPinned } }
    private var normalEntries: [ClipboardEntry] { viewModel.entries.filter { !$0.isPinned } }

    var body: some View {
        if viewModel.entries.isEmpty {
            emptyView
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    // 置顶分区
                    if !pinnedEntries.isEmpty {
                        sectionLabel("已置顶")
                        ForEach(pinnedEntries) { entry in
                            rowView(entry)
                        }
                        if !normalEntries.isEmpty {
                            Divider().padding(.horizontal, 14)
                        }
                    }

                    // 普通分区
                    ForEach(normalEntries) { entry in
                        rowView(entry)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(OneBoardColors.textTertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func rowView(_ entry: ClipboardEntry) -> some View {
        ClipboardRowView(
            entry: entry,
            onTap: { viewModel.selectAndPaste(entry) },
            onPin: { Task { await viewModel.togglePin(entry) } },
            onDelete: { Task { await viewModel.delete(entry) } }
        )
        .padding(.horizontal, 8)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 32))
                .foregroundColor(OneBoardColors.textSecondary.opacity(0.3))

            if viewModel.searchText.isEmpty {
                Text("暂无剪贴板记录")
                    .font(.system(size: 13))
                    .foregroundColor(OneBoardColors.textSecondary)
                Text("复制任意内容后自动记录")
                    .font(.system(size: 11))
                    .foregroundColor(OneBoardColors.textSecondary.opacity(0.6))
            } else {
                Text("未找到匹配结果")
                    .font(.system(size: 13))
                    .foregroundColor(OneBoardColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}

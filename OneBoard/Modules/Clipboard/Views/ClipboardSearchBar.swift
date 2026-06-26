import SwiftUI

/// 剪贴板搜索栏
struct ClipboardSearchBar: View {
    @Binding var searchText: String
    let onSearch: () -> Void
    let onClear: () -> Void

    @FocusState private var isFocused: Bool
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .oneBoardFont(.callout)
                .foregroundColor(OneBoardColors.textSecondary)

            TextField("搜索剪贴板历史...", text: $searchText)
                .textFieldStyle(.plain)
                .oneBoardFont(.body)
                .focused($isFocused)
                .onSubmit { onSearch() }
                .onChange(of: searchText) { _, _ in
                    handleSearchTextChange()
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    onClear()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .oneBoardFont(.callout)
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                .fill(OneBoardColors.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                .stroke(isFocused ? OneBoardColors.accent.opacity(0.10) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
    }

    private func handleSearchTextChange() {
        // 取消之前的防抖任务
        debounceTask?.cancel()

        if searchText.isEmpty {
            onClear()
            return
        }

        // 防抖：延迟 0.3 秒后触发搜索
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
            guard !Task.isCancelled else { return }
            await MainActor.run {
                onSearch()
            }
        }
    }
}

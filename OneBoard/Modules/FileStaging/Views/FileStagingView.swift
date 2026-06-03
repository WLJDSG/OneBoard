import SwiftUI

/// 统一文件暂存视图 - 空时显示拖放提示，有文件时显示列表
struct FileStagingView: View {
    @ObservedObject var viewModel: FileStagingViewModel
    let onClose: () -> Void

    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            headerView

            if viewModel.stagedFiles.isEmpty {
                // 空状态：拖放提示
                dropPromptView
            } else {
                // 文件列表
                fileListView
            }
        }
        .frame(minWidth: 220, maxWidth: 320)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 2)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .task {
            await viewModel.reloadFiles()
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("暂存")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)

            if !viewModel.stagedFiles.isEmpty {
                Text("· \(viewModel.stagedFiles.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary.opacity(0.6))
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    // MARK: - Drop Prompt (空状态)

    private var dropPromptView: some View {
        VStack(spacing: 6) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                .font(.system(size: 24))
                .foregroundColor(isDropTargeted ? OneBoardColors.primary : .secondary.opacity(0.5))

            Text(isDropTargeted ? "松开放入" : "拖拽文件到此处")
                .font(.system(size: 12))
                .foregroundColor(isDropTargeted ? OneBoardColors.primary : .secondary)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }

    // MARK: - File List (有文件)

    private var fileListView: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.stagedFiles) { file in
                StagedFileRowView(
                    file: file,
                    onDelete: {
                        Task { await viewModel.removeFile(file) }
                    }
                )
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 6)
    }

    // MARK: - Drop Handling

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    viewModel.addFile(url: url)
                }
            }
        }
    }
}
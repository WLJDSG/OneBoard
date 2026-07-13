import SwiftUI

/// 文件暂存悬浮视图
struct FileStagingView: View {
    @ObservedObject var viewModel: FileStagingViewModel
    let onClose: () -> Void

    @State private var isDropTargeted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Content
            if viewModel.stagedFiles.isEmpty {
                dropPrompt
                    .frame(maxHeight: .infinity)
            } else {
                fileGrid
            }
        }
        .frame(width: FileStagingViewModel.shelfSize.width, height: FileStagingViewModel.shelfSize.height)
        .oneBoardPanelStyle()
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .task {
            await viewModel.reloadFiles()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OneBoardColors.accent)
            Text("暂存架")
                .font(.system(size: 13, weight: .semibold))
            if !viewModel.stagedFiles.isEmpty {
                Text("\(viewModel.stagedFiles.count)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(OneBoardColors.textSecondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: OneBoardRadius.sm).fill(OneBoardColors.textSecondary.opacity(0.12)))
            }
            Spacer()
            OneBoardCloseButton(action: onClose)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(OneBoardColors.headerBorder).frame(height: 1), alignment: .bottom)
    }

    // MARK: - Drop Prompt

    private var dropPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 36))
                .foregroundColor(isDropTargeted ? OneBoardColors.accent : OneBoardColors.textTertiary.opacity(0.5))
            Text(isDropTargeted ? "松开放入" : "拖放文件到此处")
                .font(.system(size: 13))
                .foregroundColor(isDropTargeted ? OneBoardColors.accent : OneBoardColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)
    }

    // MARK: - File Grid

    private var fileGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 88), spacing: 12)],
                spacing: 12
            ) {
                ForEach(viewModel.stagedFiles) { file in
                    fileTile(file)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 340)
    }

    private func fileTile(_ file: StagedFile) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 6) {
                thumbnail(for: file)
                    .onDrag {
                        let url = URL(fileURLWithPath: file.fileURL)
                        return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: file.fileName as NSString)
                    }

                Text(file.fileName)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 80)
                    .foregroundColor(OneBoardColors.textPrimary)
            }
            .frame(width: 88, height: 100)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .fill(OneBoardColors.accent.opacity(0.04))
            )

            Button {
                Task { await viewModel.removeFile(file) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(OneBoardColors.textTertiary)
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
        }
    }

    private func thumbnail(for file: StagedFile) -> some View {
        Group {
            if let data = file.thumbnailData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.fileURL))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: 56, height: 56)
    }

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    viewModel.addFile(url: url)
                }
            }
        }
    }
}

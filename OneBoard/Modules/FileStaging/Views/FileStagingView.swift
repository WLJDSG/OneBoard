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


            // Content
            ZStack(alignment: .topLeading) {
                if viewModel.stagedFiles.isEmpty {
                    dropPrompt
                } else {
                    fileGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FeaturePalette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(
                isDropTargeted ? FeaturePalette.accent : FeaturePalette.border,
                style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: [5])))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            Text("移除暂存项不会删除原文件")
                .font(.system(size: 10)).foregroundStyle(.secondary)
                .padding(.bottom, 14)
        }
        .frame(width: FileStagingViewModel.shelfSize.width, height: FileStagingViewModel.shelfSize.height)
        .featurePanelStyle()
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
        FeaturePanelHeader(title: "文件暂存区", subtitle: "\(viewModel.stagedFiles.count) 个文件 · 拖入收集，拖出使用", icon: "tray.full") {
            FeaturePanelIconButton(icon: "xmark", title: "关闭", action: onClose)
        }
    }

    // MARK: - Drop Prompt

    private var dropPrompt: some View {
        VStack(spacing: 12) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "tray")
                .font(.system(size: 36))
                .foregroundColor(isDropTargeted ? FeaturePalette.accent : FeaturePalette.secondary.opacity(0.5))
            Text(isDropTargeted ? "松开放入" : "拖放文件到此处")
                .font(.system(size: 13))
                .foregroundColor(isDropTargeted ? FeaturePalette.accent : FeaturePalette.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .foregroundColor(FeaturePalette.text)
            }
            .frame(width: 88, height: 100)
            .background(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .fill(FeaturePalette.accent.opacity(0.04))
            )

            Button {
                Task { await viewModel.removeFile(file) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(FeaturePalette.secondary)
            }
            .buttonStyle(.plain)
            .help("移除暂存项")
            .accessibilityLabel("移除 \(file.fileName)")
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

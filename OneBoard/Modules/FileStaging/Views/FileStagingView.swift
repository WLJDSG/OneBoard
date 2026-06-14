import SwiftUI

/// 文件暂存悬浮视图
struct FileStagingView: View {
    @ObservedObject var viewModel: FileStagingViewModel
    let onClose: () -> Void

    @State private var isDropTargeted: Bool = false

    var body: some View {
        ZStack {
            // 内容层（有 rounded corner 裁剪，避免直角底色）
            VStack(spacing: 8) {
                headerView

                if viewModel.stagedFiles.isEmpty {
                    dropPromptView
                } else {
                    stagedPreview
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 24)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
            )
        }
        .frame(width: 348)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
            return true
        }
        .task {
            await viewModel.reloadFiles()
        }
    }

    private var headerView: some View {
        HStack {
            circleButton("xmark", action: onClose)
            Spacer()
        }
        .frame(height: 32)
        .background(WindowDragArea())
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.black.opacity(0.62))
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.58)))
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var dropPromptView: some View {
        VStack(spacing: 8) {
            Image(systemName: isDropTargeted ? "tray.and.arrow.down.fill" : "doc.badge.plus")
                .font(.system(size: 34))
                .foregroundColor(isDropTargeted ? OneBoardColors.primary : .black.opacity(0.38))

            Text(isDropTargeted ? "松开放入" : "拖到这里")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(isDropTargeted ? OneBoardColors.primary : .black.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 124)
        .background(WindowDragArea())
    }

    private var stagedPreview: some View {
        let columns = [
            GridItem(.adaptive(minimum: 92), spacing: 14)
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(viewModel.stagedFiles) { file in
                    stagedFileTile(file)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 366)
    }

    private func stagedFileTile(_ file: StagedFile) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 8) {
                filePreview(file)
                    .onDrag {
                        let url = URL(fileURLWithPath: file.fileURL)
                        return NSItemProvider(contentsOf: url) ?? NSItemProvider(object: file.fileName as NSString)
                    }

                Text(file.fileName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 92)
                    .foregroundColor(.black.opacity(0.78))
            }
            .frame(width: 96, height: 116)

            StagedFileDeleteButton {
                Task { await viewModel.removeFile(file) }
            }
            .offset(x: -2, y: 2)
        }
    }

    private func filePreview(_ file: StagedFile) -> some View {
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
        .frame(width: 72, height: 78)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.52)))
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

private struct StagedFileDeleteButton: View {
    let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    private var isActive: Bool {
        isHovered || isFocused
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isActive ? .white : OneBoardColors.destructive.opacity(0.68))
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isActive ? OneBoardColors.destructive.opacity(0.92) : Color.white.opacity(0.78))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isActive ? OneBoardColors.destructive.opacity(0.95) : OneBoardColors.destructive.opacity(0.18),
                            lineWidth: 1
                        )
                )
                .clipShape(Circle())
                .shadow(color: isActive ? OneBoardColors.destructive.opacity(0.18) : .black.opacity(0.08), radius: isActive ? 4 : 2, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .contentShape(Circle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override var acceptsFirstResponder: Bool { false }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

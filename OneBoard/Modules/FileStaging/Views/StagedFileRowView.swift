import SwiftUI

/// 暂存文件行视图
struct StagedFileRowView: View {
    let file: StagedFile
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            // 缩略图/文件图标
            fileIcon

            // 文件信息
            VStack(alignment: .leading, spacing: 2) {
                Text(file.fileName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                Text(FileIconProvider.formatFileSize(file.fileSize))
                    .font(.system(size: 10))
                    .foregroundColor(OneBoardColors.textSecondary)
            }

            Spacer()

            // 删除按钮
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OneBoardColors.destructive.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("移除")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? OneBoardColors.primary.opacity(0.08) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onDrag {
            NSItemProvider(contentsOf: URL(fileURLWithPath: file.fileURL)) ?? NSItemProvider()
        }
    }

    // MARK: - File Icon

    private var fileIcon: some View {
        Group {
            if let thumbData = file.thumbnailData, let nsImage = NSImage(data: thumbData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                let url = URL(fileURLWithPath: file.fileURL)
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            }
        }
    }
}
import SwiftUI

/// 剪贴板单行视图
struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let onTap: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 10) {
            // 类型图标
            typeIcon

            // 内容预览
            contentPreview

            Spacer()

            // 操作按钮（悬停时显示）
            if isHovered {
                actionButtons
            }

            // 时间
            Text(entry.createdAt.timeAgoDescription)
                .font(.system(size: 10))
                .foregroundColor(OneBoardColors.textSecondary)
                .frame(width: 55, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("粘贴") { onTap() }
            Button(entry.isPinned ? "取消置顶" : "置顶") { onPin() }
            Divider()
            Button("删除", role: .destructive) { onDelete() }
        }
    }

    // MARK: - Type Icon

    @ViewBuilder
    private var typeIcon: some View {
        if entry.isImage, let nsImage = entry.nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(OneBoardColors.primary.opacity(0.15))

                Image(systemName: entry.contentTypeEnum?.iconName ?? "doc")
                    .font(.system(size: 12))
                    .foregroundColor(OneBoardColors.primary)
            }
            .frame(width: 28, height: 28)
        }
    }

    // MARK: - Content Preview

    private var contentPreview: some View {
        VStack(alignment: .leading, spacing: 2) {
            if entry.isPinned {
                HStack(spacing: 4) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(OneBoardColors.primary)
                    Text(entry.previewText)
                        .font(.system(size: 12))
                        .lineLimit(2)
                        .foregroundColor(OneBoardColors.textPrimary)
                }
            } else {
                Text(entry.previewText)
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundColor(OneBoardColors.textPrimary)
            }

            if let sourceApp = entry.sourceAppBundleId {
                Text(sourceApp)
                    .font(.system(size: 9))
                    .foregroundColor(OneBoardColors.textSecondary.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if entry.isPinned {
            OneBoardColors.pinnedHighlight.opacity(isHovered ? 1.0 : 0.7)
        } else if isHovered {
            OneBoardColors.primary.opacity(0.08)
        } else {
            Color.clear
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 6) {
            // 置顶按钮
            Button(action: onPin) {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 11))
                    .foregroundColor(entry.isPinned ? OneBoardColors.primary : OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "取消置顶" : "置顶")

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(OneBoardColors.destructive.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("删除")
        }
    }
}
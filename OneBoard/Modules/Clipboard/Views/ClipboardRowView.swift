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
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            // 操作按钮（悬停时显示）
            actionButtons
                .opacity(isHovered ? 1 : 0)
                .allowsHitTesting(isHovered)
                .disabled(!isHovered)
                .accessibilityHidden(!isHovered)
                .frame(width: 36, alignment: .trailing)

            // 时间
            Text(entry.createdAt.timeAgoDescription)
                .oneBoardFont(.captionSmall)
                .foregroundColor(OneBoardColors.textSecondary)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if entry.isPinned {
                RoundedRectangle(cornerRadius: 2)
                    .fill(OneBoardColors.accent)
                    .frame(width: 2)
                    .padding(.vertical, 4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
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
                .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.sm))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                    .fill(OneBoardColors.accent.opacity(0.15))

                Image(systemName: entry.contentTypeEnum?.iconName ?? "doc")
                    .oneBoardFont(.callout)
                    .foregroundColor(OneBoardColors.accent)
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
                        .oneBoardFont(.captionSmall)
                        .foregroundColor(OneBoardColors.accent)
                    Text(entry.previewText)
                        .oneBoardFont(.callout)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(OneBoardColors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            } else {
                Text(entry.previewText)
                    .oneBoardFont(.callout)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(OneBoardColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }

            if let sourceApp = entry.sourceAppBundleId {
                Text(sourceApp)
                    .oneBoardFont(.captionSmall)
                    .foregroundColor(OneBoardColors.textSecondary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    // MARK: - Row Background

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: OneBoardRadius.md)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if entry.isPinned {
            OneBoardColors.accent.opacity(0.06)
        } else if isHovered {
            OneBoardColors.accent.opacity(0.06)
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
                    .oneBoardFont(.caption)
                    .foregroundColor(entry.isPinned ? OneBoardColors.accent : OneBoardColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "取消置顶" : "置顶")

            // 删除按钮
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.destructive.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("删除")
        }
    }
}

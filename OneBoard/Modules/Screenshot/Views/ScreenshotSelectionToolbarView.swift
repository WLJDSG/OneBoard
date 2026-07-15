import SwiftUI

struct ScreenshotSelectionToolbarView: View {
    let onAction: (ScreenshotSelectionAction) -> Void

    private let annotationTools: [AnnotationTool] = [
        .rectangle, .ellipse, .arrow, .line, .text, .number, .mosaic,
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(annotationTools, id: \.self) { tool in
                actionButton(icon: tool.iconName, help: tool.displayName) {
                    onAction(.annotate(tool))
                }
            }

            Divider().frame(height: 22)

            actionButton(icon: "doc.on.doc", help: "复制") { onAction(.copy) }
            actionButton(icon: "square.and.arrow.down", help: "保存") { onAction(.save) }
            actionButton(icon: "pin", help: "贴图") { onAction(.pin) }
            actionButton(icon: "text.viewfinder", help: "OCR") { onAction(.ocr) }
            actionButton(icon: "character.bubble", help: "翻译") { onAction(.translate) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OneBoardRadius.lg))
        .shadow(
            color: OneBoardShadow.lg.color,
            radius: OneBoardShadow.lg.radius,
            x: 0,
            y: OneBoardShadow.lg.y
        )
    }

    private func actionButton(
        icon: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .oneBoardFont(.body)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: OneBoardRadius.sm)
                        .fill(OneBoardColors.accent.opacity(0.10))
                )
                .foregroundColor(OneBoardColors.textPrimary)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

import AppKit
import SwiftUI
import Translation

struct TranslationPanelView: View {
    @ObservedObject var viewModel: TranslationPanelViewModel
    let onTranslate: () -> Void
    let onSelectService: (TranslationServiceType) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            VStack(alignment: .leading, spacing: 12) {
                sourceSection
                translationSection
                statusBar
                actionBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
        }
        .translationTask(viewModel.appleTranslationConfiguration) { session in
            await viewModel.translateWithAppleSession(session)
        }
        .frame(minWidth: 520, maxWidth: 520, minHeight: 400, maxHeight: 700)
        .oneBoardPanelStyle()
    }

    private var titleBar: some View {
        ZStack {
            TranslationPanelDragHandle()
            HStack {
                Image(systemName: serviceIconName)
                    .oneBoardFont(.headline)
                    .foregroundColor(OneBoardColors.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("翻译工作台")
                        .oneBoardFont(.headline)
                    Text(viewModel.translationServiceType.displayName)
                        .font(.system(size: 11))
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.top, 6)
        }
        .frame(height: 44)
        .oneBoardPanelHeader()
    }

    private var serviceIconName: String {
        switch viewModel.translationServiceType {
        case .apple:
            return "apple.logo"
        case .google:
            return "globe"
        case .deepSeek:
            return "sparkles"
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("原文")
                    .oneBoardFont(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                Spacer()
                Button {
                    viewModel.clearSourceText()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .disabled(viewModel.sourceText.isEmpty)
                .help("清空原文")
            }
            TextEditor(text: $viewModel.sourceText)
                .oneBoardFont(.body)
                .scrollContentBackground(.hidden)
                .background(OneBoardColors.background)
                .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.md)
                        .stroke(OneBoardColors.borderSubtle, lineWidth: 1)
                )
                .frame(minHeight: 120)
                .frame(height: 132)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("译文")
                .oneBoardFont(.caption)
                .foregroundColor(OneBoardColors.textSecondary)
            ScrollView {
                if viewModel.isTranslating {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("翻译中...")
                            .oneBoardFont(.caption)
                            .foregroundColor(OneBoardColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                } else {
                    Text(translationText)
                        .oneBoardFont(.body)
                        .foregroundColor(viewModel.translatedText.isEmpty ? OneBoardColors.textSecondary : OneBoardColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            }
            .background(OneBoardColors.background)
            .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .stroke(OneBoardColors.borderSubtle, lineWidth: 1)
            )
            .frame(minHeight: 120)
            .frame(height: 132)
        }
    }

    private var translationText: String {
        viewModel.translatedText.isEmpty ? "译文会显示在这里" : viewModel.translatedText
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.errorMessage ?? serviceStatusText)
                .oneBoardFont(.caption)
                .foregroundColor(viewModel.errorMessage == nil ? OneBoardColors.textSecondary : OneBoardColors.destructive)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 0, alignment: .topLeading)
    }

    private var serviceStatusText: String {
        switch viewModel.translationServiceType {
        case .apple:
            return "Apple 使用系统 Translation，可离线能力取决于系统支持。"
        case .google:
            return "Google 使用免费 Web 接口，不需要 API Key。"
        case .deepSeek:
            return "DeepSeek 需要在设置中填写 API Key。"
        }
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            Picker("源语言", selection: $viewModel.sourceLanguage) {
                ForEach(TranslationLanguage.sourceOptions) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .disabled(viewModel.isTranslating)
            .frame(width: 100)

            Button {
                viewModel.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.sourceLanguage == .auto || viewModel.translatedText.isEmpty || viewModel.isTranslating)
            .help("交换语言")

            Picker("目标语言", selection: $viewModel.targetLanguage) {
                ForEach(TranslationLanguage.targetOptions) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .disabled(viewModel.isTranslating)

            Spacer()

            Button(action: onTranslate) {
                Label("重新翻译", systemImage: "arrow.clockwise")
            }
            .oneBoardPrimaryButton()
            .disabled(viewModel.isTranslating || !hasSourceText)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.sourceText, forType: .string)
            } label: {
                Label("复制原文", systemImage: "doc.on.doc")
            }
            .oneBoardSecondaryButton()
            .disabled(viewModel.sourceText.isEmpty || viewModel.isTranslating)

            Button {
                viewModel.copyTranslatedText()
            } label: {
                Label("复制译文", systemImage: "doc.on.clipboard")
            }
            .oneBoardSecondaryButton()
            .disabled(viewModel.translatedText.isEmpty || viewModel.isTranslating)
        }
    }

    private var hasSourceText: Bool {
        !viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

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
                serviceControl
                languageControls
                sourceSection
                translationSection
                statusBar
                actionBar
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .translationTask(viewModel.appleTranslationConfiguration) { session in
            await viewModel.translateWithAppleSession(session)
        }
        .frame(width: 520, height: 600)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .oneBoardFont(.headline)
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.leading, 16)
            .padding(.trailing, 10)
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

    private var serviceControl: some View {
        Picker("翻译服务", selection: serviceSelection) {
            ForEach(TranslationServiceType.allCases) { serviceType in
                Text(serviceType.displayName).tag(serviceType)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var serviceSelection: Binding<TranslationServiceType> {
        Binding(
            get: { viewModel.translationServiceType },
            set: { newValue in
                onSelectService(newValue)
            }
        )
    }

    private var languageControls: some View {
        HStack(spacing: 8) {
            languagePicker("源语言", selection: $viewModel.sourceLanguage, options: TranslationLanguage.sourceOptions)

            Button {
                viewModel.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.sourceLanguage == .auto || viewModel.translatedText.isEmpty || viewModel.isTranslating)
            .help("交换语言")

            languagePicker("目标语言", selection: $viewModel.targetLanguage, options: TranslationLanguage.targetOptions)
        }
    }

    private func languagePicker(
        _ title: String,
        selection: Binding<TranslationLanguage>,
        options: [TranslationLanguage]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .oneBoardFont(.captionSmall)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(options) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .disabled(viewModel.isTranslating)
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("原文")
                    .oneBoardFont(.caption)
                    .foregroundStyle(.secondary)
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
                .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
                .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.md)
                        .stroke(OneBoardColors.textPrimary.opacity(0.10), lineWidth: 1)
                )
                .frame(height: 128)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("译文")
                .oneBoardFont(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(translationText)
                    .oneBoardFont(.body)
                    .foregroundColor(viewModel.translatedText.isEmpty ? OneBoardColors.textSecondary : OneBoardColors.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.78))
            .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: OneBoardRadius.md)
                    .stroke(OneBoardColors.textPrimary.opacity(0.10), lineWidth: 1)
            )
            .frame(height: 132)
        }
    }

    private var translationText: String {
        if viewModel.isTranslating {
            return "翻译中..."
        }
        return viewModel.translatedText.isEmpty ? "译文会显示在这里" : viewModel.translatedText
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.errorMessage ?? serviceStatusText)
                .oneBoardFont(.caption)
                .foregroundColor(viewModel.errorMessage == nil ? OneBoardColors.textSecondary : OneBoardColors.destructive)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .topLeading)
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
            Button(action: onTranslate) {
                Label("重新翻译", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isTranslating || !hasSourceText)

            Button {
                viewModel.copyTranslatedText()
            } label: {
                Label("复制译文", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.translatedText.isEmpty || viewModel.isTranslating)

            Spacer()
        }
    }

    private var hasSourceText: Bool {
        !viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

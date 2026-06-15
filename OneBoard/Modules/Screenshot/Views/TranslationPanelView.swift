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
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    private var titleBar: some View {
        ZStack {
            TranslationPanelDragHandle()
            HStack {
                Text("翻译工作台 · \(viewModel.translationServiceType.displayName)")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
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
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    Color(nsColor: .windowBackgroundColor).opacity(0.72)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Divider(), alignment: .bottom)
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
                .font(.system(size: 10, weight: .medium))
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
                    .font(.system(size: 11, weight: .semibold))
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
                .font(.system(size: 13))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.black.opacity(0.10), lineWidth: 1)
                )
                .frame(height: 128)
        }
    }

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("译文")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                Text(translationText)
                    .font(.system(size: 13))
                    .foregroundColor(viewModel.translatedText.isEmpty ? Color.secondary : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.86))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
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
                .font(.system(size: 11))
                .foregroundColor(viewModel.errorMessage == nil ? .secondary : .red)
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

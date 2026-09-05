import AppKit
import SwiftUI
import Translation

struct TranslationPanelView: View {
    @ObservedObject private var providers = AIModelSwitcherViewModel.shared
    @ObservedObject var viewModel: TranslationPanelViewModel
    let onTranslate: () -> Void
    let onSelectService: (TranslationServiceType) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header — 可拖拽
            header

            Divider()

            // 内容区
            VStack(alignment: .leading, spacing: 12) {
                languageBar
                sourceSection
                translationSection
                statusBar
                actionBar
            }
            .padding(16)
        }
        .translationTask(viewModel.appleTranslationConfiguration) { session in
            await viewModel.translateWithAppleSession(session)
        }
        .frame(minWidth: 520, maxWidth: 560, minHeight: 420, maxHeight: 700)
        .oneBoardPanelStyle()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(OneBoardColors.accent)
            Text("翻译")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker("翻译服务 / API Key", selection: Binding(
                get: { viewModel.translationServiceType == .deepSeek ? viewModel.selectedProviderID : viewModel.translationServiceType.rawValue },
                set: { value in
                    if value == "apple" { onSelectService(.apple) }
                    else if value == "google" { onSelectService(.google) }
                    else { Task { await viewModel.selectProvider(value) } }
                }
            )) {
                Text("Apple").tag("apple")
                Text("Google").tag("google")
                Text("选择 API Key").tag("").disabled(true)
                ForEach(providers.profiles.filter { $0.kind == .custom && providers.hasSavedAPIKey(for: $0) }) { profile in
                    Text("\(profile.title) · \(profile.client.title)").tag(profile.id.uuidString)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 260, height: 24)
            .disabled(viewModel.isTranslating)
            OneBoardCloseButton(action: onClose)
                .frame(width: 24, height: 24)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(Rectangle().fill(OneBoardColors.headerBorder).frame(height: 1), alignment: .bottom)
        .background(TranslationPanelDragHandle())
    }

    // MARK: - Language Bar

    private var languageBar: some View {
        HStack(spacing: 8) {
            Picker("源语言", selection: $viewModel.sourceLanguage) {
                ForEach(TranslationLanguage.sourceOptions) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .disabled(viewModel.isTranslating)

            Button {
                viewModel.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.sourceLanguage == .auto || viewModel.isTranslating)
            .help("交换语言")

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundColor(OneBoardColors.textTertiary)

            Picker("目标语言", selection: $viewModel.targetLanguage) {
                ForEach(TranslationLanguage.targetOptions) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .disabled(viewModel.isTranslating)

            Spacer()
        }
    }

    // MARK: - Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("原文")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(OneBoardColors.textTertiary)
                    .textCase(.uppercase)
                Spacer()
                if !viewModel.sourceText.isEmpty {
                    Button("清空") { viewModel.clearSourceText() }
                        .buttonStyle(.borderless)
                        .font(.system(size: 10))
                        .foregroundColor(OneBoardColors.textTertiary)
                }
            }
            TextEditor(text: $viewModel.sourceText)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .background(OneBoardColors.background)
                .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                        .stroke(OneBoardColors.borderSubtle, lineWidth: 1)
                )
                .frame(minHeight: 100)
        }
    }

    // MARK: - Translation

    private var translationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("译文")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(OneBoardColors.textTertiary)
                .textCase(.uppercase)

            if viewModel.isTranslating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("正在翻译...")
                        .font(.system(size: 13))
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                .background(OneBoardColors.background)
                .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                        .stroke(OneBoardColors.borderSubtle, lineWidth: 1)
                )
            } else {
                ScrollView {
                    Text(displayedTranslation)
                        .font(.system(size: 14))
                        .foregroundColor(viewModel.translatedText.isEmpty ? OneBoardColors.textTertiary : OneBoardColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .background(OneBoardColors.background)
                .clipShape(RoundedRectangle(cornerRadius: OneBoardRadius.lg))
                .overlay(
                    RoundedRectangle(cornerRadius: OneBoardRadius.lg)
                        .stroke(OneBoardColors.borderSubtle, lineWidth: 1)
                )
                .frame(minHeight: 100)
            }
        }
    }

    private var displayedTranslation: String {
        viewModel.translatedText.isEmpty ? "翻译结果将显示在这里" : viewModel.translatedText
    }

    // MARK: - Status

    private var statusBar: some View {
        Group {
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(OneBoardColors.destructive)
                    .lineLimit(2)
            } else {
                Text(serviceHint)
                    .font(.system(size: 10))
                    .foregroundColor(OneBoardColors.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var serviceHint: String {
        switch viewModel.translationServiceType {
        case .apple: return "使用系统翻译 · 支持离线"
        case .google: return "Google 翻译 · 免费、无需 API Key"
        case .deepSeek: return "已配置 API · 使用所选供应商的默认模型"
        }
    }

    // MARK: - Actions

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: onTranslate) {
                Label("翻译", systemImage: "arrow.clockwise")
            }
            .oneBoardPrimaryButton()
            .disabled(viewModel.isTranslating || !hasSourceText)

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(viewModel.sourceText, forType: .string)
            } label: {
                Label("复制原文", systemImage: "doc.on.doc")
            }
            .oneBoardSecondaryButton()
            .disabled(viewModel.sourceText.isEmpty)

            Button {
                viewModel.copyTranslatedText()
            } label: {
                Label("复制译文", systemImage: "doc.on.clipboard")
            }
            .oneBoardSecondaryButton()
            .disabled(viewModel.translatedText.isEmpty)
        }
    }

    private var hasSourceText: Bool {
        !viewModel.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

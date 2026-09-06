import AppKit
import SwiftUI

struct CodexOAuthAccountView: View {
    @ObservedObject var viewModel: CodexAccountViewModel
    let onClose: () -> Void
    var onAuthorized: ((UUID) -> Void)? = nil

    @State private var email = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("添加 Codex 账号", systemImage: "person.crop.circle.badge.plus")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
            }

            SettingsForm {
                Section("待授权账号") {
                    LabeledContent("OpenAI 账号邮箱") { TextField("OpenAI 账号邮箱", text: $email).labelsHidden() }
                        .textContentType(.emailAddress)
                        .disabled(viewModel.isAuthorizing)
                }

                Section {
                    Text("点击下方按钮后，在浏览器中完成 OpenAI 账号 OAuth 授权。密码和验证码只在 OpenAI 官方页面输入。")
                        .font(.callout)
                        .foregroundColor(SettingsPalette.muted)

                    Button {
                        Task {
                            if await viewModel.authorizeAccount(email: email) {
                                if let id = viewModel.lastAuthorizedAccountID { onAuthorized?(id) }
                                onClose()
                            }
                        }
                    } label: {
                        HStack {
                            if viewModel.isAuthorizing {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "globe")
                            }
                            Text(viewModel.isAuthorizing ? "等待浏览器授权…" : "在浏览器中打开")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isAuthorizing || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if let url = viewModel.authorizationURL {
                        LabeledContent("授权链接") {
                            HStack(spacing: 8) {
                                Text(url.absoluteString)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .font(.caption.monospaced())
                                    .foregroundColor(SettingsPalette.muted)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    Text("OAuth 授权")
                }
            }

            if let status = viewModel.statusMessage {
                Text(status)
                    .font(.caption)
                    .foregroundColor(SettingsPalette.muted)
            }

            HStack {
                Spacer()
                Button(viewModel.isAuthorizing ? "取消授权" : "取消", action: close)
            }
        }
        .padding(24)
        .background(SettingsBackdrop())
        .textFieldStyle(.roundedBorder)
        .tint(SettingsPalette.accent)
        .frame(width: 560, height: 430)
    }

    private func close() {
        if viewModel.isAuthorizing {
            viewModel.cancelAuthorization()
        }
        onClose()
    }
}

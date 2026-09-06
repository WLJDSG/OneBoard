import AppKit
import SwiftUI

struct ClaudeOAuthAccountView: View {
    @StateObject private var authorization = ClaudeAccountAuthorization()
    @State private var email = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    let onSave: (ClaudeAccountCredential) -> Void
    let onCancel: () -> Void
    var accountName: Binding<String>? = nil

    private var waiting: Bool { authorization.authorizationURL != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("添加 Claude Code 账号", systemImage: "person.crop.circle.badge.plus")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
            SettingsForm {
                Section("待授权账号") {
                    LabeledContent("Claude 账号邮箱") {
                        TextField("Claude 账号邮箱", text: accountName ?? $email).labelsHidden()
                    }.textContentType(.emailAddress).disabled(waiting || busy)
                }
                Section {
                    Text("点击下方按钮后，在浏览器中完成 Claude 账号 OAuth 授权。密码和验证码只在 Claude 官方页面输入。")
                        .font(.callout).foregroundColor(SettingsPalette.muted)
                    Button(action: begin) {
                        HStack {
                            if waiting { ProgressView().controlSize(.small) }
                            else { Image(systemName: "globe") }
                            Text(waiting ? "等待浏览器授权…" : "在浏览器中打开")
                                .frame(maxWidth: .infinity)
                        }
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(waiting || busy || (accountName?.wrappedValue ?? email).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let url = authorization.authorizationURL {
                        LabeledContent("授权链接") {
                            HStack(spacing: 8) {
                                Text(url.absoluteString).lineLimit(1).truncationMode(.middle)
                                    .font(.caption.monospaced()).foregroundColor(SettingsPalette.muted)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless).help("复制授权链接")
                            }
                        }
                        Text("完成浏览器授权后，将完成页提供的授权码粘贴到下方。")
                            .font(.caption).foregroundColor(SettingsPalette.muted)
                        LabeledContent("授权码") {
                            SecureField("粘贴授权码或回调地址", text: $code).labelsHidden().disabled(busy)
                        }
                    }
                } header: { Text("OAuth 授权") }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(waiting ? "取消授权" : "取消", action: close)
                if waiting {
                    Button(busy ? "正在验证…" : "完成授权") {
                        busy = true
                        error = nil
                        Task {
                            defer { busy = false }
                            do { onSave(try await authorization.complete(code)) }
                            catch is CancellationError {}
                            catch { self.error = error.localizedDescription }
                        }
                    }.buttonStyle(SettingsActionStyle(prominent: true)).disabled(busy || code.isEmpty)
                }
            }
        }
        .padding(24).background(SettingsBackdrop()).textFieldStyle(.roundedBorder)
        .tint(SettingsPalette.accent).frame(width: 560, height: waiting ? 540 : 430)
        .onDisappear { authorization.cancel() }
    }

    private func begin() {
        error = nil
        do {
            try authorization.begin()
            if let url = authorization.authorizationURL, !NSWorkspace.shared.open(url) {
                error = "无法打开浏览器，请复制授权链接后打开"
            }
        } catch { self.error = error.localizedDescription }
    }

    private func close() {
        authorization.cancel()
        onCancel()
    }
}

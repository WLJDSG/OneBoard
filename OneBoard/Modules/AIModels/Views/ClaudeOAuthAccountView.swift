import SwiftUI

struct ClaudeOAuthAccountView: View {
    @StateObject private var authorization = ClaudeAccountAuthorization()
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    let onSave: (ClaudeAccountCredential) -> Void
    let onCancel: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("添加 Claude Code 官方账号", systemImage: "person.crop.circle.badge.plus").font(.title3.bold())
            Text("在官方页面完成登录，再将授权完成页返回的授权码粘贴到下方。")
                .foregroundStyle(.secondary)
            Button("在浏览器中打开") {
                do {
                    try authorization.begin()
                    if let url = authorization.authorizationURL, !NSWorkspace.shared.open(url) {
                        error = "无法打开浏览器，请复制授权链接后打开"
                    }
                } catch { self.error = error.localizedDescription }
            }.disabled(busy)
            if let url = authorization.authorizationURL {
                Button("复制授权链接") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string) }
                SecureField("粘贴授权码或回调地址", text: $code).textFieldStyle(.roundedBorder)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消") { authorization.cancel(); onCancel() }
                Button(busy ? "正在验证…" : "完成授权") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { onSave(try await authorization.complete(code)) }
                        catch { self.error = error.localizedDescription }
                    }
                }.buttonStyle(SettingsActionStyle(prominent: true))
                    .disabled(busy || code.isEmpty || authorization.authorizationURL == nil)
            }
        }.padding(24).frame(width: 540).background(SettingsBackdrop())
            .onDisappear { authorization.cancel() }
    }
}

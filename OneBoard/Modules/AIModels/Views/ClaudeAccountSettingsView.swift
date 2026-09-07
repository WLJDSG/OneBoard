import SwiftUI

/// 与 AI 模型页共用官方配置及 SQLite 凭据，避免同一账号出现两份状态。
struct ClaudeAccountSettingsView: View {
    @ObservedObject private var model = AIModelSwitcherViewModel.shared
    @State private var showingLogin = false
    @State private var reauthorizing: AIProviderProfile?
    @State private var editing: AIProviderProfile?
    @State private var deleting: AIProviderProfile?
    @State private var accountName = ""
    @State private var error: String?

    private var accounts: [AIProviderProfile] {
        model.profiles(for: .claude).filter { $0.kind == .official && $0.officialAccountID != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("已连接 \(accounts.count) 个账号").foregroundStyle(.secondary)
                Spacer()
                Button { accountName = ""; reauthorizing = nil; showingLogin = true } label: {
                    Label("添加账号", systemImage: "plus")
                }.buttonStyle(SettingsActionStyle(prominent: true))
            }
            .padding(.horizontal, InterfaceMetrics.pageInset)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if accounts.isEmpty {
                        SettingsCard {
                            VStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 30)).foregroundStyle(SettingsPalette.accent)
                                Text("连接 Claude Code 官方账号").font(.headline)
                                Text("通过官方浏览器授权添加账号，之后可在这里切换和管理。")
                                    .font(.callout).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity).padding(32)
                        }
                    }
                    ForEach(accounts) { account in
                        SettingsCard {
                            HStack(spacing: 14) {
                                Image(systemName: "person.crop.circle")
                                    .font(.system(size: 24)).foregroundStyle(SettingsPalette.accent)
                                    .frame(width: 46, height: 46)
                                    .background(SettingsPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(account.title).font(.headline)
                                    Text(account.model).font(.caption).foregroundStyle(.secondary)
                                    if let note = account.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                if model.activeID(for: .claude) == account.id {
                                    Label("当前账号", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(SettingsPalette.teal)
                                } else {
                                    Button("切换") {
                                        Task {
                                            let result = await model.switchProfile(id: account.id)
                                            error = model.activeID(for: .claude) == account.id ? nil : result
                                        }
                                    }
                                        .buttonStyle(SettingsActionStyle()).disabled(model.isSwitching)
                                }
                                Menu {
                                    Button("编辑名称与模型") { editing = account }
                                    Button("重新授权") { reauthorizing = account; accountName = account.title; showingLogin = true }
                                    Divider()
                                    Button("删除账号", role: .destructive) { deleting = account }
                                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                                .menuStyle(.borderlessButton).fixedSize()
                            }.padding(20)
                        }
                    }
                    Text("切换后请新建 Claude Code 会话，已运行的终端会话会继续使用原来的凭据。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let message = error {
                        Text(message).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(.horizontal, InterfaceMetrics.pageInset).padding(.bottom, 28)
            }.scrollIndicators(.hidden)
        }
        .sheet(isPresented: $showingLogin) {
                ClaudeOAuthAccountView(onSave: { credential in
                    Task {
                        do {
                            var profile = reauthorizing ?? AIProviderProfile(client: .claude, kind: .official, title: "Claude Code", model: "sonnet")
                            let name = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !name.isEmpty { profile.title = name }
                            profile.officialAccountID = profile.officialAccountID ?? profile.id
                            try ClaudeAccountCredentialStore().save(credential, id: profile.officialAccountID!)
                            try await model.save(profile, apiKey: nil)
                            showingLogin = false
                            error = nil
                        } catch { self.error = error.localizedDescription; showingLogin = false }
                    }
                }, onCancel: { showingLogin = false }, accountName: $accountName)
        }
        .sheet(item: $editing) { profile in
            AIProviderEditorView(client: .claude, profile: profile, savedAPIKey: nil,
                onSave: { value, key in try await model.save(value, apiKey: key); editing = nil },
                onSaveAndSwitch: { value, key in try await model.saveAndSwitch(value, apiKey: key); editing = nil },
                onCancel: { editing = nil })
        }
        .alert("删除 Claude Code 账号？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) { if let account = deleting { model.delete(account) }; deleting = nil }
        } message: {
            Text("移除 OneBoard 中保存的账号与授权。已经写入 Claude Code 的活动配置会保留。")
        }
    }
}

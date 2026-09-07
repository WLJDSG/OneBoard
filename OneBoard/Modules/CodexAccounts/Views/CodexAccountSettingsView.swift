import SwiftUI

struct CodexAccountSettingsView: View {
    @StateObject private var viewModel = CodexAccountViewModel.shared
    @State private var isAddingAccount = false
    @State private var editingProfile: CodexAccountProfile?
    @State private var deletingProfile: CodexAccountProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已保存 \(viewModel.profiles.count) 个账号").font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                Button { isAddingAccount = true } label: { Label("添加账号", systemImage: "plus") }
                    .buttonStyle(SettingsActionStyle(prominent: true))
            }.padding(.horizontal, InterfaceMetrics.pageInset)
            SettingsForm {
                Section {
                    LabeledContent("Codex 状态", value: viewModel.isCodexRunning ? "正在运行" : "未运行")
                    LabeledContent("当前账号", value: viewModel.activeProfile?.title ?? "尚未保存")
                    LabeledContent("登录凭据", value: viewModel.hasCurrentAuthCache ? "已检测到" : "未检测到")

                    if viewModel.activeProfile != nil {
                        Button("更新当前账号凭据") {
                            viewModel.refreshActiveAuthCache()
                        }
                        .disabled(!viewModel.hasCurrentAuthCache)
                    }
                } header: {
                    Text("账号授权")
                } footer: {
                    Text("填写账号邮箱后打开 Codex 官方授权页。OneBoard 不会读取或保存密码和验证码。")
                }

                Section {
                    if profilesAreEmpty {
                        Text("还没有保存 Codex 账号")
                            .foregroundColor(SettingsPalette.muted)
                    } else {
                        SettingsReorderList(items: viewModel.profiles, title: { $0.title }, onCommit: { viewModel.reorderAccounts($0) }) { profile in
                            accountRow(profile)
                        }
                    }
                } header: {
                    HStack {
                        Text("已保存账号")
                        Spacer()
                        Button {
                            Task { await viewModel.refreshAllAccountStatuses() }
                        } label: {
                            Label("刷新额度", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SettingsActionStyle())
                        .disabled(!viewModel.refreshingAccountIDs.isEmpty)
                    }
                } footer: {
                    Text("点击切换后，OneBoard 会先退出 Codex，确认旧进程完全结束后替换认证缓存，再自动重新打开。")
                }

                if let pendingProfile = viewModel.pendingProfile {
                    Section {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在切换到 \(pendingProfile.title)")
                            Spacer()
                        }
                    } header: {
                        Text("正在切换")
                    }
                }
            }

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundColor(SettingsPalette.muted)
                    .padding(.horizontal)
            }
        }
        .onAppear { viewModel.refreshState() }
        .sheet(isPresented: $isAddingAccount) {
            CodexOAuthAccountView(
                viewModel: viewModel,
                onClose: { isAddingAccount = false }
            )
        }
        .sheet(item: $editingProfile) { profile in
            CodexAccountEditorView(
                viewModel: CodexAccountEditorViewModel(profile: profile),
                onSave: { title in
                    viewModel.updateProfile(id: profile.id, title: title)
                    editingProfile = nil
                },
                onCancel: { editingProfile = nil }
            )
        }
        .alert("删除 Codex 账号？", isPresented: deleteAlertBinding, presenting: deletingProfile) { profile in
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                viewModel.deleteAccount(id: profile.id)
                deletingProfile = nil
            }
        } message: { profile in
            Text("将删除“\(profile.title)”及其数据库登录凭据。仅切换账号时才会退出并重新打开 Codex。")
        }
    }

    private var profilesAreEmpty: Bool {
        viewModel.profiles.isEmpty
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingProfile != nil },
            set: { if !$0 { deletingProfile = nil } }
        )
    }

    private func accountRow(_ profile: CodexAccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: viewModel.activeAccountID == profile.id ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                    .font(.system(size: 23))
                    .frame(width: 44, height: 44)
                    .background(SettingsPalette.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                    .foregroundColor(viewModel.activeAccountID == profile.id ? OneBoardColors.success : SettingsPalette.muted)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(profile.title).font(.system(size: 15, weight: .semibold))
                        if let planType = profile.planType, !planType.isEmpty {
                            Text(planType.uppercased())
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(SettingsPalette.accent.opacity(0.12), in: Capsule())
                                .foregroundColor(SettingsPalette.accent)
                        }
                    }
                    if let email = profile.email, email != profile.title {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(SettingsPalette.muted)
                    }
                    Text("凭据更新于 \(profile.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(SettingsPalette.muted)
                }

                Spacer()

                if viewModel.refreshingAccountIDs.contains(profile.id) {
                    ProgressView().controlSize(.small)
                } else if viewModel.pendingAccountID == profile.id {
                    Text("切换中")
                        .font(.caption)
                        .foregroundColor(SettingsPalette.accent)
                } else if viewModel.activeAccountID == profile.id {
                    Text("当前")
                        .font(.caption)
                        .foregroundColor(OneBoardColors.success)
                }

                Button("切换") {
                    Task { await viewModel.requestSwitch(id: profile.id) }
                }
                    .disabled(viewModel.activeAccountID == profile.id || viewModel.isSwitching)
                Button("编辑") { editingProfile = profile }
                    .disabled(viewModel.isSwitching)
                Button(role: .destructive) {
                    deletingProfile = profile
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isSwitching)
            }

            if let status = profile.status {
                HStack(spacing: 18) {
                    if let window = status.fiveHour { usageMeter(title: "5 小时", window: window) }
                    if let window = status.weekly { usageMeter(title: "每周", window: window) }
                }

                HStack(spacing: 18) {
                    Label(subscriptionText(status.subscriptionActiveUntil), systemImage: "calendar")
                    Label(resetCreditText(status.resetCreditsAvailable), systemImage: "arrow.counterclockwise.circle")
                    Spacer()
                    Text("更新于 \(status.fetchedAt.formatted(date: .omitted, time: .shortened))")
                }
                .font(.caption)
                .foregroundColor(SettingsPalette.muted)
            }

            if let error = profile.statusError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(OneBoardColors.warning)
            }
        }
    }

    private func usageMeter(title: String, window: CodexUsageWindowSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold))
                Spacer()
                Text("\(window.remainingPercent)%")
                    .font(.caption.monospacedDigit())
            }
            ProgressView(value: Double(window.remainingPercent), total: 100)
            Text(window.resetAt.map { "重置：\($0.formatted(date: .abbreviated, time: .shortened))" } ?? "重置时间未知")
                .font(.caption2)
                .foregroundColor(SettingsPalette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(15)
        .background(SettingsPalette.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private func subscriptionText(_ date: Date?) -> String {
        guard let date else { return "订阅到期时间未知" }
        return "订阅至 \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private func resetCreditText(_ count: Int?) -> String {
        count.map { "剩余重置 \($0) 次" } ?? "重置次数未知"
    }
}

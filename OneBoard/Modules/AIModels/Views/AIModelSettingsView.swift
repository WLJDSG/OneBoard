import SwiftUI

struct AIModelSettingsView: View {
    @StateObject private var viewModel = AIModelSwitcherViewModel.shared
    @State private var selectedClient: AIClient = .codex
    @State private var editingProfile: AIProviderProfile?
    @State private var isAddingProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("工具", selection: $selectedClient) {
                ForEach(AIClient.allCases) { client in
                    Label(client.title, systemImage: client.systemImage).tag(client)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Form {
                Section {
                    if viewModel.profiles(for: selectedClient).isEmpty {
                        Text("暂无配置，请先新增官方或自定义 API 配置。")
                            .foregroundColor(OneBoardColors.textSecondary)
                    }
                    ForEach(viewModel.profiles(for: selectedClient)) { profile in
                        profileRow(profile)
                    }
                    Button {
                        isAddingProfile = true
                    } label: {
                        Label("新增模型配置", systemImage: "plus")
                    }
                } header: {
                    Text("\(selectedClient.title) 供应商")
                }

                Section {
                    Button {
                        viewModel.importFromCCSwitch()
                    } label: {
                        Label("从 CC Switch 导入", systemImage: "square.and.arrow.down")
                    }
                    Button("恢复初次切换前备份") {
                        viewModel.restoreBackup(for: selectedClient)
                    }
                    .disabled(viewModel.isSwitching)
                } footer: {
                    Text(backupHelp)
                        .font(.caption)
                        .foregroundColor(OneBoardColors.textSecondary)
                }
            }
            .formStyle(.grouped)

            if let message = viewModel.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                    .padding(.horizontal)
            }
        }
        .padding()
        .sheet(isPresented: $isAddingProfile) {
            AIProviderEditorView(client: selectedClient, profile: nil) { profile, key in
                try viewModel.save(profile, apiKey: key)
                isAddingProfile = false
            } onCancel: {
                isAddingProfile = false
            }
        }
        .sheet(item: $editingProfile) { profile in
            AIProviderEditorView(client: profile.client, profile: profile) { updated, key in
                try viewModel.save(updated, apiKey: key)
                editingProfile = nil
            } onCancel: {
                editingProfile = nil
            }
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: AIProviderProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: profile.kind == .official ? "building.columns" : "point.3.connected.trianglepath.dotted")
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.title)
                Text(profile.kind == .official ? profile.model : "\(profile.model) · \(profile.baseURL)")
                    .font(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            if viewModel.activeID(for: selectedClient) == profile.id {
                Image(systemName: "checkmark.circle.fill").foregroundColor(OneBoardColors.success)
            }
            Button("切换") { viewModel.switchProfile(id: profile.id) }
                .disabled(viewModel.isSwitching || viewModel.activeID(for: selectedClient) == profile.id)
            Button("编辑") { editingProfile = profile }
            Button(role: .destructive) { viewModel.delete(profile) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var backupHelp: String {
        switch selectedClient {
        case .codex:
            return "切换会合并修改 ~/.codex/config.toml，不改动账号认证缓存。第三方 API Key 从 OneBoard SQLite 读取，并按 Codex 格式写入当前活动配置。"
        case .claude:
            return "切换会保留 ~/.claude/settings.json 的未知字段，仅更新 Anthropic API 和模型环境变量。"
        }
    }
}

private struct AIProviderEditorView: View {
    let client: AIClient
    let profile: AIProviderProfile?
    let onSave: (AIProviderProfile, String?) throws -> Void
    let onCancel: () -> Void

    @State private var kind: AIProviderKind
    @State private var title: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiKey = ""
    @State private var keyField: ClaudeAPIKeyField
    @State private var haikuModel: String
    @State private var sonnetModel: String
    @State private var opusModel: String
    @State private var errorMessage: String?

    init(
        client: AIClient,
        profile: AIProviderProfile?,
        onSave: @escaping (AIProviderProfile, String?) throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.client = client
        self.profile = profile
        self.onSave = onSave
        self.onCancel = onCancel
        _kind = State(initialValue: profile?.kind ?? .custom)
        _title = State(initialValue: profile?.title ?? "")
        _baseURL = State(initialValue: profile?.baseURL ?? "")
        _model = State(initialValue: profile?.model ?? "")
        _keyField = State(initialValue: profile?.claudeAPIKeyField ?? .authToken)
        _haikuModel = State(initialValue: profile?.claudeHaikuModel ?? "")
        _sonnetModel = State(initialValue: profile?.claudeSonnetModel ?? "")
        _opusModel = State(initialValue: profile?.claudeOpusModel ?? "")
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(profile == nil ? "新增 \(client.title) 配置" : "编辑 \(client.title) 配置")
                .font(.title3.weight(.semibold))
            Form {
                Picker("类型", selection: $kind) {
                    ForEach(AIProviderKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                TextField("名称", text: $title)
                TextField("模型 ID", text: $model)
                if kind == .custom {
                    TextField("API 地址", text: $baseURL)
                    SecureField(profile == nil ? "API Key" : "API Key（留空则保留原值）", text: $apiKey)
                    if client == .claude {
                        Picker("密钥字段", selection: $keyField) {
                            ForEach(ClaudeAPIKeyField.allCases) { field in Text(field.title).tag(field) }
                        }
                        TextField("Haiku 模型（可选）", text: $haikuModel)
                        TextField("Sonnet 模型（可选）", text: $sonnetModel)
                        TextField("Opus 模型（可选）", text: $opusModel)
                    }
                }
            }
            .formStyle(.grouped)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
    }

    private func save() {
        do {
            let now = Date()
            let value = AIProviderProfile(
                id: profile?.id ?? UUID(),
                client: client,
                kind: kind,
                title: title,
                baseURL: baseURL,
                model: model,
                claudeAPIKeyField: keyField,
                claudeHaikuModel: haikuModel,
                claudeSonnetModel: sonnetModel,
                claudeOpusModel: opusModel,
                sourceIdentifier: profile?.sourceIdentifier,
                createdAt: profile?.createdAt ?? now,
                updatedAt: now
            )
            try onSave(value, apiKey.isEmpty ? nil : apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

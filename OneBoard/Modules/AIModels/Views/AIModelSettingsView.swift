import SwiftUI

struct AIModelSettingsView: View {
    @StateObject private var viewModel = AIModelSwitcherViewModel.shared
    @StateObject private var codexAccountViewModel = CodexAccountViewModel.shared
    @StateObject private var usageViewModel = AIUsageViewModel()
    @State private var selectedClient: AIClient = .codex
    @State private var editingProfile: AIProviderProfile?
    @State private var isAddingProfile = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 4) {
                    ForEach(AIClient.allCases) { client in
                        Button { selectedClient = client } label: {
                            Label(client.title, systemImage: client.systemImage)
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 17).padding(.vertical, 10)
                                .foregroundStyle(selectedClient == client ? SettingsPalette.accent : .secondary)
                                .background(selectedClient == client ? SettingsPalette.accent.opacity(0.09) : .clear,
                                            in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(.background, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.05)))
                Spacer()
                Button { isAddingProfile = true } label: {
                    Label("添加供应商", systemImage: "plus")
                }.buttonStyle(SettingsActionStyle(prominent: true))
            }
            .padding(.horizontal, 28)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("供应商").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Text("\(viewModel.profiles(for: selectedClient).count)")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Color.primary.opacity(0.045), in: Capsule())
                        Spacer()
                        Button {
                            Task {
                                async let official: Void = codexAccountViewModel.refreshAllAccountStatuses()
                                await usageViewModel.refresh(viewModel.profiles)
                                await official
                            }
                        } label: {
                            Label(usageViewModel.isRefreshing ? "正在刷新…" : "刷新额度与用量", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(SettingsPalette.accent)
                        .disabled(usageViewModel.isRefreshing || !codexAccountViewModel.refreshingAccountIDs.isEmpty)
                    }
                    .padding(.horizontal, 4)
                    if viewModel.profiles(for: selectedClient).isEmpty {
                        SettingsCard {
                            VStack(spacing: 12) {
                                Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(SettingsPalette.accent)
                                Text("连接你的第一个供应商").font(.headline)
                                Text("添加 API Key，开始管理模型、额度与用量。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("添加供应商") { isAddingProfile = true }
                                    .buttonStyle(SettingsActionStyle(prominent: true))
                            }.frame(maxWidth: .infinity).padding(36)
                        }
                    }
                    SettingsReorderList(items: viewModel.profiles(for: selectedClient), title: { $0.title }, onCommit: { ids in
                        viewModel.reorderProfiles(ids, client: selectedClient)
                    }) { profile in profileRow(profile) }
                    .id(selectedClient)
                    if let message = viewModel.statusMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack(spacing: 14) {
                        Button { viewModel.importFromCCSwitch() } label: {
                            Label("从 CC Switch 导入", systemImage: "square.and.arrow.down")
                        }
                        Spacer()
                    }
                    .buttonStyle(SettingsActionStyle())
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }.scrollIndicators(.hidden)
        }
        .onAppear { codexAccountViewModel.refreshState() }
        .task { await usageViewModel.refresh(viewModel.profiles) }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            usageViewModel.loadLocal(viewModel.profiles)
        }
        .sheet(isPresented: $isAddingProfile) {
            AIProviderEditorView(client: selectedClient, profile: nil, savedAPIKey: nil) { profile, key in
                try await viewModel.save(profile, apiKey: key)
                isAddingProfile = false
            } onSaveAndSwitch: { profile, key in
                try await viewModel.saveAndSwitch(profile, apiKey: key)
                isAddingProfile = false
            } onCancel: {
                isAddingProfile = false
            }
        }
        .sheet(item: $editingProfile) { profile in
            AIProviderEditorView(
                client: profile.client,
                profile: profile,
                savedAPIKey: viewModel.savedAPIKey(for: profile)
            ) { updated, key in
                try await viewModel.save(updated, apiKey: key)
                editingProfile = nil
            } onSaveAndSwitch: { updated, key in
                try await viewModel.saveAndSwitch(updated, apiKey: key)
                editingProfile = nil
            } onCancel: {
                editingProfile = nil
            }
        }
    }

    private func profileRow(_ profile: AIProviderProfile) -> some View {
        AIProviderSettingsCard(
            profile: profile,
            active: viewModel.activeID(for: selectedClient) == profile.id,
            switching: viewModel.isSwitching,
            snapshot: usageViewModel.snapshots[profile.id],
            error: usageViewModel.errors[profile.id],
            today: usageViewModel.localToday[profile.id],
            total: usageViewModel.localTotal[profile.id],
            officialQuota: AIProviderQuotaPresentation.make(profile: profile, activeCodexAccount: profile.officialAccountID == nil ? codexAccountViewModel.activeProfile : codexAccountViewModel.profiles.first { $0.id == profile.officialAccountID }),
            onSwitch: { Task { await viewModel.switchProfile(id: profile.id) } },
            onEdit: { editingProfile = profile },
            onDelete: { viewModel.delete(profile) }
        )
    }

}

struct AIProviderEditorView: View {
    let allowsSwitch: Bool
    let client: AIClient
    let profile: AIProviderProfile?
    let onSave: (AIProviderProfile, String?) async throws -> Void
    let onSaveAndSwitch: (AIProviderProfile, String?) async throws -> Void
    let onCancel: () -> Void

    @State private var showOfficialLogin = false
    @State private var officialAccountID: UUID?
    @State private var claudeCredential: ClaudeAccountCredential?
    @StateObject private var accounts = CodexAccountViewModel.shared
    @State private var kind: AIProviderKind
    @State private var title: String
    @State private var note: String
    @State private var websiteURL: String
    @State private var baseURL: String
    @State private var model: String
    @State private var quotaAPI: AIQuotaAPI
    @State private var apiFormat: AIUpstreamAPIFormat
    @State private var selectedPresetID: String
    @State private var automaticQuota: Bool
    @State private var quotaURL: String
    private var selectedPreset: AIProviderPreset? { AIProviderPreset.find(selectedPresetID) }
    private var isFullURL: Bool { AIEndpointResolver.isComplete(baseURL) || (profile?.isFullURL == true && profile?.baseURL == baseURL) }
    @State private var customUserAgent: String
    @State private var requestHeadersJSON: String
    @State private var requestBodyJSON: String
    @State private var promptCacheKey: String
    @State private var promptCacheRouting: AIPromptCacheRouting
    @State private var impersonateClaudeCode: Bool
    @State private var maxOutputTokens: String
    @State private var endpointAutoSelect: Bool
    @State private var customEndpointsText: String
    @State private var endpointTestMessage: String?
    @State private var isTestingEndpoint = false
    @State private var discoveredModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelRequestID = UUID()
    @State private var isSaving = false
    @State private var apiKey: String
    @State private var isAPIKeyVisible = false
    @State private var isAdvancedExpanded = false
    @State private var isProxyAdvancedExpanded = false
    @State private var keyField: ClaudeAPIKeyField
    @State private var haikuModel: String
    @State private var haikuModelName: String
    @State private var sonnetModel: String
    @State private var sonnetModelName: String
    @State private var opusModel: String
    @State private var opusModelName: String
    @State private var fableModel: String
    @State private var fableModelName: String
    @State private var subagentModel: String
    @State private var bulkClaudeModel: String
    @State private var errorMessage: String?

    init(
        client: AIClient,
        profile: AIProviderProfile?,
        savedAPIKey: String?,
        allowsSwitch: Bool = true,
        onSave: @escaping (AIProviderProfile, String?) async throws -> Void,
        onSaveAndSwitch: @escaping (AIProviderProfile, String?) async throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.client = client
        self.allowsSwitch = allowsSwitch
        self.profile = profile
        self.onSave = onSave
        self.onSaveAndSwitch = onSaveAndSwitch
        self.onCancel = onCancel
        _officialAccountID = State(initialValue: profile?.officialAccountID)
        _kind = State(initialValue: profile?.kind ?? .custom)
        _title = State(initialValue: profile?.title ?? "")
        _note = State(initialValue: profile?.note ?? "")
        _websiteURL = State(initialValue: profile?.websiteURL ?? "")
        _baseURL = State(initialValue: profile?.baseURL ?? "")
        _model = State(initialValue: profile?.model ?? "")
        _quotaAPI = State(initialValue: profile?.quotaAPI ?? .auto)
        _apiFormat = State(
            initialValue: profile?.apiFormat
                ?? .recommendedValue(for: client, baseURL: profile?.baseURL ?? "")
        )
        _selectedPresetID = State(initialValue: profile.map { value in
            value.kind == .official ? "official" : (value.presetID ?? AIProviderPreset.matching(value)?.id ?? "custom")
        } ?? "custom")
        _automaticQuota = State(initialValue: profile?.quotaURL == nil)
        _quotaURL = State(initialValue: profile?.quotaURL ?? "")
        _customUserAgent = State(initialValue: profile?.customUserAgent ?? "")
        _requestHeadersJSON = State(initialValue: profile?.requestHeaderOverridesJSON ?? "")
        _requestBodyJSON = State(initialValue: profile?.requestBodyOverridesJSON ?? "")
        _promptCacheKey = State(initialValue: profile?.promptCacheKey ?? "")
        _promptCacheRouting = State(initialValue: profile?.promptCacheRouting ?? .auto)
        _impersonateClaudeCode = State(initialValue: profile?.impersonateClaudeCode ?? false)
        _maxOutputTokens = State(initialValue: profile?.maxOutputTokens.map(String.init) ?? "")
        _endpointAutoSelect = State(initialValue: profile?.endpointAutoSelect ?? false)
        _customEndpointsText = State(initialValue: profile?.customEndpoints?.joined(separator: "\n") ?? "")
        _apiKey = State(initialValue: savedAPIKey ?? "")
        _keyField = State(initialValue: profile?.claudeAPIKeyField ?? .authToken)
        _haikuModel = State(initialValue: profile?.claudeHaikuModel ?? "")
        _haikuModelName = State(initialValue: profile?.claudeHaikuModelName ?? "")
        _sonnetModel = State(initialValue: profile?.claudeSonnetModel ?? "")
        _sonnetModelName = State(initialValue: profile?.claudeSonnetModelName ?? "")
        _opusModel = State(initialValue: profile?.claudeOpusModel ?? "")
        _opusModelName = State(initialValue: profile?.claudeOpusModelName ?? "")
        _fableModel = State(initialValue: profile?.claudeFableModel ?? "")
        _fableModelName = State(initialValue: profile?.claudeFableModelName ?? "")
        _subagentModel = State(initialValue: profile?.claudeSubagentModel ?? "")
        _bulkClaudeModel = State(initialValue: profile?.model ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: client.systemImage)
                    .font(.title2)
                    .foregroundColor(SettingsPalette.accent)
                    .frame(width: 44, height: 44)
                    .background(SettingsPalette.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile == nil ? "新增 \(client.title) 供应商" : "编辑 \(client.title) 供应商")
                        .font(.title3.weight(.semibold))
                    Text("配置供应商连接、鉴权和模型映射")
                        .font(.caption)
                        .foregroundColor(SettingsPalette.muted)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            editorRow("供应商") {
                                Picker("供应商", selection: $selectedPresetID) {
                                    Text("自定义供应商").tag("custom")
                                    Text("官方账号登录（不使用 API Key）").tag("official")
                                    Divider()
                                    ForEach(AIProviderPreset.all) { preset in Text(preset.title).tag(preset.id) }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            editorRow("供应商名称") {
                                TextField("例如：Sub2API-claude", text: $title)
                            }
                            editorRow("备注") {
                                TextField("例如：公司专用账号", text: $note)
                            }
                            editorRow("官网链接") {
                                TextField("https://provider.example", text: $websiteURL)
                            }
                            editorRow("默认模型") {
                                VStack(alignment: .leading, spacing: 5) {
                                    if discoveredModels.isEmpty {
                                        TextField("输入模型 ID", text: $model)
                                        Text(isFetchingModels ? "正在获取模型目录…" : "暂无模型目录，可手动输入模型 ID")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        AIModelComboBox(text: $model, models: discoveredModels).frame(minHeight: 24)
                                        if kind == .official && client == .codex {
                                            Text("来自本机 Codex 缓存目录，实际可用模型以账号为准").font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            if kind == .official {
                                editorRow("官方账号") {
                                    VStack(alignment: .leading, spacing: 8) {
                                        if client == .codex {
                                            Picker("账号", selection: $officialAccountID) {
                                                Text("使用 Codex 当前账号").tag(nil as UUID?)
                                                ForEach(accounts.profiles) { Text($0.title).tag(Optional($0.id)) }
                                            }.labelsHidden()
                                        } else {
                                            Text(claudeCredential != nil || profile?.officialAccountID != nil ? "已保存 Claude Code 授权" : "尚未连接 Claude Code 账号")
                                        }
                                        Button("登录官方账号…") { showOfficialLogin = true }
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("基本信息", systemImage: "info.circle")
                    }

                    if kind == .custom {
                        GroupBox {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                                editorRow("请求地址") {
                                    HStack {
                                        if selectedPreset != nil {
                                            Text(baseURL).font(.callout).textSelection(.enabled)
                                            Spacer()
                                        } else {
                                            TextField("基础地址或完整请求 URL", text: $baseURL)
                                        }
                                        Button(isTestingEndpoint ? "测试中…" : "测速") { testEndpoints() }
                                            .disabled(isTestingEndpoint || baseURL.isEmpty)
                                    }
                                }
                                editorRow("地址识别") {
                                    Text(isFullURL ? "已识别完整请求地址，直接使用" : "已识别基础地址，自动补全请求路径")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                editorRow("额度查询") {
                                    if let preset = selectedPreset {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(preset.quota == .none ? "暂未接入，请在供应商控制台查看" : "已自动配置 " + preset.quota.title)
                                            if let address = presetQuotaURL { Text(address).textSelection(.enabled) }
                                        }.font(.caption).foregroundStyle(.secondary)
                                    } else {
                                        Toggle("自动识别额度接口", isOn: $automaticQuota)
                                    }
                                }
                                if selectedPreset == nil && !automaticQuota {
                                    editorRow("额度地址") {
                                        TextField("https://provider.example/v1/usage", text: $quotaURL)
                                    }
                                    editorRow("响应格式") {
                                        Picker("额度响应格式", selection: $quotaAPI) {
                                            ForEach(AIQuotaAPI.allCases.filter { $0 != .none }) { Text($0.title).tag($0) }
                                        }.labelsHidden()
                                    }
                                    editorRow("查询说明") {
                                        Text("向此地址发送只读 GET 请求，使用当前 API Key 鉴权；自动格式识别支持已接入的额度响应。")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                editorRow("模型目录") {
                                    Button(isFetchingModels ? "获取中…" : "获取模型") { fetchModels() }
                                        .disabled(isFetchingModels || baseURL.isEmpty)
                                }
                                editorRow("API Key") {
                                    HStack(spacing: 8) {
                                        Group {
                                            if isAPIKeyVisible {
                                                TextField("输入供应商 API Key", text: $apiKey)
                                            } else {
                                                SecureField("输入供应商 API Key", text: $apiKey)
                                            }
                                        }
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(apiKey, forType: .string)
                                        } label: { Image(systemName: "doc.on.doc") }
                                        .buttonStyle(.borderless).help("复制 API Key").disabled(apiKey.isEmpty)
                                        Button {
                                            if let value = NSPasteboard.general.string(forType: .string) {
                                                apiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                            }
                                        } label: { Image(systemName: "doc.on.clipboard") }
                                        .buttonStyle(.borderless).help("粘贴 API Key")
                                        Button {
                                            isAPIKeyVisible.toggle()
                                        } label: {
                                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                        }
                                        .buttonStyle(.borderless)
                                        .help(isAPIKeyVisible ? "隐藏 API Key" : "显示 API Key")
                                    }
                                }
                            }

                            if let endpointTestMessage {
                                Text(endpointTestMessage)
                                    .font(.caption)
                                    .foregroundColor(SettingsPalette.muted)
                                    .padding(.top, 4)
                            }
                        } label: {
                            Label("连接与鉴权", systemImage: "key.horizontal")
                        }
                    }

                    if kind == .custom && selectedPreset == nil {
                        GroupBox {
                            DisclosureGroup(isExpanded: $isProxyAdvancedExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                                        editorRow("上游格式") {
                                            apiFormatPicker
                                        }
                                        if client == .claude {
                                            editorRow("鉴权字段") {
                                                Picker("", selection: $keyField) {
                                                    ForEach(ClaudeAPIKeyField.allCases) { field in Text(field.title).tag(field) }
                                                }
                                                .labelsHidden()
                                            }
                                        }
                                        editorRow("User-Agent") {
                                            TextField("留空使用客户端默认值", text: $customUserAgent)
                                        }
                                        editorRow("备用端点") {
                                            TextEditor(text: $customEndpointsText)
                                                .font(.system(.body, design: .monospaced))
                                                .frame(height: 58)
                                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(OneBoardColors.border))
                                        }
                                        editorRow("自动择优") {
                                            Toggle("测速后使用最快可用端点", isOn: $endpointAutoSelect)
                                        }
                                        editorRow("请求头覆盖") {
                                            TextEditor(text: $requestHeadersJSON)
                                                .font(.system(.body, design: .monospaced))
                                                .frame(height: 70)
                                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(OneBoardColors.border))
                                        }
                                        editorRow("请求体覆盖") {
                                            TextEditor(text: $requestBodyJSON)
                                                .font(.system(.body, design: .monospaced))
                                                .frame(height: 70)
                                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(OneBoardColors.border))
                                        }
                                        if apiFormat == .openAIResponses {
                                            editorRow("缓存 Key") {
                                                TextField("可选；覆盖 prompt_cache_key", text: $promptCacheKey)
                                            }
                                        }
                                        if client == .codex {
                                            editorRow("缓存路由") {
                                                promptCacheRoutingPicker
                                            }
                                        }
                                        if client == .codex, apiFormat == .anthropic {
                                            editorRow("模拟 Claude") {
                                                Toggle("注入 Claude Code 请求头与系统提示", isOn: $impersonateClaudeCode)
                                            }
                                            editorRow("最大输出") {
                                                TextField("例如：16384", text: $maxOutputTokens)
                                            }
                                        }
                                    }
                                    Text("仅当供应商要求特殊协议、鉴权字段或请求头时修改。常规连接无需设置请求覆盖；JSON 留空表示不覆盖，备用端点每行一个 URL。")
                                        .font(.caption)
                                        .foregroundColor(SettingsPalette.muted)
                                }
                                .padding(.top, 10)
                            } label: {
                                Text("自定义协议与兼容选项")
                                    .font(.body.weight(.medium))
                            }
                        } label: {
                            Label("高级兼容设置", systemImage: "slider.horizontal.3")
                        }
                    }

                    if client == .claude {
                        claudeModelSettings
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .disabled(isSaving)
                Button("保存") { save(activate: false) }
                    .disabled(isSaving)
                if allowsSwitch {
                Button("保存并切换") { save(activate: true) }
                    .buttonStyle(SettingsActionStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
                }
            }
            .padding(16)
        }
        .background(SettingsBackdrop())
        .groupBoxStyle(SettingsEditorGroupStyle())
        .tint(SettingsPalette.accent)
        .frame(width: client == .claude ? 860 : 780)
        .frame(minHeight: 600, idealHeight: 740, maxHeight: 800)
        .onAppear {
            accounts.refreshState()
            if kind == .official { loadOfficialModels() }
        }
        .task(id: baseURL + apiKey + apiFormat.rawValue + kind.rawValue) {
            guard kind == .custom, !baseURL.isEmpty, !apiKey.isEmpty else { return }
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            fetchModels()
        }
        .sheet(isPresented: $showOfficialLogin) {
            if client == .codex {
                CodexOAuthAccountView(viewModel: accounts, onClose: { showOfficialLogin = false }, onAuthorized: { id in
                    officialAccountID = id
                    title = accounts.profiles.first { $0.id == id }?.title ?? title
                    loadOfficialModels()
                })
            } else {
                ClaudeOAuthAccountView(onSave: { credential in
                    claudeCredential = credential
                    showOfficialLogin = false
                    if model.isEmpty { model = "sonnet" }
                }, onCancel: { showOfficialLogin = false })
            }
        }
        .onChange(of: selectedPresetID) { _, _ in applyPreset() }
        .onChange(of: apiFormat) { _, _ in invalidateModels() }
        .onChange(of: keyField) { _, _ in invalidateModels() }
        .onChange(of: customUserAgent) { _, _ in invalidateModels() }
        .onChange(of: requestHeadersJSON) { _, _ in invalidateModels() }
        .onChange(of: kind) { _, _ in invalidateModels() }
        .onChange(of: apiKey) { _, _ in invalidateModels() }
        .onChange(of: isFullURL) { _, _ in invalidateModels() }
        .onChange(of: baseURL) { _, newValue in
            invalidateModels()
            guard profile?.apiFormat == nil,
                  apiFormat == .defaultValue(for: client) else { return }
            apiFormat = .recommendedValue(for: client, baseURL: newValue)
        }
    }

    @ViewBuilder
    private func editorRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .foregroundColor(SettingsPalette.muted)
                .frame(width: 92, alignment: .leading)
            content()
                .frame(maxWidth: .infinity)
        }
    }

    private var claudeModelSettings: some View {
        GroupBox {
            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("空槽位自动使用默认模型；Fable 为空时优先使用 Opus。模型 ID 可带 [1M] 后缀。")
                        .font(.caption).foregroundColor(SettingsPalette.muted)
                    HStack {
                        Text("模型映射").font(.body.weight(.medium))
                        Spacer()
                        AIModelComboBox(text: $bulkClaudeModel, models: discoveredModels).frame(width: 220).frame(minHeight: 24)
                        Button(action: applyOneModelToAllRoles) { Label("一键设置", systemImage: "wand.and.stars") }
                            .disabled(bulkClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow { Text("模型角色"); Text("显示名称"); Text("实际请求模型"); Text("1M") }
                            .font(.caption.weight(.medium)).foregroundColor(SettingsPalette.muted)
                        modelMappingRow("Sonnet", model: $sonnetModel, name: $sonnetModelName)
                        modelMappingRow("Opus", model: $opusModel, name: $opusModelName)
                        modelMappingRow("Fable", model: $fableModel, name: $fableModelName)
                        modelMappingRow("Haiku", model: $haikuModel, name: $haikuModelName, supportsOneM: false)
                        GridRow { Text("子代理"); Text("不显示在 /model 菜单"); modelSelector($subagentModel); Toggle("", isOn: oneMBinding($subagentModel)).labelsHidden() }
                        GridRow { Divider().gridCellColumns(4) }
                        GridRow { Text("默认兜底"); Text("未匹配角色时使用"); modelSelector($model); Toggle("", isOn: oneMBinding($model)).labelsHidden() }
                    }
                }.padding(.top, 10)
            } label: { Text("高级选项").font(.body.weight(.medium)) }
        } label: { Label("Claude Code 模型槽位", systemImage: "slider.horizontal.3") }
    }

    @ViewBuilder
    private func modelMappingRow(
        _ title: String,
        model: Binding<String>,
        name: Binding<String>,
        supportsOneM: Bool = true
    ) -> some View {
        GridRow {
            Text(title)
                .foregroundColor(SettingsPalette.muted)
                .frame(width: 92, alignment: .leading)
            TextField("显示名（可选）", text: name)
                .frame(minWidth: 150)
            modelSelector(model)
            if supportsOneM {
                Toggle("", isOn: oneMBinding(model))
                    .labelsHidden()
            } else {
                Text("—")
                    .foregroundColor(SettingsPalette.muted)
            }
        }
    }

    private func modelSelector(_ value: Binding<String>) -> some View {
        AIModelComboBox(text: modelBaseBinding(value), models: discoveredModels)
            .frame(minWidth: 180, minHeight: 24)
            .accessibilityLabel("实际请求模型")
    }

    private func invalidateModels() {
        modelRequestID = UUID()
        discoveredModels = []
        isFetchingModels = false
        endpointTestMessage = nil
        if kind == .official { loadOfficialModels() }
    }

    private func applyOneModelToAllRoles() {
        let value = bulkClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let base = Self.stripOneMMarker(value)
        model = value
        sonnetModel = value
        sonnetModelName = base
        opusModel = value
        opusModelName = base
        fableModel = value
        fableModelName = base
        haikuModel = base
        haikuModelName = base
        subagentModel = value
    }

    private func modelBaseBinding(_ value: Binding<String>) -> Binding<String> {
        Binding(
            get: { Self.stripOneMMarker(value.wrappedValue) },
            set: { newValue in
                let usesOneM = Self.hasOneMMarker(value.wrappedValue)
                value.wrappedValue = usesOneM && !newValue.isEmpty ? "\(newValue)[1M]" : newValue
            }
        )
    }

    private func oneMBinding(_ value: Binding<String>) -> Binding<Bool> {
        Binding(
            get: { Self.hasOneMMarker(value.wrappedValue) },
            set: { enabled in
                let base = Self.stripOneMMarker(value.wrappedValue)
                value.wrappedValue = enabled && !base.isEmpty ? "\(base)[1M]" : base
            }
        )
    }

    private static func hasOneMMarker(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("[1M]")
    }

    private static func stripOneMMarker(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix("[1M]") else { return trimmed }
        return String(trimmed.dropLast(4)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save(activate: Bool) {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                if kind == .custom && selectedPreset == nil && !automaticQuota && quotaURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    throw AIModelSwitchError.invalidProfile("请填写额度地址，或勾选自动识别")
                }
                let now = Date()
                var value = AIProviderProfile(
                    id: profile?.id ?? UUID(),
                    client: client,
                    kind: kind,
                    title: title,
                    note: note,
                    websiteURL: websiteURL,
                    baseURL: baseURL,
                    model: model,
                    quotaAPI: selectedPreset?.quota ?? (automaticQuota ? .auto : quotaAPI),
                    quotaURL: selectedPreset == nil && !automaticQuota ? quotaURL : nil,
                    presetID: selectedPreset?.id,
                    apiFormat: apiFormat,
                    isFullURL: isFullURL,
                    customUserAgent: customUserAgent,
                    requestHeaderOverridesJSON: requestHeadersJSON,
                    requestBodyOverridesJSON: requestBodyJSON,
                    promptCacheKey: promptCacheKey,
                    promptCacheRouting: promptCacheRouting,
                    impersonateClaudeCode: impersonateClaudeCode,
                    maxOutputTokens: Int(maxOutputTokens),
                    endpointAutoSelect: endpointAutoSelect,
                    customEndpoints: customEndpointsText.components(separatedBy: .newlines),
                    runtimeSettingsJSON: selectedPreset == nil ? profile?.runtimeSettingsJSON : nil,
                    runtimeMetadataJSON: selectedPreset == nil ? profile?.runtimeMetadataJSON : nil,
                    claudeAPIKeyField: keyField,
                    claudeHaikuModel: haikuModel,
                    claudeHaikuModelName: haikuModelName,
                    claudeSonnetModel: sonnetModel,
                    claudeSonnetModelName: sonnetModelName,
                    claudeOpusModel: opusModel,
                    claudeOpusModelName: opusModelName,
                    claudeFableModel: fableModel,
                    claudeFableModelName: fableModelName,
                    claudeSubagentModel: subagentModel,
                    sourceIdentifier: profile?.sourceIdentifier,
                    createdAt: profile?.createdAt ?? now,
                    updatedAt: now
                )
                value.officialAccountID = kind == .official ? officialAccountID : nil
                if kind == .official, client == .claude, let credential = claudeCredential {
                    value.officialAccountID = value.id
                    value = try value.validated()
                    try ClaudeAccountCredentialStore().save(credential, id: value.id)
                }
                if activate {
                    try await onSaveAndSwitch(value, apiKey.isEmpty ? nil : apiKey)
                } else {
                    try await onSave(value, apiKey.isEmpty ? nil : apiKey)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var availableAPIFormats: [AIUpstreamAPIFormat] {
        client == .claude
            ? [.anthropic, .openAIChat, .openAIResponses, .geminiNative]
            : [.openAIResponses, .openAIChat, .anthropic]
    }

    private var apiFormatPicker: some View {
        Picker("", selection: $apiFormat) {
            ForEach(availableAPIFormats) { format in
                Text(format.title).tag(format)
            }
        }
        .labelsHidden()
    }

    private var promptCacheRoutingPicker: some View {
        Picker("", selection: $promptCacheRouting) {
            ForEach(AIPromptCacheRouting.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .labelsHidden()
    }

    private func testEndpoints() {
        isTestingEndpoint = true
        endpointTestMessage = nil
        let candidates = ([baseURL] + customEndpointsText.components(separatedBy: .newlines))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        Task {
            var measurements: [(String, Int)] = []
            for candidate in candidates {
                guard let url = URL(string: candidate) else { continue }
                var request = URLRequest(url: url)
                request.timeoutInterval = 8
                request.httpMethod = "GET"
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                }
                if !customUserAgent.isEmpty { request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent") }
                let started = Date()
                do {
                    let (_, response) = try await URLSession.shared.data(for: request)
                    guard response is HTTPURLResponse else { continue }
                    measurements.append((candidate, Int(Date().timeIntervalSince(started) * 1_000)))
                } catch { continue }
            }
            await MainActor.run {
                isTestingEndpoint = false
                guard let fastest = measurements.min(by: { $0.1 < $1.1 }) else {
                    endpointTestMessage = "所有端点均不可达"
                    return
                }
                endpointTestMessage = "最快：\(fastest.0) · \(fastest.1) ms"
                if endpointAutoSelect { baseURL = fastest.0 }
            }
        }
    }

    private func fetchModels() {
        guard let url = modelCatalogURL else {
            endpointTestMessage = "请求地址无效"
            return
        }
        isFetchingModels = true
        discoveredModels = []
        let requestID = UUID()
        modelRequestID = requestID
        endpointTestMessage = nil
        let requestKey = apiKey
        let requestFormat = apiFormat
        let requestKeyField = keyField
        let userAgent = customUserAgent
        let headers = requestHeadersJSON
        Task {
            do {
                let models = try await AIModelCatalogService().fetch(url: url, format: requestFormat, keyField: requestKeyField,
                    key: requestKey, userAgent: userAgent, headersJSON: headers)
                await MainActor.run {
                    guard modelRequestID == requestID else { return }
                    discoveredModels = models
                    endpointTestMessage = models.isEmpty ? "未识别到模型 ID" : "已获取 \(models.count) 个模型"
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    guard modelRequestID == requestID else { return }
                    endpointTestMessage = "获取模型失败：\(error.localizedDescription)"
                    isFetchingModels = false
                }
            }
        }
    }

    private var modelCatalogURL: URL? {
        AIEndpointResolver.catalogURL(baseURL: baseURL, format: apiFormat)
    }

    static func modelCatalogURL(baseURL: String, isFullURL: Bool = false) -> URL? {
        AIEndpointResolver.catalogURL(baseURL: baseURL)
    }

    private var presetQuotaURL: String? {
        guard let preset = selectedPreset, preset.quota != .none else { return nil }
        return try? AIProviderUsageService.endpoint(AIProviderProfile(client: client, title: title, baseURL: baseURL, model: model, quotaAPI: preset.quota)).0.absoluteString
    }

    private func applyPreset() {
        invalidateModels()
        errorMessage = nil
        if selectedPresetID == "custom" { kind = .custom; return }
        kind = selectedPresetID == "official" ? .official : .custom
        apiKey = ""
        model = ""
        bulkClaudeModel = ""
        haikuModel = ""; sonnetModel = ""; opusModel = ""; fableModel = ""; subagentModel = ""
        haikuModelName = ""; sonnetModelName = ""; opusModelName = ""; fableModelName = ""
        quotaURL = ""; automaticQuota = true
        customUserAgent = ""; requestHeadersJSON = ""; requestBodyJSON = ""
        promptCacheKey = ""; promptCacheRouting = .auto; impersonateClaudeCode = false
        maxOutputTokens = ""; endpointAutoSelect = false; customEndpointsText = ""
        if let preset = selectedPreset {
            title = preset.title
            baseURL = preset.address(for: client)
            websiteURL = preset.websiteURL
            apiFormat = preset.apiFormat(for: client)
            quotaAPI = preset.quota
            keyField = apiFormat == .anthropic && preset.id == "anthropic" ? .apiKey : .authToken
        } else {
            title = client.title + " 官方账号"
            baseURL = ""; websiteURL = ""
            apiFormat = .defaultValue(for: client)
            loadOfficialModels()
            showOfficialLogin = true
        }
    }

    private func loadOfficialModels() {
        discoveredModels = client == .codex ? OfficialModelCatalog.codexModels() : ["sonnet", "opus", "haiku"]
    }

    static func parseModelIDs(_ data: Data) -> [String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        let entries: [Any]
        if let object = root as? [String: Any] {
            entries = (object["data"] as? [Any]) ?? (object["models"] as? [Any]) ?? []
        } else {
            entries = root as? [Any] ?? []
        }
        return Array(Set(entries.compactMap { entry -> String? in
            if let value = entry as? String { return value }
            guard let object = entry as? [String: Any] else { return nil }
            return (object["id"] as? String) ?? (object["name"] as? String)
        })).sorted()
    }
}

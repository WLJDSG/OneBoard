import SwiftUI

struct AIModelSettingsView: View {
    @StateObject private var viewModel = AIModelSwitcherViewModel.shared
    @StateObject private var codexAccountViewModel = CodexAccountViewModel.shared
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
                    HStack {
                        Text("\(selectedClient.title) 供应商")
                        Spacer()
                        if selectedClient == .codex {
                            Button {
                                Task { await codexAccountViewModel.refreshAllAccountStatuses() }
                            } label: {
                                Label("刷新额度", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!codexAccountViewModel.refreshingAccountIDs.isEmpty)
                        }
                    }
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
        .onAppear { codexAccountViewModel.refreshState() }
        .sheet(isPresented: $isAddingProfile) {
            AIProviderEditorView(client: selectedClient, profile: nil, savedAPIKey: nil) { profile, key in
                try viewModel.save(profile, apiKey: key)
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
                if let note = profile.note {
                    Text(note)
                        .font(.caption)
                        .foregroundColor(OneBoardColors.textSecondary)
                        .lineLimit(1)
                }
                Text(profile.kind == .official ? profile.model : "\(profile.model) · \(profile.baseURL)")
                    .font(.caption)
                    .foregroundColor(OneBoardColors.textSecondary)
                    .lineLimit(1)
                let quota = AIProviderQuotaPresentation.make(
                    profile: profile,
                    activeCodexAccount: codexAccountViewModel.activeProfile
                )
                Text(quota.text)
                    .font(.caption2)
                    .foregroundColor(quotaColor(quota.tone))
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

    private func quotaColor(_ tone: AIProviderQuotaPresentation.Tone) -> Color {
        switch tone {
        case .normal: return OneBoardColors.success
        case .unavailable: return OneBoardColors.textSecondary
        case .warning: return OneBoardColors.warning
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
    @State private var note: String
    @State private var websiteURL: String
    @State private var baseURL: String
    @State private var model: String
    @State private var apiFormat: AIUpstreamAPIFormat
    @State private var isFullURL: Bool
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
    @State private var apiKey: String
    @State private var isAPIKeyVisible = false
    @State private var isAdvancedExpanded = true
    @State private var isProxyAdvancedExpanded = true
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
    @State private var errorMessage: String?

    init(
        client: AIClient,
        profile: AIProviderProfile?,
        savedAPIKey: String?,
        onSave: @escaping (AIProviderProfile, String?) throws -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.client = client
        self.profile = profile
        self.onSave = onSave
        self.onCancel = onCancel
        _kind = State(initialValue: profile?.kind ?? .custom)
        _title = State(initialValue: profile?.title ?? "")
        _note = State(initialValue: profile?.note ?? "")
        _websiteURL = State(initialValue: profile?.websiteURL ?? "")
        _baseURL = State(initialValue: profile?.baseURL ?? "")
        _model = State(initialValue: profile?.model ?? "")
        _apiFormat = State(initialValue: profile?.apiFormat ?? .defaultValue(for: client))
        _isFullURL = State(initialValue: profile?.isFullURL ?? false)
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
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: client.systemImage)
                    .font(.title2)
                    .foregroundColor(OneBoardColors.accent)
                    .frame(width: 44, height: 44)
                    .background(OneBoardColors.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile == nil ? "新增 \(client.title) 供应商" : "编辑 \(client.title) 供应商")
                        .font(.title3.weight(.semibold))
                    Text("配置供应商连接、鉴权和模型映射")
                        .font(.caption)
                        .foregroundColor(OneBoardColors.textSecondary)
                }
                Spacer()
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            editorRow("类型") {
                                Picker("", selection: $kind) {
                                    ForEach(AIProviderKind.allCases) { kind in Text(kind.title).tag(kind) }
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
                            if client == .codex {
                                editorRow("默认模型") {
                                    TextField("例如：gpt-5", text: $model)
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
                                        TextField("https://api.example.com", text: $baseURL)
                                        Button(isTestingEndpoint ? "测试中…" : "测速") { testEndpoints() }
                                            .disabled(isTestingEndpoint || baseURL.isEmpty)
                                    }
                                }
                                editorRow("完整 URL") {
                                    Toggle("地址已包含最终 API 路径，不再自动拼接", isOn: $isFullURL)
                                }
                                editorRow("模型目录") {
                                    HStack {
                                        Button(isFetchingModels ? "获取中…" : "获取模型") { fetchModels() }
                                            .disabled(isFetchingModels || baseURL.isEmpty)
                                        if !discoveredModels.isEmpty {
                                            Picker("选择模型", selection: $model) {
                                                ForEach(discoveredModels, id: \.self) { Text($0).tag($0) }
                                            }
                                            .labelsHidden()
                                        }
                                    }
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
                                            isAPIKeyVisible.toggle()
                                        } label: {
                                            Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                                        }
                                        .buttonStyle(.borderless)
                                        .help(isAPIKeyVisible ? "隐藏 API Key" : "显示 API Key")
                                    }
                                }
                            }

                            Label("API Key 仅保存到 OneBoard 的 oneboard.sqlite，不使用钥匙串。", systemImage: "externaldrive.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(OneBoardColors.textSecondary)
                                .padding(.top, 10)
                            if let endpointTestMessage {
                                Text(endpointTestMessage)
                                    .font(.caption)
                                    .foregroundColor(OneBoardColors.textSecondary)
                                    .padding(.top, 4)
                            }
                        } label: {
                            Label("连接与鉴权", systemImage: "key.horizontal")
                        }
                    }

                    if kind == .custom {
                        GroupBox {
                            DisclosureGroup(isExpanded: $isProxyAdvancedExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                                        editorRow("上游格式") {
                                            Picker("", selection: $apiFormat) {
                                                ForEach(availableAPIFormats) { format in Text(format.title).tag(format) }
                                            }
                                            .labelsHidden()
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
                                                Picker("", selection: $promptCacheRouting) {
                                                    ForEach(AIPromptCacheRouting.allCases) { mode in Text(mode.title).tag(mode) }
                                                }
                                                .labelsHidden()
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
                                    Text("请求覆盖在协议转换完成后应用。JSON 留空表示不覆盖；备用端点每行一个 URL。")
                                        .font(.caption)
                                        .foregroundColor(OneBoardColors.textSecondary)
                                }
                                .padding(.top, 10)
                            } label: {
                                Text("代理与协议转换")
                                    .font(.body.weight(.medium))
                            }
                        } label: {
                            Label("CC Switch 兼容能力", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }

                    if client == .claude {
                        GroupBox {
                            DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("空槽位自动使用默认模型；Fable 为空时优先使用 Opus。模型 ID 可带 [1M] 后缀，显示名仅影响 Claude Code 的模型选择界面。")
                                        .font(.caption)
                                        .foregroundColor(OneBoardColors.textSecondary)

                                    HStack {
                                        Text("模型映射")
                                            .font(.body.weight(.medium))
                                        Spacer()
                                        Button {
                                            applyOneModelToAllRoles()
                                        } label: {
                                            Label("一键设置", systemImage: "wand.and.stars")
                                        }
                                        .disabled(firstConfiguredClaudeModel == nil)
                                    }

                                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                                        GridRow {
                                            Text("模型角色")
                                            Text("显示名称")
                                            Text("实际请求模型")
                                            Text("1M")
                                        }
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(OneBoardColors.textSecondary)

                                        modelMappingRow("Sonnet", model: $sonnetModel, name: $sonnetModelName)
                                        modelMappingRow("Opus", model: $opusModel, name: $opusModelName)
                                        modelMappingRow("Fable", model: $fableModel, name: $fableModelName)
                                        modelMappingRow("Haiku", model: $haikuModel, name: $haikuModelName, supportsOneM: false)
                                        GridRow {
                                            Text("子代理")
                                                .foregroundColor(OneBoardColors.textSecondary)
                                                .frame(width: 92, alignment: .leading)
                                            Text("不显示在 /model 菜单")
                                                .font(.caption)
                                                .foregroundColor(OneBoardColors.textSecondary)
                                            TextField("模型 ID（可选）", text: modelBaseBinding($subagentModel))
                                            Toggle("", isOn: oneMBinding($subagentModel))
                                                .labelsHidden()
                                        }

                                        GridRow {
                                            Divider().gridCellColumns(4)
                                        }

                                        GridRow {
                                            Text("默认兜底")
                                                .foregroundColor(OneBoardColors.textSecondary)
                                                .frame(width: 92, alignment: .leading)
                                            Text("未匹配角色时使用")
                                                .font(.caption)
                                                .foregroundColor(OneBoardColors.textSecondary)
                                            TextField("第三方端点建议填写", text: modelBaseBinding($model))
                                            Toggle("", isOn: oneMBinding($model))
                                                .labelsHidden()
                                        }
                                    }
                                }
                                .padding(.top, 10)
                            } label: {
                                Text("高级选项")
                                    .font(.body.weight(.medium))
                            }
                        } label: {
                            Label("Claude Code 模型槽位", systemImage: "slider.horizontal.3")
                        }
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
                Button("保存") { save() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: client == .claude ? 820 : 760, height: 800)
    }

    @ViewBuilder
    private func editorRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .foregroundColor(OneBoardColors.textSecondary)
                .frame(width: 92, alignment: .leading)
            content()
                .frame(maxWidth: .infinity)
        }
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
                .foregroundColor(OneBoardColors.textSecondary)
                .frame(width: 92, alignment: .leading)
            TextField("显示名（可选）", text: name)
                .frame(minWidth: 150)
            TextField("模型 ID（可选）", text: modelBaseBinding(model))
            if supportsOneM {
                Toggle("", isOn: oneMBinding(model))
                    .labelsHidden()
            } else {
                Text("—")
                    .foregroundColor(OneBoardColors.textSecondary)
            }
        }
    }

    private var firstConfiguredClaudeModel: String? {
        [model, sonnetModel, opusModel, fableModel, haikuModel, subagentModel]
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func applyOneModelToAllRoles() {
        guard let value = firstConfiguredClaudeModel else { return }
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

    private func save() {
        do {
            let now = Date()
            let value = AIProviderProfile(
                id: profile?.id ?? UUID(),
                client: client,
                kind: kind,
                title: title,
                note: note,
                websiteURL: websiteURL,
                baseURL: baseURL,
                model: model,
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
                runtimeSettingsJSON: profile?.runtimeSettingsJSON,
                runtimeMetadataJSON: profile?.runtimeMetadataJSON,
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
            try onSave(value, apiKey.isEmpty ? nil : apiKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var availableAPIFormats: [AIUpstreamAPIFormat] {
        client == .claude
            ? [.anthropic, .openAIChat, .openAIResponses, .geminiNative]
            : [.openAIResponses, .openAIChat, .anthropic]
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
        endpointTestMessage = nil
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 15
                if !apiKey.isEmpty {
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                }
                if !customUserAgent.isEmpty { request.setValue(customUserAgent, forHTTPHeaderField: "User-Agent") }
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                    throw AIModelSwitchError.proxyFailure("模型目录返回非 2xx 状态")
                }
                let models = Self.parseModelIDs(data)
                await MainActor.run {
                    discoveredModels = models
                    endpointTestMessage = models.isEmpty ? "未识别到模型 ID" : "已获取 \(models.count) 个模型"
                    isFetchingModels = false
                }
            } catch {
                await MainActor.run {
                    endpointTestMessage = "获取模型失败：\(error.localizedDescription)"
                    isFetchingModels = false
                }
            }
        }
    }

    private var modelCatalogURL: URL? {
        guard var components = URLComponents(string: baseURL) else { return nil }
        if isFullURL { return components.url }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + ([path, "models"].filter { !$0.isEmpty }.joined(separator: "/"))
        return components.url
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

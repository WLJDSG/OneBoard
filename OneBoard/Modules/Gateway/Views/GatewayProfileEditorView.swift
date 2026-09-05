import SwiftUI

struct GatewayProfileEditorView: View {
    @ObservedObject var viewModel: GatewayProfileEditorViewModel
    let onSave: (GatewayProfile) -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(viewModel.title.isEmpty ? "新增网关" : "编辑网关")
                .font(.headline)

            SettingsForm {
                LabeledContent("标题") { TextField("标题", text: $viewModel.title).labelsHidden() }

                LabeledContent("模式") {
                    Picker("模式", selection: $viewModel.mode) {
                    ForEach(GatewaySwitchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }.labelsHidden().frame(width: 230)
                }

                if viewModel.mode == .gatewayAndDNS {
                    LabeledContent("网关 IP") { TextField("网关 IP", text: $viewModel.gateway).labelsHidden() }
                }

                LabeledContent("DNS（逗号、空格或换行分隔）") { TextField("DNS（逗号、空格或换行分隔）", text: $viewModel.dnsText, axis: .vertical).labelsHidden() }
                    .lineLimit(3, reservesSpace: true)

                LabeledContent("图标") { TextField("图标", text: $viewModel.symbolName).labelsHidden() }
                LabeledContent("描述") { TextField("描述", text: $viewModel.description, axis: .vertical).labelsHidden() }
                    .lineLimit(2, reservesSpace: true)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") {
                    do {
                        onSave(try viewModel.buildProfile())
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(SettingsActionStyle(prominent: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .background(SettingsBackdrop())
        .buttonStyle(SettingsActionStyle())
        .textFieldStyle(.roundedBorder)
        .tint(SettingsPalette.accent)
        .frame(width: 560, height: 600)
    }
}

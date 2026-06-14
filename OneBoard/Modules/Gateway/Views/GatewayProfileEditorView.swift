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

            Form {
                TextField("标题", text: $viewModel.title)

                Picker("模式", selection: $viewModel.mode) {
                    ForEach(GatewaySwitchMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if viewModel.mode == .gatewayAndDNS {
                    TextField("网关 IP", text: $viewModel.gateway)
                }

                TextField("DNS（逗号、空格或换行分隔）", text: $viewModel.dnsText, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)

                TextField("图标", text: $viewModel.symbolName)
                TextField("描述", text: $viewModel.description, axis: .vertical)
                    .lineLimit(2, reservesSpace: true)
            }
            .formStyle(.grouped)

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
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 430, height: 430)
    }
}

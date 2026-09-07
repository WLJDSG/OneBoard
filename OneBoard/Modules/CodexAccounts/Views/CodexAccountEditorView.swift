import SwiftUI

struct CodexAccountEditorView: View {
    @ObservedObject var viewModel: CodexAccountEditorViewModel
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑账号名称")
                .font(.system(size: 17, weight: .semibold))

            SettingsForm(inset: 0) {
                LabeledContent("账号名称") { TextField("账号名称", text: $viewModel.title).labelsHidden() }
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
                        onSave(try viewModel.validatedTitle())
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
        .frame(width: 480, height: 270)
    }
}

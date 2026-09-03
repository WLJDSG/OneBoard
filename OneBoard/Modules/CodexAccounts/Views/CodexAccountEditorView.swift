import SwiftUI

struct CodexAccountEditorView: View {
    @ObservedObject var viewModel: CodexAccountEditorViewModel
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑账号名称")
                .font(.headline)

            Form {
                TextField("账号名称", text: $viewModel.title)
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
                        onSave(try viewModel.validatedTitle())
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 430, height: 210)
    }
}

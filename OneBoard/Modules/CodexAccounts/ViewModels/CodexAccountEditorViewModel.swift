import Foundation

@MainActor
final class CodexAccountEditorViewModel: ObservableObject {
    @Published var title: String
    let editingID: UUID?

    init(profile: CodexAccountProfile? = nil) {
        editingID = profile?.id
        title = profile?.title ?? ""
    }

    func validatedTitle() throws -> String {
        let value = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw CodexAccountError.invalidTitle }
        return value
    }
}

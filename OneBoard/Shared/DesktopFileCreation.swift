import AppKit

@MainActor
enum DesktopFileCreation {
    static func create(kind: FinderFileKind) {
        do {
            let desktop = try FileManager.default.url(for: .desktopDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: false)
            let file = try FinderFileCreator.create(kind: kind, in: desktop.resolvingSymlinksInPath())
            NSWorkspace.shared.activateFileViewerSelecting([file])
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法在桌面新建文件"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}

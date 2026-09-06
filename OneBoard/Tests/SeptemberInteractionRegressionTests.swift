import AppKit
import XCTest
@testable import OneBoardKit

@MainActor
final class SeptemberInteractionRegressionTests: XCTestCase {
    func testDeletingNumberClosesGapBeforeAddingNext() {
        let service = AnnotationService()
        for x in 1...3 { service.addNumber(at: CGPoint(x: x * 40, y: 40)) }
        service.removeLayer(id: service.layers[1].id)
        XCTAssertEqual(service.layers.compactMap(\.numberValue), [1, 2])
        service.addNumber(at: CGPoint(x: 160, y: 40))
        XCTAssertEqual(service.layers.compactMap(\.numberValue), [1, 2, 3])
    }
}

@MainActor
final class SeptemberAccountAndAnnotationTests: XCTestCase {
    func testRenumberShiftsOtherBadgesAndUndoRestoresOrder() {
        let service = AnnotationService()
        for x in 1...3 { service.addNumber(at: CGPoint(x: x * 40, y: 40)) }
        let id = service.layers[2].id
        service.updateNumber(id: id, value: 1)
        XCTAssertEqual(service.layers.compactMap(\.numberValue), [2, 3, 1])
        service.undo()
        XCTAssertEqual(service.layers.compactMap(\.numberValue), [1, 2, 3])
        service.redo()
        XCTAssertEqual(service.layers.compactMap(\.numberValue), [2, 3, 1])
        service.updateNumber(id: id, value: 5)
        XCTAssertEqual(service.layers.compactMap(\.numberValue), [2, 3, 1])
        service.addNumber(at: CGPoint(x: 200, y: 40))
        XCTAssertEqual(service.layers.last?.numberValue, 4)
    }

    func testClickExistingBadgeEditsInsteadOfAppending() throws {
        let service = AnnotationService()
        service.selectedTool = .number
        service.addNumber(at: CGPoint(x: 40, y: 40))
        let model = AnnotationViewModel(annotationService: service)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 40, y: 40),
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        model.beginInteraction(at: CGPoint(x: 40, y: 40), event: event)
        XCTAssertEqual(model.editingNumberLayerID, service.layers.first?.id)
        XCTAssertEqual(service.layers.count, 1)
    }

    func testOAuthCallbackRejectsWrongStateAndAuthorizationPage() throws {
        XCTAssertEqual(try ClaudeAccountAuthorization.authorizationCode("abc#state", expectedState: "state"), "abc")
        XCTAssertEqual(try ClaudeAccountAuthorization.authorizationCode("https://platform.claude.com/oauth/code/callback?code=abc&state=state", expectedState: "state"), "abc")
        XCTAssertThrowsError(try ClaudeAccountAuthorization.authorizationCode("abc#wrong", expectedState: "state"))
        XCTAssertThrowsError(try ClaudeAccountAuthorization.authorizationCode("https://claude.com/cai/oauth/authorize?code=true", expectedState: "state"))
    }

    func testOAuthURLUsesPKCEAndCancelInvalidatesSession() async throws {
        let authorization = ClaudeAccountAuthorization()
        try authorization.begin()
        let url = try XCTUnwrap(authorization.authorizationURL)
        let parameters = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(url.host, "claude.com")
        XCTAssertEqual(parameters.first { $0.name == "code_challenge_method" }?.value, "S256")
        XCTAssertEqual(parameters.first { $0.name == "code_challenge" }?.value?.count, 43)
        authorization.cancel()
        do { _ = try await authorization.complete("fake"); XCTFail("Cancelled session accepted") } catch {}
    }

    func testOfficialCatalogParsesVisibleSlugs() {
        let json = Data(#"{"models":[{"slug":"a","visibility":"list"},{"slug":"hidden","visibility":"hide"},{"slug":"a"},{"slug":"b"}]}"#.utf8)
        XCTAssertEqual(OfficialModelCatalog.parse(json), ["a", "b"])
    }

    func testMosaicUsesOriginalColorAndBlockSize() throws {
        let image = NSImage(size: CGSize(width: 100, height: 100))
        image.lockFocus(); NSColor.red.setFill(); CGRect(x: 0, y: 0, width: 100, height: 100).fill(); image.unlockFocus()
        let pixels = try XCTUnwrap(MosaicPixels.make(image: image, displaySize: image.size,
            rect: CGRect(x: 10, y: 10, width: 60, height: 40), blockSize: 10))
        let source = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        XCTAssertEqual(pixels.width, Int(60 * CGFloat(source.width) / image.size.width))
        XCTAssertEqual(pixels.height, Int(40 * CGFloat(source.height) / image.size.height))
        let color = try XCTUnwrap(NSBitmapImageRep(cgImage: pixels).colorAt(x: 1, y: 1)?.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(color.redComponent, 0.95)
        XCTAssertLessThan(color.greenComponent, 0.05)
        XCTAssertEqual(color.alphaComponent, 1, accuracy: 0.01)
    }

    func testTrackingExitDoesNotEraseHoverWhilePointerIsStillInside() throws {
        let point = NSEvent.mouseLocation
        let frame = CGRect(x: point.x - 150, y: point.y - 100, width: 300, height: 200)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let image = NSImage(size: frame.size)
        image.lockFocus(); NSColor.white.setFill(); CGRect(origin: .zero, size: frame.size).fill(); image.unlockFocus()
        let candidate = CGRect(x: 20, y: 20, width: 260, height: 160)
        let view = ScreenshotOverlayContentView(screenshot: image, eventManager: OverlayEventManager(), windowCandidates: [candidate])
        window.contentView = view
        view.refreshPointerHover()
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 150, y: 100),
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        view.mouseExited(with: event)
        XCTAssertEqual(Mirror(reflecting: view).children.first { $0.label == "hoveredWindowRect" }?.value as? CGRect, candidate)
    }

    func testOfficialClaudeSwitchRemovesAPIKeyAndPreservesUnknownSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("settings.json")
        try Data(#"{"theme":"dark","env":{"KEEP":"yes","ANTHROPIC_API_KEY":"old","ANTHROPIC_BASE_URL":"https://example.test"}}"#.utf8).write(to: url)
        let writer = AIModelConfigurationWriter(codexConfigURL: root.appendingPathComponent("config.toml"), claudeSettingsURL: url)
        var profile = AIProviderProfile(client: .claude, kind: .official, title: "Test", model: "sonnet")
        profile.officialAccountID = UUID()
        try writer.apply(profile, apiKey: "test-oauth")
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let env = try XCTUnwrap(value["env"] as? [String: String])
        XCTAssertEqual(value["theme"] as? String, "dark")
        XCTAssertEqual(env["KEEP"], "yes")
        XCTAssertEqual(env["CLAUDE_CODE_OAUTH_TOKEN"], "test-oauth")
        XCTAssertNil(env["ANTHROPIC_API_KEY"]); XCTAssertNil(env["ANTHROPIC_BASE_URL"])
        profile.kind = .custom; profile.baseURL = "https://example.test"
        try writer.apply(profile, apiKey: "test-key")
        let custom = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        XCTAssertNil((custom["env"] as? [String: String])?["CLAUDE_CODE_OAUTH_TOKEN"])
    }
}

@MainActor
final class SeptemberMaskAndAccessTests: XCTestCase {
    func testDimMaskExcludesSelectionAndCoversOtherScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let mask = LongCaptureOverlayLayout.dimPath(in: bounds, selection: CGRect(x: 200, y: 200, width: 300, height: 300))
        XCTAssertFalse(mask.contains(CGPoint(x: 350, y: 350)))
        XCTAssertTrue(mask.contains(CGPoint(x: 50, y: 350)))
        let otherScreen = LongCaptureOverlayLayout.dimPath(in: bounds, selection: CGRect(x: -800, y: 200, width: 300, height: 300))
        XCTAssertTrue(otherScreen.contains(CGPoint(x: 350, y: 350)))
    }

    func testFolderSelectionIgnoresDirectoryURLTrailingSlash() {
        let path = "/tmp/oneboard-folder-selection"
        let expected = URL(fileURLWithPath: path, isDirectory: true)
        XCTAssertTrue(FolderAccessStore.matchesDirectory(URL(fileURLWithPath: path, isDirectory: false), expected: expected))
        XCTAssertFalse(FolderAccessStore.matchesDirectory(URL(fileURLWithPath: path + "-other", isDirectory: true), expected: expected))
    }

    func testClaudeAccountNavigationIsDistinct() {
        XCTAssertNotEqual(SettingsTab.claudeAccounts, SettingsTab.codexAccounts)
        XCTAssertEqual(SettingsTab.claudeAccounts.title, "Claude Code 账号")
    }

    func testFolderBookmarkSurvivesStoreRecreation() throws {
        let suite = "OneBoard.Access.Test." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        do { try FolderAccessStore(defaults: defaults).save(root, for: .iCloud) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == 256 {
            throw XCTSkip("当前 xctest 无签名应用作用域，ScopedBookmarksAgent 拒绝创建；需签名 App 内验收")
        }
        let restored = try FolderAccessStore(defaults: defaults).resolve(.iCloud)
        XCTAssertEqual(restored.url.resolvingSymlinksInPath(), root.resolvingSymlinksInPath())
    }
}

import AppKit
import XCTest
@testable import OneBoardKit

final class WorkspaceNavigationTests: XCTestCase {
    @MainActor
    func testDailyToolsAreReachableAndMaintenanceIsSeparate() {
        let menu = MenuBarManager.shared.makeMainMenu()
        for title in ["截图…", "翻译…", "剪贴板历史…", "文件暂存区…", "待办列表…", "网关切换…", "设置…"] {
            let item = menu.items.first { $0.title == title }
            XCTAssertNotNil(item, title)
            XCTAssertNotNil(item?.action, title)
            XCTAssertTrue(item?.target === MenuBarManager.shared, title)
        }
        XCTAssertNil(menu.items.first { $0.title == "彻底卸载并清理残留…" })
        let maintenance = menu.items.first { $0.title == "维护" }?.submenu
        XCTAssertEqual(maintenance?.items.count, 2)
        XCTAssertNotNil(maintenance?.items.last?.action)
    }

    @MainActor
    func testDesktopCreationIsAvailableWithoutFinderExtensionMenu() throws {
        let menu = MenuBarManager.shared.makeMainMenu()
        let desktop = try XCTUnwrap(menu.items.first { $0.title == "在桌面新建文件" }?.submenu)
        let enabled = UserDefaults(suiteName: Constants.appGroupIdentifier)?.stringArray(forKey: Constants.UserDefaultsKeys.enabledFileTypes) ?? ["txt", "docx", "xlsx"]
        XCTAssertEqual(desktop.items.compactMap { $0.representedObject as? String },
                       FinderFileKind.allCases.map(\.rawValue).filter { enabled.contains($0) })
        for item in desktop.items {
            XCTAssertNotNil(item.action)
            XCTAssertTrue(item.target === MenuBarManager.shared)
        }
    }

    func testPersistedSettingsDestinationsRemainValid() {
        XCTAssertEqual(SettingsTab(rawValue: "general"), .general)
        XCTAssertEqual(SettingsTab(rawValue: "recognition"), .recognition)
        XCTAssertEqual(SettingsTab(rawValue: "todo"), .todo)
        XCTAssertNotEqual(SettingsTab.translation, .recognition)
        XCTAssertNotEqual(SettingsTab.files, .todo)
    }
}

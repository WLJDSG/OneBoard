import Foundation
@testable import OneBoardKit
import XCTest

final class FinderFileCreationTests: XCTestCase {
    func testFinderCommandRoundTripsProtectedDirectoryWithoutWritingInExtension() throws {
        let directory = URL(fileURLWithPath: "/Users/example/Desktop/办公", isDirectory: true)
        let request = FinderFileCreationRequest(directoryURL: directory, kind: .txt)

        let commandURL = try XCTUnwrap(request.commandURL)
        let decoded = try XCTUnwrap(FinderFileCreationRequest(commandURL: commandURL))

        XCTAssertEqual(decoded.directoryURL, directory)
        XCTAssertEqual(decoded.kind, .txt)
    }

    func testFinderManagedDirectoriesCoverRootAndDesktop() {
        let home = URL(fileURLWithPath: "/Users/example", isDirectory: true)
        let directories = FinderFileCreationRequest.managedDirectories(homeURL: home)
        let iCloudDesktop = home
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Desktop", isDirectory: true)

        XCTAssertTrue(directories.contains(URL(fileURLWithPath: "/", isDirectory: true)))
        XCTAssertTrue(directories.contains(home.appendingPathComponent("Desktop", isDirectory: true)))
        XCTAssertTrue(directories.contains(iCloudDesktop))
    }

    func testFinderExtensionSharesFileTypePreferencesWithMainApp() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let entitlementsURL = testsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("FinderSync/OneBoardFinderSync.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let groups = try XCTUnwrap(plist["com.apple.security.application-groups"] as? [String])

        XCTAssertTrue(groups.contains("group.com.oneboard.mac"))
    }

    func testCreatorWritesUniqueTextFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("oneboard-finder-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try FinderFileCreator.create(kind: .txt, in: root)
        let second = try FinderFileCreator.create(kind: .txt, in: root)

        XCTAssertEqual(first.lastPathComponent, "未命名.txt")
        XCTAssertEqual(second.lastPathComponent, "未命名 1.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
}

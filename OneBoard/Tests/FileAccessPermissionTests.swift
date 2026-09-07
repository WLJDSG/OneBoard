import Foundation
import XCTest
@testable import OneBoardKit

final class FileAccessPermissionTests: XCTestCase {
    func testOtherAppDataGuideUsesPathBoundaries() {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        XCTAssertTrue(PermissionManager.isOtherAppDataURL(library.appendingPathComponent("Containers/test/Data/a.txt")))
        XCTAssertTrue(PermissionManager.isOtherAppDataURL(library.appendingPathComponent("Group Containers/test/a.txt")))
        XCTAssertFalse(PermissionManager.isOtherAppDataURL(library.appendingPathComponent("Containers-backup/a.txt")))
        XCTAssertFalse(PermissionManager.isOtherAppDataURL(URL(fileURLWithPath: "/tmp/a.txt")))
    }

    func testClipboardFileClassificationDoesNotRequireExistingFiles() {
        XCTAssertTrue(PasteboardTypeMapper.isSupportedFileURL(URL(fileURLWithPath: "/nonexistent/report.txt")))
        XCTAssertFalse(PasteboardTypeMapper.isSupportedFileURL(URL(fileURLWithPath: "/nonexistent/Test.app")))
        XCTAssertFalse(PasteboardTypeMapper.isSupportedFileURL(URL(fileURLWithPath: "/nonexistent/Test.bundle")))
    }

    func testOnlyAccessDenialsOfferAuthorization() {
        for code in [NSFileReadNoPermissionError, NSFileWriteNoPermissionError] {
            XCTAssertTrue(PermissionManager.isFileAccessDenied(NSError(domain: NSCocoaErrorDomain, code: code)))
        }
        XCTAssertTrue(PermissionManager.isFileAccessDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
        XCTAssertTrue(PermissionManager.isFileAccessDenied(NSError(domain: "Preview", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])))
        XCTAssertFalse(PermissionManager.isFileAccessDenied(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        XCTAssertFalse(PermissionManager.isFileAccessDenied(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))))
        XCTAssertFalse(PermissionManager.isFileAccessDenied(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)))
    }
}

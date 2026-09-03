import Foundation
import XCTest
@testable import OneBoardKit

@MainActor
final class CodexAccountServiceTests: XCTestCase {
    func testSaveAuthorizedAccountStoresOAuthCredentialWithoutReplacingCurrentLogin() throws {
        let context = try makeContext(initialData: authData("current"))
        let credential = CodexOAuthCredential(
            email: "work@example.com",
            accountID: "account-1",
            planType: "plus",
            authCache: authData("oauth")
        )

        let profile = try context.service.saveAuthorizedAccount(
            requestedEmail: " Work@Example.com ",
            credential: credential
        )

        XCTAssertEqual(profile.title, "work@example.com")
        XCTAssertEqual(profile.email, "work@example.com")
        XCTAssertEqual(profile.accountID, "account-1")
        XCTAssertEqual(profile.planType, "plus")
        XCTAssertEqual(context.vault.storage[profile.id], authData("oauth"))
        XCTAssertNil(context.store.activeAccountID)
        XCTAssertEqual(try context.authFile.read(), authData("current"))
    }

    func testSaveAuthorizedAccountRejectsBrowserAccountMismatch() throws {
        let context = try makeContext(initialData: authData("current"))
        let credential = CodexOAuthCredential(
            email: "other@example.com",
            accountID: nil,
            planType: nil,
            authCache: authData("oauth")
        )

        XCTAssertThrowsError(
            try context.service.saveAuthorizedAccount(
                requestedEmail: "work@example.com",
                credential: credential
            )
        ) { error in
            XCTAssertEqual(
                error as? CodexAccountError,
                .oauthAccountMismatch(expected: "work@example.com", actual: "other@example.com")
            )
        }
        XCTAssertTrue(context.store.profiles.isEmpty)
        XCTAssertTrue(context.vault.storage.isEmpty)
    }

    func testSaveAuthorizedAccountUpdatesExistingEmailCredential() throws {
        let context = try makeContext(initialData: authData("current"))
        let existing = CodexAccountProfile(title: "工作", email: "work@example.com")
        context.store.profiles = [existing]
        context.vault.storage[existing.id] = authData("old")

        let updated = try context.service.saveAuthorizedAccount(
            requestedEmail: "work@example.com",
            credential: CodexOAuthCredential(
                email: "work@example.com",
                accountID: "account-new",
                planType: "team",
                authCache: authData("new")
            )
        )

        XCTAssertEqual(context.store.profiles.count, 1)
        XCTAssertEqual(updated.id, existing.id)
        XCTAssertEqual(updated.title, "工作")
        XCTAssertEqual(updated.accountID, "account-new")
        XCTAssertEqual(context.vault.storage[existing.id], authData("new"))
    }

    func testRequestSwitchClosesBeforeReplacingCredentialAndRelaunches() async throws {
        let context = try makeContext(initialData: authData("refreshed-account-a"))
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountA.id] = authData("old-account-a")
        context.vault.storage[accountB.id] = authData("account-b")
        context.lifecycle.isRunning = true
        context.lifecycle.onClose = {
            XCTAssertEqual(try context.authFile.read(), self.authData("refreshed-account-a"))
        }

        let outcome = try await context.service.requestSwitch(to: accountB.id)

        XCTAssertEqual(outcome, .switched)
        XCTAssertEqual(context.lifecycle.events, ["close", "launch"])
        XCTAssertEqual(context.vault.storage[accountA.id], authData("refreshed-account-a"))
        XCTAssertEqual(try context.authFile.read(), authData("account-b"))
        XCTAssertEqual(context.store.activeAccountID, accountB.id)
        XCTAssertNil(context.store.pendingAccountID)
    }

    func testRequestSwitchRenewsTargetCredentialBeforeClosingCodex() async throws {
        let statusProvider = FakeCodexAccountStatusProvider()
        statusProvider.preparedCredential = authData("account-b-rotated")
        let context = try makeContext(initialData: authData("account-a"), statusProvider: statusProvider)
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountA.id] = authData("account-a")
        context.vault.storage[accountB.id] = authData("account-b")
        context.lifecycle.isRunning = true

        _ = try await context.service.requestSwitch(to: accountB.id)

        XCTAssertEqual(statusProvider.preparedInputs, [authData("account-b")])
        XCTAssertEqual(context.vault.storage[accountB.id], authData("account-b-rotated"))
        XCTAssertEqual(try context.authFile.read(), authData("account-b-rotated"))
        XCTAssertEqual(context.lifecycle.events, ["close", "launch"])
    }

    func testRefreshStatusDoesNotRotateActiveCredentialWhileCodexRuns() async throws {
        let statusProvider = FakeCodexAccountStatusProvider()
        statusProvider.refreshError = CodexAccountError.credentialRefreshDeferred
        let context = try makeContext(initialData: authData("account-a"), statusProvider: statusProvider)
        let account = CodexAccountProfile(title: "账号 A")
        context.store.profiles = [account]
        context.store.activeAccountID = account.id
        context.vault.storage[account.id] = authData("account-a")
        context.lifecycle.isRunning = true

        do {
            _ = try await context.service.refreshAccountStatus(id: account.id)
            XCTFail("运行中的当前账号不应旋转凭据")
        } catch {
            XCTAssertEqual(error as? CodexAccountError, .credentialRefreshDeferred)
        }

        XCTAssertEqual(statusProvider.allowCredentialRefreshValues, [false])
        XCTAssertEqual(context.vault.storage[account.id], authData("account-a"))
        XCTAssertEqual(try context.authFile.read(), authData("account-a"))
        XCTAssertEqual(context.store.profiles.first?.statusError, CodexAccountError.credentialRefreshDeferred.localizedDescription)
    }

    func testRefreshStatusUsesCurrentOfficialCredentialAsActiveAccountAuthority() async throws {
        let statusProvider = FakeCodexAccountStatusProvider()
        let context = try makeContext(initialData: authData("codex-rotated"), statusProvider: statusProvider)
        let account = CodexAccountProfile(title: "账号 A")
        context.store.profiles = [account]
        context.store.activeAccountID = account.id
        context.vault.storage[account.id] = authData("stale-vault")
        context.lifecycle.isRunning = true

        _ = try await context.service.refreshAccountStatus(id: account.id)

        XCTAssertEqual(statusProvider.refreshInputs, [authData("codex-rotated")])
        XCTAssertEqual(context.vault.storage[account.id], authData("codex-rotated"))
        XCTAssertEqual(statusProvider.allowCredentialRefreshValues, [false])
    }

    func testRequestSwitchRejectsMissingTargetCredentialBeforeClosingCodex() async throws {
        let context = try makeContext(initialData: authData("account-a"))
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountA.id] = authData("account-a")
        context.lifecycle.isRunning = true

        do {
            _ = try await context.service.requestSwitch(to: accountB.id)
            XCTFail("应在关闭 Codex 前拒绝缺失的目标凭据")
        } catch {
            XCTAssertEqual(error as? CodexAccountError, .authCacheMissing)
        }
        XCTAssertTrue(context.lifecycle.events.isEmpty)
        XCTAssertNil(context.store.pendingAccountID)
        XCTAssertEqual(try context.authFile.read(), authData("account-a"))
    }

    func testRequestSwitchRejectsInvalidTargetCredentialBeforeClosingCodex() async throws {
        let context = try makeContext(initialData: authData("account-a"))
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountB.id] = Data("invalid".utf8)
        context.lifecycle.isRunning = true

        do {
            _ = try await context.service.requestSwitch(to: accountB.id)
            XCTFail("应在关闭 Codex 前拒绝无效的目标凭据")
        } catch {
            XCTAssertEqual(error as? CodexAccountError, .invalidAuthCache)
        }
        XCTAssertTrue(context.lifecycle.events.isEmpty)
        XCTAssertEqual(try context.authFile.read(), authData("account-a"))
    }

    func testCloseFailureDoesNotCommitCredentialOrLaunch() async throws {
        let context = try makeContext(initialData: authData("account-a"))
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountA.id] = authData("account-a")
        context.vault.storage[accountB.id] = authData("account-b")
        context.lifecycle.closeError = CodexAccountError.applicationCloseFailed

        do {
            _ = try await context.service.requestSwitch(to: accountB.id)
            XCTFail("关闭失败时不应切换")
        } catch {
            XCTAssertEqual(error as? CodexAccountError, .applicationCloseFailed)
        }
        XCTAssertEqual(context.lifecycle.events, ["close"])
        XCTAssertEqual(try context.authFile.read(), authData("account-a"))
        XCTAssertEqual(context.store.activeAccountID, accountA.id)
        XCTAssertNil(context.store.pendingAccountID)
    }

    func testLaunchFailureKeepsCommittedTargetAndReportsManualRecovery() async throws {
        let context = try makeContext(initialData: authData("account-a"))
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountA.id] = authData("account-a")
        context.vault.storage[accountB.id] = authData("account-b")
        context.lifecycle.launchError = CodexAccountError.applicationLaunchFailed

        do {
            _ = try await context.service.requestSwitch(to: accountB.id)
            XCTFail("应返回启动失败")
        } catch {
            XCTAssertEqual(error as? CodexAccountError, .applicationLaunchFailed)
        }
        XCTAssertEqual(context.lifecycle.events, ["close", "launch"])
        XCTAssertEqual(try context.authFile.read(), authData("account-b"))
        XCTAssertEqual(context.store.activeAccountID, accountB.id)
        XCTAssertNil(context.store.pendingAccountID)
    }

    func testFirstManagedSwitchReplacesUnmanagedCurrentCredentialAfterClosingCodex() async throws {
        let context = try makeContext(initialData: authData("unmanaged"))
        let target = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [target]
        context.vault.storage[target.id] = authData("account-b")
        context.lifecycle.isRunning = true

        let outcome = try await context.service.requestSwitch(to: target.id)

        XCTAssertEqual(outcome, .switched)
        XCTAssertEqual(try context.authFile.read(), authData("account-b"))
        XCTAssertEqual(context.store.activeAccountID, target.id)
        XCTAssertEqual(context.lifecycle.events, ["close", "launch"])
    }

    func testDeleteAccountRemovesMetadataCredentialAndPendingSwitch() throws {
        let context = try makeContext(initialData: authData("current"))
        let profile = CodexAccountProfile(title: "待删除")
        context.store.profiles = [profile]
        context.store.pendingAccountID = profile.id
        context.vault.storage[profile.id] = authData("saved")

        try context.service.deleteAccount(id: profile.id)

        XCTAssertTrue(context.store.profiles.isEmpty)
        XCTAssertNil(context.store.pendingAccountID)
        XCTAssertNil(context.vault.storage[profile.id])
    }

    func testAuthCacheFileRejectsInvalidJSON() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAccountServiceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authFile = CodexAuthCacheFile(url: directory.appendingPathComponent("auth.json"))

        XCTAssertThrowsError(try authFile.replace(with: Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? CodexAccountError, .invalidAuthCache)
        }
        XCTAssertFalse(authFile.exists)
    }

    func testAuthCacheFileCreatesPrivateDirectoryAndFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAccountServiceTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let authURL = directory.appendingPathComponent("auth.json")
        let authFile = CodexAuthCacheFile(url: authURL)

        try authFile.replace(with: authData("private"))

        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: authURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testViewModelSwitchesAndPublishesCompletionMessage() async throws {
        let context = try makeContext(initialData: authData("account-a"))
        let accountA = CodexAccountProfile(title: "账号 A")
        let accountB = CodexAccountProfile(title: "账号 B")
        context.store.profiles = [accountA, accountB]
        context.store.activeAccountID = accountA.id
        context.vault.storage[accountA.id] = authData("account-a")
        context.vault.storage[accountB.id] = authData("account-b")
        let viewModel = CodexAccountViewModel(service: context.service)

        let message = await viewModel.requestSwitch(id: accountB.id)

        XCTAssertEqual(message, "账号已切换，Codex 已重新打开")
        XCTAssertFalse(viewModel.isSwitching)
        XCTAssertEqual(context.store.activeAccountID, accountB.id)
    }

    private func makeContext(
        initialData: Data,
        statusProvider: CodexAccountStatusProviding = CodexAccountStatusService()
    ) throws -> TestContext {
        let suiteName = "CodexAccountServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = CodexAccountStore(
            defaults: defaults,
            profilesKey: "profiles",
            activeIDKey: "active",
            pendingIDKey: "pending"
        )
        let vault = InMemoryCodexAuthCacheVault()
        let lifecycle = FakeCodexApplicationLifecycleController()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexAccountServiceTests-\(UUID().uuidString)")
        let authFile = CodexAuthCacheFile(url: directory.appendingPathComponent("auth.json"))
        try authFile.replace(with: initialData)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let service = CodexAccountService(
            store: store,
            vault: vault,
            authCacheFile: authFile,
            applicationLifecycle: lifecycle,
            statusProvider: statusProvider,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        return TestContext(
            service: service,
            store: store,
            vault: vault,
            authFile: authFile,
            lifecycle: lifecycle
        )
    }

    private func authData(_ value: String) -> Data {
        Data("{\"tokens\":{\"access_token\":\"\(value)\"}}".utf8)
    }
}

private final class FakeCodexAccountStatusProvider: CodexAccountStatusProviding {
    var preparedCredential: Data?
    var refreshError: Error?
    private(set) var preparedInputs: [Data] = []
    private(set) var refreshInputs: [Data] = []
    private(set) var allowCredentialRefreshValues: [Bool] = []

    func prepareCredential(_ authCache: Data) async throws -> Data {
        preparedInputs.append(authCache)
        return preparedCredential ?? authCache
    }

    func refreshStatus(
        authCache: Data,
        accountID: String?,
        allowCredentialRefresh: Bool
    ) async throws -> CodexAccountStatusRefreshResult {
        refreshInputs.append(authCache)
        allowCredentialRefreshValues.append(allowCredentialRefresh)
        if let refreshError { throw refreshError }
        return CodexAccountStatusRefreshResult(
            status: CodexAccountStatusSnapshot(
                fiveHour: nil,
                weekly: nil,
                resetCreditsAvailable: nil,
                subscriptionActiveUntil: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            planType: nil,
            refreshedAuthCache: nil
        )
    }
}

@MainActor
private struct TestContext {
    let service: CodexAccountService
    let store: CodexAccountStore
    let vault: InMemoryCodexAuthCacheVault
    let authFile: CodexAuthCacheFile
    let lifecycle: FakeCodexApplicationLifecycleController
}

private final class InMemoryCodexAuthCacheVault: CodexAuthCacheVaulting {
    var storage: [UUID: Data] = [:]

    func save(_ data: Data, for accountID: UUID) throws {
        storage[accountID] = data
    }

    func load(for accountID: UUID) throws -> Data {
        guard let data = storage[accountID] else { throw CodexAccountError.authCacheMissing }
        return data
    }

    func delete(for accountID: UUID) throws {
        storage.removeValue(forKey: accountID)
    }
}

@MainActor
private final class FakeCodexApplicationLifecycleController: CodexApplicationLifecycleControlling {
    var isRunning = false
    var closeError: Error?
    var launchError: Error?
    var onClose: (() throws -> Void)?
    private(set) var events: [String] = []

    func closeAndWait() async throws {
        events.append("close")
        try onClose?()
        if let closeError { throw closeError }
        isRunning = false
    }

    func launch() async throws {
        events.append("launch")
        if let launchError { throw launchError }
        isRunning = true
    }
}

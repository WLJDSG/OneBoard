import CloudKit
import Foundation

protocol CloudConfigurationStoring: Sendable {
    func load() async throws -> ConfigurationSnapshot?
    func save(_ snapshot: ConfigurationSnapshot) async throws
}

struct CloudKitConfigurationStore: CloudConfigurationStoring {
    private static let recordID = CKRecord.ID(recordName: "oneboard-configuration-v1")
    private let database: CKDatabase

    init(container: CKContainer = CKContainer(identifier: "iCloud.com.oneboard.mac")) {
        database = container.privateCloudDatabase
    }

    func load() async throws -> ConfigurationSnapshot? {
        do {
            let record = try await database.record(for: Self.recordID)
            guard let payload = record["payload"] as? Data else { throw ConfigurationSyncError.invalidSnapshot }
            return try JSONDecoder().decode(ConfigurationSnapshot.self, from: payload)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch let error as ConfigurationSyncError {
            throw error
        } catch {
            throw ConfigurationSyncError.iCloudUnavailable
        }
    }

    func save(_ snapshot: ConfigurationSnapshot) async throws {
        do {
            let record = (try? await database.record(for: Self.recordID))
                ?? CKRecord(recordType: "OneBoardConfiguration", recordID: Self.recordID)
            record["payload"] = try JSONEncoder().encode(snapshot) as CKRecordValue
            _ = try await database.save(record)
        } catch {
            throw ConfigurationSyncError.iCloudUnavailable
        }
    }
}

//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CloudKit
import CryptoKit
import Foundation
import GRDB

enum CloudSyncRecordType: String, CaseIterable, Sendable {
    case book = "Book"
    case progress = "ReadingProgress"
    case bookmark = "Bookmark"
    case highlight = "Highlight"

    var recordNamePrefix: String {
        switch self {
        case .book: return "book"
        case .progress: return "progress"
        case .bookmark: return "bookmark"
        case .highlight: return "highlight"
        }
    }
}

enum CloudSyncIdentifier {
    static func book(identifier: String?) -> String {
        guard let identifier, !identifier.isEmpty else {
            return "book-\(UUID().uuidString.lowercased())"
        }
        return "book-\(sha256(identifier))"
    }

    static func progress(forBookSyncID bookSyncID: String) -> String {
        "progress-\(bookSyncID)"
    }

    static func bookmark() -> String {
        "bookmark-\(UUID().uuidString.lowercased())"
    }

    static func highlight() -> String {
        "highlight-\(UUID().uuidString.lowercased())"
    }

    static func stableBook(identifier: String?, fallbackID: Int64) -> String {
        guard let identifier, !identifier.isEmpty else {
            return "book-legacy-\(fallbackID)"
        }
        return "book-\(sha256(identifier))"
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct SyncTombstone: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "syncTombstone"

    let recordType: String
    let syncID: String
    let deletedAt: Date
}

struct CloudRecordMetadata: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "cloudRecordMetadata"

    let recordType: String
    let syncID: String
    let systemFields: Data
}

enum CloudSyncPreferences {
    static let enabledKey = "cloud_sync_enabled"
    static let lastSuccessfulSyncKey = "cloud_sync_last_success"
    static let stateSerializationKey = "cloud_sync_engine_state"

    static var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            NotificationCenter.default.post(name: .cloudSyncPreferenceDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let cloudSyncLocalDataDidChange = Notification.Name("PagePilot.CloudSyncLocalDataDidChange")
    static let cloudSyncPreferenceDidChange = Notification.Name("PagePilot.CloudSyncPreferenceDidChange")
    static let cloudSyncStatusDidChange = Notification.Name("PagePilot.CloudSyncStatusDidChange")
}

enum CloudSyncStatus: Equatable, Sendable {
    case disabled
    case starting
    case syncing
    case synced(Date)
    case unavailable(String)
    case failed(String)
}

struct CloudSyncMergePolicy {
    /// Last-write-wins is deliberately based on the domain timestamp rather
    /// than CloudKit's server modification date, so offline edits can be
    /// compared consistently after either device reconnects.
    static func remoteWins(localUpdatedAt: Date, remoteUpdatedAt: Date) -> Bool {
        remoteUpdatedAt >= localUpdatedAt
    }
}

extension CKRecord {
    func encodedSystemFields() throws -> Data {
        let data = NSMutableData()
        let archiver = NSKeyedArchiver(forWritingWith: data)
        archiver.requiresSecureCoding = true
        encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        return data as Data
    }

    static func fromSystemFields(_ data: Data) throws -> CKRecord? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = true
        defer { unarchiver.finishDecoding() }
        return CKRecord(coder: unarchiver)
    }
}

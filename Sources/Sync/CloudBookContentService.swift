//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CloudKit
import Foundation
import ReadiumShared

/// Stores publication files separately from the automatically-synced library zone.
///
/// `CKSyncEngine` only handles lightweight library metadata. EPUB/PDF assets live in
/// a dedicated zone and are fetched explicitly when the user opens a cloud-only book.
final actor CloudBookContentService {
    static let zoneName = "PagePilotContent"
    static let recordType = "BookContent"

    private let database: CKDatabase
    private let contentZone = CKRecordZone(zoneName: CloudBookContentService.zoneName)
    private var isZoneReady = false

    init(container: CKContainer = CKContainer(identifier: CloudSyncService.containerIdentifier)) {
        database = container.privateCloudDatabase
    }

    func uploadIfNeeded(syncID: String, fileURL: URL?, fileName: String?) async throws {
        guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        try await saveContent(
            syncID: syncID,
            fileURL: fileURL,
            fileName: fileName ?? fileURL.lastPathComponent
        )
    }

    /// Downloads a publication only after an explicit user action.
    ///
    /// During the v1 -> v2 transition, fall back to the legacy `Book.publication`
    /// asset so users do not lose access before another device has republished the
    /// file into the dedicated content zone.
    func download(syncID: String, title: String) async throws -> AnyURL {
        guard CloudSyncAccessPolicy.canSync(
            isEnabled: CloudSyncPreferences.isEnabled,
            hasProAccess: ProPurchaseManager.shared.hasProAccess
        ) else {
            throw LibraryError.bookNotFound
        }

        try await prepareZoneIfNeeded()

        let payload: (asset: CKAsset, fileName: String)
        do {
            let record = try await database.record(for: contentRecordID(for: syncID))
            guard let asset = record["publication"] as? CKAsset else {
                throw LibraryError.bookNotFound
            }
            payload = (asset, (record["fileName"] as? String) ?? title)
        } catch let error as CKError where error.code == .unknownItem {
            payload = try await legacyPayload(syncID: syncID, title: title)
        }

        guard let assetURL = payload.asset.fileURL else {
            throw LibraryError.bookNotFound
        }

        let destination = Paths.documents.appendingUniquePathComponent(safeFilename(payload.fileName))
        do {
            try FileManager.default.copyItem(at: assetURL, to: destination.url)
        } catch {
            throw LibraryError.downloadFailed(error)
        }

        return destination.anyURL
    }

    func delete(syncID: String) async throws {
        try await prepareZoneIfNeeded()
        do {
            _ = try await database.deleteRecord(withID: contentRecordID(for: syncID))
        } catch let error as CKError where error.code == .unknownItem {
            return
        }
    }

    private func saveContent(syncID: String, fileURL: URL, fileName: String) async throws {
        try await prepareZoneIfNeeded()

        let recordID = contentRecordID(for: syncID)
        let record: CKRecord
        do {
            record = try await database.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        }

        record["schemaVersion"] = Int64(1)
        record["bookSyncID"] = syncID
        record["fileName"] = fileName
        record["publication"] = CKAsset(fileURL: fileURL)
        record["updatedAt"] = Date()
        _ = try await database.save(record)
    }

    private func prepareZoneIfNeeded() async throws {
        guard !isZoneReady else { return }

        do {
            _ = try await database.recordZone(for: contentZone.zoneID)
        } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
            _ = try await database.save(contentZone)
        }
        isZoneReady = true
    }

    private func legacyPayload(syncID: String, title: String) async throws -> (asset: CKAsset, fileName: String) {
        let legacyZone = CKRecordZone(zoneName: CloudSyncService.zoneName)
        let recordID = CKRecord.ID(recordName: syncID, zoneID: legacyZone.zoneID)
        let record = try await database.record(for: recordID)
        guard let asset = record["publication"] as? CKAsset else {
            throw LibraryError.bookNotFound
        }
        return (asset, (record["fileName"] as? String) ?? title)
    }

    private func contentRecordID(for syncID: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "content-\(syncID)", zoneID: contentZone.zoneID)
    }

    private func safeFilename(_ filename: String) -> String {
        let value = URL(fileURLWithPath: filename).lastPathComponent
        return value.isEmpty ? UUID().uuidString : value
    }
}

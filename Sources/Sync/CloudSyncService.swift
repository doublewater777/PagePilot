//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import CloudKit
import Foundation

/// Bidirectional iCloud sync for the user's private PagePilot library.
///
/// GRDB remains the source of truth. CKSyncEngine is the transport: local writes
/// set a durable `needsSync` bit (or deletion tombstone), then this service
/// projects those rows into CloudKit records. Fetched records are merged back
/// into GRDB before CKSyncEngine state is persisted.
final actor CloudSyncService: CKSyncEngineDelegate {
    static let containerIdentifier = "iCloud.com.panyang.PagePilot"
    static let zoneName = "PagePilotSync"

    private let store: CloudSyncStore
    private let defaults: UserDefaults
    private let zone = CKRecordZone(zoneName: CloudSyncService.zoneName)

    private var syncEngine: CKSyncEngine?
    private var localChangesTask: Task<Void, Never>?
    private var preferenceTask: Task<Void, Never>?
    private var enqueueTask: Task<Void, Never>?
    private var status: CloudSyncStatus = .starting
    private var canPersistEngineState = true

    init(db: Database, defaults: UserDefaults = .standard) {
        store = CloudSyncStore(db: db)
        self.defaults = defaults
    }

    deinit {
        localChangesTask?.cancel()
        preferenceTask?.cancel()
        enqueueTask?.cancel()
    }

    func start() async {
        installObserversIfNeeded()
        await configureForCurrentPreference()
    }

    func currentStatus() -> CloudSyncStatus {
        status
    }

    func syncNow() async {
        guard CloudSyncPreferences.isEnabled(in: defaults) else {
            await setStatus(.disabled)
            return
        }
        if syncEngine == nil {
            await configureForCurrentPreference()
        }
        guard let syncEngine else { return }

        await setStatus(.syncing)
        do {
            try await enqueueDirtyChanges()
            try await syncEngine.fetchChanges()
            try await enqueueDirtyChanges()
            try await syncEngine.sendChanges()
            try await updateSettledStatus()
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    // MARK: - Lifecycle

    private func configureForCurrentPreference() async {
        guard CloudSyncPreferences.isEnabled(in: defaults) else {
            if let syncEngine {
                await syncEngine.cancelOperations()
            }
            syncEngine = nil
            await setStatus(.disabled)
            return
        }

        await setStatus(.starting)
        do {
            try await store.prepareStableIDs()

            let container = CKContainer(identifier: Self.containerIdentifier)
            let state = loadStateSerialization()
            var configuration = CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: state,
                delegate: self
            )
            configuration.automaticallySync = true
            configuration.subscriptionID = "PagePilotSyncSubscription"

            let engine = CKSyncEngine(configuration)
            syncEngine = engine
            engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
            try await enqueueDirtyChanges()

            // Do one eager pull on launch; automatic scheduling and push wakes
            // handle subsequent syncs.
            try await engine.fetchChanges()
            try await updateSettledStatus()
        } catch let error as CKError where error.code == .notAuthenticated {
            await setStatus(.unavailable("iCloud account unavailable"))
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func installObserversIfNeeded() {
        guard localChangesTask == nil else { return }

        localChangesTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .cloudSyncLocalDataDidChange) {
                guard !Task.isCancelled, let self else { break }
                await self.scheduleEnqueue()
            }
        }

        preferenceTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .cloudSyncPreferenceDidChange) {
                guard !Task.isCancelled, let self else { break }
                await self.configureForCurrentPreference()
            }
        }
    }

    private func scheduleEnqueue() {
        enqueueTask?.cancel()
        enqueueTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self else { return }
            try? await self.enqueueDirtyChanges()
        }
    }

    /// Adds a bounded slice of the durable GRDB outbox to CKSyncEngine. Sending
    /// another slice after each completion avoids a huge first-launch engine
    /// state for users with large libraries.
    private func enqueueDirtyChanges() async throws {
        guard CloudSyncPreferences.isEnabled(in: defaults), let syncEngine else { return }
        let changes = try await store.pendingChanges(limit: 400)
        guard !changes.isEmpty else { return }

        var pending: [CKSyncEngine.PendingRecordZoneChange] = []
        pending.reserveCapacity(changes.count)
        for change in changes {
            let recordID = CKRecord.ID(recordName: change.syncID, zoneID: zone.zoneID)
            switch change.kind {
            case .save:
                pending.append(.saveRecord(recordID))
            case .delete:
                pending.append(.deleteRecord(recordID))
            }
        }
        syncEngine.state.add(pendingRecordZoneChanges: pending)
    }

    // MARK: - CKSyncEngineDelegate

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let store = self.store

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            do {
                if let record = try await store.record(for: recordID) {
                    return record
                }
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            } catch {
                return nil
            }
        }
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let event):
            if canPersistEngineState {
                saveStateSerialization(event.stateSerialization)
            }

        case .accountChange(let event):
            await handleAccountChange(event, syncEngine: syncEngine)

        case .fetchedDatabaseChanges(let event):
            await handleFetchedDatabaseChanges(event, syncEngine: syncEngine)

        case .fetchedRecordZoneChanges(let event):
            await handleFetchedRecordZoneChanges(event, syncEngine: syncEngine)

        case .sentRecordZoneChanges(let event):
            await handleSentRecordZoneChanges(event, syncEngine: syncEngine)

        case .willFetchChanges, .willSendChanges:
            await setStatus(.syncing)

        case .didFetchChanges, .didSendChanges:
            await updateSettledStatusIgnoringErrors()

        case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
            break

        @unknown default:
            break
        }
    }

    private func handleFetchedRecordZoneChanges(
        _ event: CKSyncEngine.Event.FetchedRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        do {
            let records = event.modifications.map(\.record)
            let localWins = try await store.applyFetchedRecords(records)
            for deletion in event.deletions {
                try await store.applyRemoteDeletion(deletion.recordID)
            }

            if !localWins.isEmpty {
                syncEngine.state.add(
                    pendingRecordZoneChanges: localWins.map { .saveRecord($0) }
                )
            }
            canPersistEngineState = true
        } catch {
            // Do not checkpoint past a remote batch that failed to reach GRDB.
            // If the process restarts, the last durable CKSyncEngine state will
            // cause CloudKit to deliver the batch again.
            canPersistEngineState = false
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func handleFetchedDatabaseChanges(
        _ event: CKSyncEngine.Event.FetchedDatabaseChanges,
        syncEngine: CKSyncEngine
    ) async {
        guard event.deletions.contains(where: { $0.zoneID == zone.zoneID }) else { return }
        do {
            // A server-side zone reset must never erase the user's local books.
            // Recreate the zone and republish the local cache instead.
            try await store.markEverythingDirtyAndClearServerMetadata()
            syncEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
            try await enqueueDirtyChanges()
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func handleSentRecordZoneChanges(
        _ event: CKSyncEngine.Event.SentRecordZoneChanges,
        syncEngine: CKSyncEngine
    ) async {
        do {
            for record in event.savedRecords {
                try await store.acknowledgeSavedRecord(record)
            }
            for recordID in event.deletedRecordIDs {
                try await store.acknowledgeDeletedRecord(recordID)
            }

            var recordRetries: [CKSyncEngine.PendingRecordZoneChange] = []
            var databaseRetries: [CKSyncEngine.PendingDatabaseChange] = []

            for failure in event.failedRecordSaves {
                let recordID = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    if let serverRecord = failure.error.serverRecord {
                        let localWins = try await store.applyRemoteRecord(serverRecord)
                        if localWins {
                            recordRetries.append(.saveRecord(recordID))
                        }
                    } else {
                        recordRetries.append(.saveRecord(recordID))
                    }

                case .zoneNotFound:
                    try await store.clearMetadata(for: recordID)
                    databaseRetries.append(.saveZone(zone))
                    recordRetries.append(.saveRecord(recordID))

                case .unknownItem:
                    try await store.clearMetadata(for: recordID)
                    recordRetries.append(.saveRecord(recordID))

                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .accountTemporarilyUnavailable, .requestRateLimited,
                     .operationCancelled:
                    // CKSyncEngine retains/retries these automatically.
                    break

                default:
                    await setStatus(.failed(failure.error.localizedDescription))
                }
            }

            for (recordID, error) in event.failedRecordDeletes {
                switch error.code {
                case .unknownItem:
                    try await store.acknowledgeDeletedRecord(recordID)
                case .zoneNotFound:
                    databaseRetries.append(.saveZone(zone))
                    recordRetries.append(.deleteRecord(recordID))
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
                     .notAuthenticated, .accountTemporarilyUnavailable, .requestRateLimited,
                     .operationCancelled:
                    break
                default:
                    if try await store.isDeletePending(recordID) {
                        recordRetries.append(.deleteRecord(recordID))
                    }
                    await setStatus(.failed(error.localizedDescription))
                }
            }

            if !databaseRetries.isEmpty {
                syncEngine.state.add(pendingDatabaseChanges: databaseRetries)
            }
            if !recordRetries.isEmpty {
                syncEngine.state.add(pendingRecordZoneChanges: recordRetries)
            }

            try await enqueueDirtyChanges()
            try await updateSettledStatus()
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func handleAccountChange(
        _ event: CKSyncEngine.Event.AccountChange,
        syncEngine: CKSyncEngine
    ) async {
        switch event.changeType {
        case .signOut:
            await setStatus(.unavailable("iCloud account unavailable"))

        case .signIn, .switchAccounts:
            do {
                // Keep the local-first library intact. CKSyncEngine resets its
                // account-scoped state; record system fields are account-scoped
                // too, so discard them and publish the local cache to the newly
                // active private database.
                try await store.markEverythingDirtyAndClearServerMetadata()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
                try await enqueueDirtyChanges()
                await setStatus(.syncing)
            } catch {
                await setStatus(.failed(error.localizedDescription))
            }

        @unknown default:
            break
        }
    }

    // MARK: - State / status

    private func loadStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = defaults.data(forKey: CloudSyncPreferences.stateSerializationKey) else {
            return nil
        }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveStateSerialization(_ state: CKSyncEngine.State.Serialization) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: CloudSyncPreferences.stateSerializationKey)
    }

    private func updateSettledStatusIgnoringErrors() async {
        do {
            try await updateSettledStatus()
        } catch {
            await setStatus(.failed(error.localizedDescription))
        }
    }

    private func updateSettledStatus() async throws {
        let pending = try await store.pendingChanges(limit: 1)
        if pending.isEmpty {
            let date = Date()
            defaults.set(date, forKey: CloudSyncPreferences.lastSuccessfulSyncKey)
            await setStatus(.synced(date))
        } else {
            await setStatus(.syncing)
        }
    }

    private func setStatus(_ newStatus: CloudSyncStatus) async {
        guard status != newStatus else { return }
        status = newStatus
        await MainActor.run {
            NotificationCenter.default.post(
                name: .cloudSyncStatusDidChange,
                object: newStatus
            )
        }
    }
}

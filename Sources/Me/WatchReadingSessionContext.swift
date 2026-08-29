//
//  Copyright 2026 PagePilot. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Bridges the Reader's active reading-session lifecycle into the existing
/// Watch application context without introducing a second Watch protocol.
///
/// The values are persisted because `WatchPageTurnSettings.watchContext` can
/// be rebuilt from several call sites (settings changes, progress updates,
/// reconnects). Keeping the session state here makes every rebuilt context
/// carry the same authoritative session snapshot.
enum WatchReadingSessionContext {
    enum Keys {
        static let isActive = "readingSessionActive"
        static let startedAt = "readingSessionStartedAt"
        static let startProgress = "readingSessionStartProgress"
    }

    private enum StorageKeys {
        static let isActive = "watch_reading_session_active"
        static let startedAt = "watch_reading_session_started_at"
        static let startProgress = "watch_reading_session_start_progress"
    }

    private static let defaults = UserDefaults.standard

    static var contextValues: [String: Any] {
        let active = defaults.bool(forKey: StorageKeys.isActive)
        return [
            Keys.isActive: active,
            Keys.startedAt: active ? defaults.double(forKey: StorageKeys.startedAt) : 0.0,
            Keys.startProgress: active ? defaults.double(forKey: StorageKeys.startProgress) : 0.0,
        ]
    }

    /// Starts a Watch-visible session only for a visual Reader. Audiobooks use
    /// the same base ReaderViewController lifecycle but do not register a
    /// VisualNavigator with WatchPageTurnService, so they intentionally no-op.
    static func begin(at startDate: Date, progression: Double) {
        guard WatchPageTurnService.shared.isReaderReady else { return }

        defaults.set(true, forKey: StorageKeys.isActive)
        defaults.set(startDate.timeIntervalSince1970, forKey: StorageKeys.startedAt)
        defaults.set(clampProgress(progression), forKey: StorageKeys.startProgress)
        publishCurrentReaderContext()
    }

    static func end() {
        guard defaults.bool(forKey: StorageKeys.isActive) else { return }

        defaults.set(false, forKey: StorageKeys.isActive)
        defaults.removeObject(forKey: StorageKeys.startedAt)
        defaults.removeObject(forKey: StorageKeys.startProgress)
        publishCurrentReaderContext()
    }

    private static func publishCurrentReaderContext() {
        let service = WatchPageTurnService.shared
        service.updateProgress(
            title: service.currentBookTitle,
            progression: service.currentBookProgress
        )
    }

    private static func clampProgress(_ value: Double) -> Double {
        min(max(value, 0.0), 1.0)
    }
}

//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation
import os

extension Notification.Name {
    static let readingStatsDidChange = Notification.Name("readingStatsDidChange")
}

enum ReadingHistoryAccess {
    static func canAccess(hasProAccess: Bool) -> Bool {
        hasProAccess
    }
}

enum ReadingStatsScope: String, CaseIterable, Identifiable {
    case summary
    case day
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summary:
            return NSLocalizedString("stats_tab_summary", comment: "")
        case .day:
            return NSLocalizedString("stats_tab_day", comment: "")
        case .week:
            return NSLocalizedString("stats_tab_week", comment: "")
        case .month:
            return NSLocalizedString("stats_tab_month", comment: "")
        case .year:
            return NSLocalizedString("stats_tab_year", comment: "")
        }
    }

    var requiresPro: Bool {
        self != .day
    }
}

struct DailyReadingStat: Codable, Identifiable {
    let dateKey: String
    var seconds: Int
    var sessions: Int
    var bookIds: [String]
    var bookSeconds: [String: Int]?
    var hourlySeconds: [Int: Int]? // Key: hour (0-23), Value: seconds read in that hour
    // Stored atomically with daily totals so resumed checkpoints cannot be counted twice.
    var checkpointedSessionSeconds: [String: Int]?
    // A single reading session is counted once in each touched local day.
    var checkpointedSessionIDs: [String]?
    // True wall-clock timestamp of the last committed monotonic checkpoint.
    var checkpointedSessionObservedAt: [String: Date]?

    var id: String { dateKey }
}

struct ReadingBadge: Identifiable, Codable, Equatable {
    let id: String // e.g., "early_bird", "night_owl"
    let titleKey: String
    let descKey: String
    let iconName: String
    let isUnlocked: Bool
    let progress: Double // 0.0 to 1.0
    let currentValue: Int
    let targetValue: Int
}

struct ReadingStatsSnapshot {
    var totalSeconds: Int = 0
    var activeDays: Int = 0
    var sessions: Int = 0
    var distinctBooks: Int = 0
    var averageSecondsPerActiveDay: Int = 0
    var currentStreakDays: Int = 0
    var bestDaySeconds: Int = 0
    var dailyStats: [DailyReadingStat] = []
    var badges: [ReadingBadge] = []

    static let empty = ReadingStatsSnapshot()
}

private struct PendingFinalReadingCheckpoint: Codable {
    let sessionID: String
    let startedAt: Date
    let elapsedSeconds: Int
    let recordedAt: Date
    let bookId: Book.Id
}

final class ReadingStatsStore {
    static let shared = ReadingStatsStore()

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let storageURL: URL
    private let finalRecoveryURL: URL
    private let decoder = JSONDecoder()
    private let encodeStats: ([String: DailyReadingStat]) throws -> Data
    private static let ioQueue = DispatchQueue(label: "PagePilot.ReadingStatsStore.IO", qos: .utility)
    // Accessed only on ioQueue. Stats screens reuse committed memory without
    // decoding the full JSON file after each 15-second checkpoint notification.
    private static var committedCache: [URL: [String: DailyReadingStat]] = [:]
    // This is a best-effort in-process fallback when the recovery journal
    // itself is temporarily unwritable. Only journaled entries survive restart.
    private static var transientFinals: [URL: [String: PendingFinalReadingCheckpoint]] = [:]
    private let signposter = OSSignposter(subsystem: "PagePilot", category: "ReadingStatsStore")

    private enum Keys {
        static let dailyStats = "readingStats_dailyStats"
        static let didMigrateDailyStats = "readingStats_didMigrateDailyStatsToFile"
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .autoupdatingCurrent
            return calendar
        }(),
        storageURL: URL? = nil,
        finalRecoveryURL: URL? = nil,
        encodeStats: @escaping ([String: DailyReadingStat]) throws -> Data = { try JSONEncoder().encode($0) }
    ) {
        self.defaults = defaults
        self.calendar = calendar
        let resolvedStorageURL = storageURL ?? Self.defaultStorageURL()
        self.storageURL = resolvedStorageURL
        self.finalRecoveryURL = finalRecoveryURL ?? (storageURL == nil
            ? Paths.library.url
                .appendingPathComponent("ReadingStatsRecovery", isDirectory: true)
                .appendingPathComponent("pending-final-v1.json")
            : resolvedStorageURL.deletingLastPathComponent()
                .appendingPathComponent("pending-final-v1.json"))
        self.encodeStats = encodeStats
        Self.ioQueue.async { [self] in
            _ = replayPendingFinalCheckpoints()
        }
    }

    func recordReadingSession(startDate: Date, endDate: Date = Date(), bookId: Book.Id) {
        guard endDate > startDate else { return }

        var segmentStart = startDate
        while segmentStart < endDate {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: segmentStart)) ?? endDate
            let segmentEnd = min(nextDay, endDate)
            let seconds = Int(segmentEnd.timeIntervalSince(segmentStart).rounded())

            recordReadingSession(seconds: seconds, bookId: bookId, date: segmentStart)
            segmentStart = segmentEnd
        }
    }

    /// A checkpoint records a monotonic elapsed cursor and an independently
    /// sampled wall-clock time. Only the new interval is attributed to the
    /// calendar. Repeated/decreasing cursors are no-ops.
    ///
    /// Returns false if the atomic write failed; the committed cursor is then
    /// unchanged and the entire interval can safely be retried.
    @discardableResult
    func recordReadingCheckpoint(
        sessionID: String,
        startedAt: Date,
        elapsedSeconds: Int,
        recordedAt: Date,
        bookId: Book.Id
    ) -> Bool {
        Self.ioQueue.sync {
            commitCheckpoint(
                sessionID: sessionID,
                startedAt: startedAt,
                elapsedSeconds: elapsedSeconds,
                recordedAt: recordedAt,
                bookId: bookId
            )
        }
    }

    /// The Reader always uses this asynchronous entrypoint, ensuring JSON
    /// decoding, calendar aggregation and atomic writes never run on its UI timer.
    func enqueueReadingCheckpoint(
        sessionID: String,
        startedAt: Date,
        elapsedSeconds: Int,
        recordedAt: Date,
        bookId: Book.Id,
        completion: ((Bool) -> Void)? = nil
    ) {
        Self.ioQueue.async {
            let success = self.commitCheckpoint(
                sessionID: sessionID,
                startedAt: startedAt,
                elapsedSeconds: elapsedSeconds,
                recordedAt: recordedAt,
                bookId: bookId
            )
            if let completion {
                DispatchQueue.main.async { completion(success) }
            }
        }
    }

    /// The final interval is journaled separately before attempting the main
    /// aggregate write. Failed aggregate commits remain eligible for replay
    /// on foreground activation and on the next process launch.
    func enqueueFinalReadingCheckpoint(
        sessionID: String,
        startedAt: Date,
        elapsedSeconds: Int,
        recordedAt: Date,
        bookId: Book.Id,
        completion: @escaping (Bool) -> Void
    ) {
        Self.ioQueue.async {
            let entry = PendingFinalReadingCheckpoint(
                sessionID: sessionID,
                startedAt: startedAt,
                elapsedSeconds: elapsedSeconds,
                recordedAt: recordedAt,
                bookId: bookId
            )
            self.stagePendingFinalCheckpoint(entry)
            let saved = self.commitCheckpoint(
                sessionID: sessionID,
                startedAt: startedAt,
                elapsedSeconds: elapsedSeconds,
                recordedAt: recordedAt,
                bookId: bookId
            )
            if saved { self.removePendingFinalCheckpoint(sessionID: sessionID) }
            DispatchQueue.main.async { completion(saved) }
        }
    }

    /// Explicit retry on activation. The initializer also schedules a replay,
    /// so entries from a previous process are recovered without opening Reader.
    func enqueuePendingFinalCheckpointRetry() {
        Self.ioQueue.async {
            _ = self.replayPendingFinalCheckpoints()
        }
    }

    /// Test seam: synchronously replay on the same queue as all writers.
    @discardableResult
    func retryPendingFinalCheckpoints() -> Bool {
        Self.ioQueue.sync { replayPendingFinalCheckpoints() }
    }

    // The following helpers are called only from the process-wide IO queue.
    private func readPendingFinalCheckpoints() -> [String: PendingFinalReadingCheckpoint] {
        guard let data = try? Data(contentsOf: finalRecoveryURL),
              let pending = try? decoder.decode([String: PendingFinalReadingCheckpoint].self, from: data)
        else { return [:] }
        return pending
    }

    @discardableResult
    private func writePendingFinalCheckpoints(
        _ pending: [String: PendingFinalReadingCheckpoint]
    ) -> Bool {
        do {
            let data = try JSONEncoder().encode(pending)
            try FileManager.default.createDirectory(
                at: finalRecoveryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: finalRecoveryURL, options: [.atomic])
            return true
        } catch {
            print("ReadingStatsStore: failed to persist final checkpoint journal: \(error)")
            return false
        }
    }

    private func stagePendingFinalCheckpoint(_ checkpoint: PendingFinalReadingCheckpoint) {
        var pending = readPendingFinalCheckpoints()
        pending[checkpoint.sessionID] = checkpoint
        var transient = Self.transientFinals[finalRecoveryURL] ?? [:]
        transient[checkpoint.sessionID] = checkpoint
        Self.transientFinals[finalRecoveryURL] = transient
        if writePendingFinalCheckpoints(pending) {
            transient.removeValue(forKey: checkpoint.sessionID)
            Self.transientFinals[finalRecoveryURL] = transient
        }
    }

    private func removePendingFinalCheckpoint(sessionID: String) {
        var pending = readPendingFinalCheckpoints()
        guard pending[sessionID] != nil else {
            Self.transientFinals[finalRecoveryURL]?.removeValue(forKey: sessionID)
            return
        }
        pending.removeValue(forKey: sessionID)
        if writePendingFinalCheckpoints(pending) {
            Self.transientFinals[finalRecoveryURL]?.removeValue(forKey: sessionID)
        }
        // Failed deletion is harmless: replay is idempotent by sessionID/cursor.
    }

    private func replayPendingFinalCheckpoints() -> Bool {
        var pending = readPendingFinalCheckpoints()
        for (id, checkpoint) in Self.transientFinals[finalRecoveryURL] ?? [:] {
            pending[id] = checkpoint
        }
        var allSaved = true
        for checkpoint in pending.values.sorted(by: { $0.sessionID < $1.sessionID }) {
            let saved = commitCheckpoint(
                sessionID: checkpoint.sessionID,
                startedAt: checkpoint.startedAt,
                elapsedSeconds: checkpoint.elapsedSeconds,
                recordedAt: checkpoint.recordedAt,
                bookId: checkpoint.bookId
            )
            if saved {
                removePendingFinalCheckpoint(sessionID: checkpoint.sessionID)
            } else {
                allSaved = false
            }
        }
        return allSaved
    }

    private func commitCheckpoint(
        sessionID: String,
        startedAt: Date,
        elapsedSeconds: Int,
        recordedAt: Date,
        bookId: Book.Id
    ) -> Bool {
        guard !sessionID.isEmpty, elapsedSeconds > 0 else { return true }
        let interval = signposter.beginInterval("CheckpointPersist")
        defer { signposter.endInterval("CheckpointPersist", interval) }

        var statsByDate = loadStatsByDate()
        let existingAnchor = statsByDate.first {
            $0.value.checkpointedSessionSeconds?[sessionID] != nil
        }?.key
        let committed = statsByDate.values.compactMap {
            $0.checkpointedSessionSeconds?[sessionID]
        }.max() ?? 0
        guard elapsedSeconds > committed else { return true }

        let delta = elapsedSeconds - committed
        // Anchor THIS delta at the observed wall time. startedAt + uptime
        // would incorrectly assign days if the system clock changed.
        let intervalStart = recordedAt.addingTimeInterval(-Double(delta))
        var offset = 0
        while offset < delta {
            let segmentDate = intervalStart.addingTimeInterval(TimeInterval(offset))
            let hourEnd = calendar.dateInterval(of: .hour, for: segmentDate)?.end
                ?? segmentDate.addingTimeInterval(3600)
            let dayEnd = calendar.dateInterval(of: .day, for: segmentDate)?.end
                ?? segmentDate.addingTimeInterval(86400)
            let boundary = min(hourEnd, dayEnd)
            // Always advance even in unusual calendar transitions.
            let endOffset = min(delta, max(offset + 1, Int(ceil(boundary.timeIntervalSince(intervalStart)))))
            let seconds = endOffset - offset
            let key = dateKey(for: segmentDate)
            var stat = statsByDate[key] ?? DailyReadingStat(
                dateKey: key,
                seconds: 0,
                sessions: 0,
                bookIds: [],
                bookSeconds: [:],
                hourlySeconds: [:]
            )
            var ids = stat.checkpointedSessionIDs ?? []
            if !ids.contains(sessionID) {
                ids.append(sessionID)
                stat.sessions += 1
            }
            stat.checkpointedSessionIDs = ids

            stat.seconds += seconds
            let bookKey = bookId.string
            if !stat.bookIds.contains(bookKey) { stat.bookIds.append(bookKey) }
            var perBook = stat.bookSeconds ?? [:]
            perBook[bookKey, default: 0] += seconds
            stat.bookSeconds = perBook

            // Repeated autumn hours intentionally share the same 0...23
            // bucket, matching the existing 24-column hourly chart.
            let hour = calendar.component(.hour, from: segmentDate)
            var perHour = stat.hourlySeconds ?? [:]
            perHour[hour, default: 0] += seconds
            stat.hourlySeconds = perHour
            statsByDate[key] = stat
            offset = endOffset
        }

        let anchorKey = existingAnchor ?? dateKey(for: startedAt)
        var anchor = statsByDate[anchorKey] ?? DailyReadingStat(
            dateKey: anchorKey, seconds: 0, sessions: 0, bookIds: [],
            bookSeconds: [:], hourlySeconds: [:]
        )
        var cursors = anchor.checkpointedSessionSeconds ?? [:]
        cursors[sessionID] = elapsedSeconds
        anchor.checkpointedSessionSeconds = cursors
        var observations = anchor.checkpointedSessionObservedAt ?? [:]
        observations[sessionID] = recordedAt
        anchor.checkpointedSessionObservedAt = observations
        statsByDate[anchorKey] = anchor

        guard save(statsByDate) else { return false }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
        }
        return true
    }

    @discardableResult
    func recordReadingSession(seconds: Int, bookId: Book.Id, date: Date = Date()) -> Bool {
        guard seconds > 0 else { return true }
        return Self.ioQueue.sync {
            recordLegacyReadingSession(seconds: seconds, bookId: bookId, date: date)
        }
    }

    private func recordLegacyReadingSession(seconds: Int, bookId: Book.Id, date: Date) -> Bool {
        var statsByDate = loadStatsByDate()
        let key = dateKey(for: date)
        var stat = statsByDate[key] ?? DailyReadingStat(dateKey: key, seconds: 0, sessions: 0, bookIds: [], bookSeconds: [:], hourlySeconds: [:])

        stat.seconds += seconds
        stat.sessions += 1

        let bookIdString = bookId.string
        if !stat.bookIds.contains(bookIdString) {
            stat.bookIds.append(bookIdString)
        }

        var bSeconds = stat.bookSeconds ?? [:]
        bSeconds[bookIdString] = (bSeconds[bookIdString] ?? 0) + seconds
        stat.bookSeconds = bSeconds

        // Record hourly seconds
        let hour = calendar.component(.hour, from: date)
        var hSeconds = stat.hourlySeconds ?? [:]
        hSeconds[hour] = (hSeconds[hour] ?? 0) + seconds
        stat.hourlySeconds = hSeconds

        statsByDate[key] = stat
        guard save(statsByDate) else { return false }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
        }
        return true
    }

    func snapshot(for scope: ReadingStatsScope, referenceDate: Date = Date()) -> ReadingStatsSnapshot {
        let allStats = Self.ioQueue.sync { loadStatsByDate().values.sorted { $0.dateKey < $1.dateKey } }
        let filtered: [DailyReadingStat]

        switch scope {
        case .summary:
            filtered = allStats
        case .day:
            let key = dateKey(for: referenceDate)
            filtered = allStats.filter { $0.dateKey == key }
        case .week:
            filtered = allStats.filter { date(from: $0.dateKey).map { calendar.isDate($0, equalTo: referenceDate, toGranularity: .weekOfYear) } ?? false }
        case .month:
            filtered = allStats.filter { date(from: $0.dateKey).map { calendar.isDate($0, equalTo: referenceDate, toGranularity: .month) } ?? false }
        case .year:
            filtered = allStats.filter { date(from: $0.dateKey).map { calendar.isDate($0, equalTo: referenceDate, toGranularity: .year) } ?? false }
        }

        return makeSnapshot(from: filtered, streakSource: allStats, referenceDate: referenceDate)
    }

    func todayReadingSeconds(referenceDate: Date = Date()) -> Int {
        Self.ioQueue.sync { loadStatsByDate()[dateKey(for: referenceDate)]?.seconds ?? 0 }
    }

    private func makeSnapshot(from stats: [DailyReadingStat], streakSource: [DailyReadingStat], referenceDate: Date) -> ReadingStatsSnapshot {
        let totalSeconds = stats.reduce(0) { $0 + $1.seconds }
        let activeDays = stats.filter { $0.seconds > 0 }.count
        let sessions = stats.reduce(0) { $0 + $1.sessions }
        let distinctBooks = Set(stats.flatMap(\.bookIds)).count
        let bestDaySeconds = stats.map(\.seconds).max() ?? 0
        let currentStreak = currentStreakDays(from: streakSource, referenceDate: referenceDate)
        let badges = calculateBadges(from: streakSource, currentStreak: currentStreak)

        return ReadingStatsSnapshot(
            totalSeconds: totalSeconds,
            activeDays: activeDays,
            sessions: sessions,
            distinctBooks: distinctBooks,
            averageSecondsPerActiveDay: activeDays == 0 ? 0 : totalSeconds / activeDays,
            currentStreakDays: currentStreak,
            bestDaySeconds: bestDaySeconds,
            dailyStats: stats.sorted { $0.dateKey > $1.dateKey },
            badges: badges
        )
    }

    private func calculateBadges(from allStats: [DailyReadingStat], currentStreak: Int) -> [ReadingBadge] {
        // 1. Early Bird (5 mornings)
        var morningDays = 0
        for stat in allStats {
            if let hourly = stat.hourlySeconds {
                let morningSec = hourly.filter { (5...8).contains($0.key) }.values.reduce(0, +)
                if morningSec >= 60 { // at least 1 minute in the morning
                    morningDays += 1
                }
            }
        }
        let earlyBirdProgress = min(Double(morningDays) / 5.0, 1.0)
        let earlyBird = ReadingBadge(
            id: "early_bird",
            titleKey: "badge_early_bird_title",
            descKey: "badge_early_bird_desc",
            iconName: "sun.and.horizon.fill",
            isUnlocked: earlyBirdProgress >= 1.0,
            progress: earlyBirdProgress,
            currentValue: morningDays,
            targetValue: 5
        )

        // 2. Night Owl (5 nights)
        var nightDays = 0
        let nightHours = Set([22, 23, 0, 1, 2, 3, 4])
        for stat in allStats {
            if let hourly = stat.hourlySeconds {
                let nightSec = hourly.filter { nightHours.contains($0.key) }.values.reduce(0, +)
                if nightSec >= 60 { // at least 1 minute at night
                    nightDays += 1
                }
            }
        }
        let nightOwlProgress = min(Double(nightDays) / 5.0, 1.0)
        let nightOwl = ReadingBadge(
            id: "night_owl",
            titleKey: "badge_night_owl_title",
            descKey: "badge_night_owl_desc",
            iconName: "moon.stars.fill",
            isUnlocked: nightOwlProgress >= 1.0,
            progress: nightOwlProgress,
            currentValue: nightDays,
            targetValue: 5
        )

        // 3. Deep Reader (1 day with >= 45 mins)
        let maxDailySeconds = allStats.map(\.seconds).max() ?? 0
        let targetSeconds = 2700 // 45 minutes
        let deepReaderProgress = min(Double(maxDailySeconds) / Double(targetSeconds), 1.0)
        let deepReader = ReadingBadge(
            id: "deep_reader",
            titleKey: "badge_deep_reader_title",
            descKey: "badge_deep_reader_desc",
            iconName: "brain.head.profile",
            isUnlocked: deepReaderProgress >= 1.0,
            progress: deepReaderProgress,
            currentValue: maxDailySeconds / 60,
            targetValue: 45
        )

        // 4. Super Streak (7 days streak)
        let superStreakProgress = min(Double(currentStreak) / 7.0, 1.0)
        let superStreak = ReadingBadge(
            id: "super_streak",
            titleKey: "badge_super_streak_title",
            descKey: "badge_super_streak_desc",
            iconName: "flame.fill",
            isUnlocked: superStreakProgress >= 1.0,
            progress: superStreakProgress,
            currentValue: currentStreak,
            targetValue: 7
        )

        // 5. Book Collector (3 books)
        let distinctBooks = Set(allStats.flatMap(\.bookIds)).count
        let collectorProgress = min(Double(distinctBooks) / 3.0, 1.0)
        let bookCollector = ReadingBadge(
            id: "book_collector",
            titleKey: "badge_book_collector_title",
            descKey: "badge_book_collector_desc",
            iconName: "books.vertical.fill",
            isUnlocked: collectorProgress >= 1.0,
            progress: collectorProgress,
            currentValue: distinctBooks,
            targetValue: 3
        )

        // 6. Watch Pilot (10 watch turns)
        let watchTurns = UserDefaults.standard.integer(forKey: "review_watchPageTurnCount")
        let watchProgress = min(Double(watchTurns) / 10.0, 1.0)
        let watchPilot = ReadingBadge(
            id: "watch_pilot",
            titleKey: "badge_watch_pilot_title",
            descKey: "badge_watch_pilot_desc",
            iconName: "applewatch.watchface",
            isUnlocked: watchProgress >= 1.0,
            progress: watchProgress,
            currentValue: watchTurns,
            targetValue: 10
        )

        return [earlyBird, nightOwl, deepReader, superStreak, bookCollector, watchPilot]
    }

    private func currentStreakDays(from stats: [DailyReadingStat], referenceDate: Date) -> Int {
        let activeDates = Set(stats.filter { $0.seconds > 0 }.map(\.dateKey))
        var date = calendar.startOfDay(for: referenceDate)
        
        let todayKey = dateKey(for: date)
        if !activeDates.contains(todayKey) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: date) else { return 0 }
            let yesterdayKey = dateKey(for: yesterday)
            if activeDates.contains(yesterdayKey) {
                date = yesterday
            } else {
                return 0
            }
        }
        
        var streak = 0
        while activeDates.contains(dateKey(for: date)) {
            streak += 1
            guard let previousDate = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previousDate
        }

        return streak
    }

    private func loadStatsByDate() -> [String: DailyReadingStat] {
        if let cached = Self.committedCache[storageURL] { return cached }
        migrateUserDefaultsStatsIfNeeded()

        guard let data = try? Data(contentsOf: storageURL),
              let stats = try? decoder.decode([String: DailyReadingStat].self, from: data)
        else {
            return [:]
        }
        Self.committedCache[storageURL] = stats
        return stats
    }

    @discardableResult
    private func save(_ stats: [String: DailyReadingStat]) -> Bool {
        do {
            let data = try encodeStats(stats)
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: [.atomic])
            Self.committedCache[storageURL] = stats
            return true
        } catch {
            print("ReadingStatsStore: failed to save stats: \(error)")
            return false
        }
    }

    private func migrateUserDefaultsStatsIfNeeded() {
        guard !defaults.bool(forKey: Keys.didMigrateDailyStats) else {
            return
        }

        guard let data = defaults.data(forKey: Keys.dailyStats) else {
            defaults.set(true, forKey: Keys.didMigrateDailyStats)
            return
        }

        do {
            _ = try decoder.decode([String: DailyReadingStat].self, from: data)
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: [.atomic])
            defaults.set(true, forKey: Keys.didMigrateDailyStats)
        } catch {
            print("ReadingStatsStore: failed to migrate stats: \(error)")
        }
    }

    private func dateKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func date(from key: String) -> Date? {
        dateFormatter().date(from: key)
    }

    private func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func defaultStorageURL() -> URL {
        Paths.library.url
            .appendingPathComponent("ReadingStats", isDirectory: true)
            .appendingPathComponent("daily-stats-v1.json", isDirectory: false)
    }
}

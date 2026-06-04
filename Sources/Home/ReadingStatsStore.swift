//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

extension Notification.Name {
    static let readingStatsDidChange = Notification.Name("readingStatsDidChange")
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

    var id: String { dateKey }
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

    static let empty = ReadingStatsSnapshot()
}

final class ReadingStatsAccess {
    static let shared = ReadingStatsAccess()

    private let defaults: UserDefaults

    private enum Keys {
        static let isPro = "entitlements_isPro"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasProAccess: Bool {
        ProPurchaseManager.shared.hasProAccess
    }
}

final class ReadingStatsStore {
    static let shared = ReadingStatsStore()

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let storageURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private enum Keys {
        static let dailyStats = "readingStats_dailyStats"
        static let didMigrateDailyStats = "readingStats_didMigrateDailyStatsToFile"
    }

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = Calendar(identifier: .gregorian),
        storageURL: URL? = nil
    ) {
        self.defaults = defaults
        var cal = calendar
        if cal.identifier != .gregorian {
            cal = Calendar(identifier: .gregorian)
        }
        cal.timeZone = .current
        self.calendar = cal
        self.storageURL = storageURL ?? Self.defaultStorageURL()
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

    func recordReadingSession(seconds: Int, bookId: Book.Id, date: Date = Date()) {
        guard seconds > 0 else { return }

        var statsByDate = loadStatsByDate()
        let key = dateKey(for: date)
        var stat = statsByDate[key] ?? DailyReadingStat(dateKey: key, seconds: 0, sessions: 0, bookIds: [], bookSeconds: [:])

        stat.seconds += seconds
        stat.sessions += 1

        let bookIdString = bookId.string
        if !stat.bookIds.contains(bookIdString) {
            stat.bookIds.append(bookIdString)
        }

        var bSeconds = stat.bookSeconds ?? [:]
        bSeconds[bookIdString] = (bSeconds[bookIdString] ?? 0) + seconds
        stat.bookSeconds = bSeconds

        statsByDate[key] = stat
        save(statsByDate)

        NotificationCenter.default.post(name: .readingStatsDidChange, object: self)
    }

    func snapshot(for scope: ReadingStatsScope, referenceDate: Date = Date()) -> ReadingStatsSnapshot {
        let allStats = loadStatsByDate().values.sorted { $0.dateKey < $1.dateKey }
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
        loadStatsByDate()[dateKey(for: referenceDate)]?.seconds ?? 0
    }

    private func makeSnapshot(from stats: [DailyReadingStat], streakSource: [DailyReadingStat], referenceDate: Date) -> ReadingStatsSnapshot {
        let totalSeconds = stats.reduce(0) { $0 + $1.seconds }
        let activeDays = stats.filter { $0.seconds > 0 }.count
        let sessions = stats.reduce(0) { $0 + $1.sessions }
        let distinctBooks = Set(stats.flatMap(\.bookIds)).count
        let bestDaySeconds = stats.map(\.seconds).max() ?? 0

        return ReadingStatsSnapshot(
            totalSeconds: totalSeconds,
            activeDays: activeDays,
            sessions: sessions,
            distinctBooks: distinctBooks,
            averageSecondsPerActiveDay: activeDays == 0 ? 0 : totalSeconds / activeDays,
            currentStreakDays: currentStreakDays(from: streakSource, referenceDate: referenceDate),
            bestDaySeconds: bestDaySeconds,
            dailyStats: stats.sorted { $0.dateKey > $1.dateKey }
        )
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
        migrateUserDefaultsStatsIfNeeded()

        guard let data = try? Data(contentsOf: storageURL),
              let stats = try? decoder.decode([String: DailyReadingStat].self, from: data)
        else {
            return [:]
        }

        return stats
    }

    private func save(_ stats: [String: DailyReadingStat]) {
        guard let data = try? encoder.encode(stats) else { return }
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storageURL, options: [.atomic])
        } catch {
            print("ReadingStatsStore: failed to save stats: \(error)")
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
        Self.dateFormatter.string(from: calendar.startOfDay(for: date))
    }

    private func date(from key: String) -> Date? {
        Self.dateFormatter.date(from: key)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func defaultStorageURL() -> URL {
        Paths.library.url
            .appendingPathComponent("ReadingStats", isDirectory: true)
            .appendingPathComponent("daily-stats-v1.json", isDirectory: false)
    }
}

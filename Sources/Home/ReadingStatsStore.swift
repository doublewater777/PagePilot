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
    var hourlySeconds: [Int: Int]? // Key: hour (0-23), Value: seconds read in that hour

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

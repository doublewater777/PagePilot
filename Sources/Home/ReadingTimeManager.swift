//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Manages reading time tracking via UserDefaults
final class ReadingTimeManager {
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let todayReadingTime = "home_todayReadingTime"
        static let lastReadingDate = "home_lastReadingDate"
        static let totalReadingTimeSeconds = "home_totalReadingTimeSeconds"
    }

    private(set) var todayReadingTimeSeconds: Int = 0

    init() {
        resetTodayIfNeeded()
        todayReadingTimeSeconds = defaults.integer(forKey: Keys.todayReadingTime)
    }

    /// Add reading time in seconds
    func addReadingTime(seconds: Int) {
        resetTodayIfNeeded()
        todayReadingTimeSeconds += seconds
        defaults.set(todayReadingTimeSeconds, forKey: Keys.todayReadingTime)
    }

    /// Returns formatted reading time string (e.g., "1h 23m")
    var formattedTodayReadingTime: String {
        let hours = todayReadingTimeSeconds / 3600
        let minutes = (todayReadingTimeSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "0m"
        }
    }

    private func resetTodayIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        if let lastDate = defaults.object(forKey: Keys.lastReadingDate) as? Date {
            if !calendar.isDate(lastDate, inSameDayAs: today) {
                defaults.set(0, forKey: Keys.todayReadingTime)
            }
        }
        defaults.set(today, forKey: Keys.lastReadingDate)
    }
}

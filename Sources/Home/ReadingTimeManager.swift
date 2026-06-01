//
//  Copyright 2026 Readium Foundation. All rights reserved.
//  Use of this source code is governed by the BSD-style license
//  available in the top-level LICENSE file of the project.
//

import Foundation

/// Manages reading time tracking via UserDefaults
final class ReadingTimeManager {
    private let statsStore: ReadingStatsStore

    var todayReadingTimeSeconds: Int {
        statsStore.todayReadingSeconds()
    }

    init(statsStore: ReadingStatsStore = .shared) {
        self.statsStore = statsStore
    }

    /// Add reading time in seconds.
    func addReadingTime(seconds: Int, bookId: Book.Id) {
        statsStore.recordReadingSession(seconds: seconds, bookId: bookId)
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
}

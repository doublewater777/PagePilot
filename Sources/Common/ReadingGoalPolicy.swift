import Foundation

/// Pure logic for the daily reading-goal payoff, testable without UIKit or stats I/O.
enum ReadingGoalPolicy {
    /// True when today's reading has met or crossed the daily goal.
    static func goalReached(todaySeconds: Int, goalMinutes: Int) -> Bool {
        guard goalMinutes > 0 else { return false }
        return todaySeconds >= goalMinutes * 60
    }
}

/// Tracks whether the goal-reached toast has already been shown today, so it fires at
/// most once per day. Thin UserDefaults wrapper.
enum ReadingGoalCelebration {
    private static let dateKey = "reading_goal_celebrated_date"

    static func alreadyCelebratedToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        UserDefaults.standard.string(forKey: dateKey) == dayKey(now, calendar: calendar)
    }

    static func markCelebratedToday(now: Date = Date(), calendar: Calendar = .current) {
        UserDefaults.standard.set(dayKey(now, calendar: calendar), forKey: dateKey)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

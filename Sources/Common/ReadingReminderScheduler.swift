import Foundation
import UserNotifications

/// Pure decision logic for the reading reminder, testable without
/// `UNUserNotificationCenter`.
enum ReadingReminderPolicy {
    /// Stable identifier for the scheduled reminder request.
    static let identifier = "pagepilot.reading.reminder"

    /// The daily repeating trigger components for the given time.
    static func triggerComponents(hour: Int, minute: Int) -> DateComponents {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return components
    }
}

/// Schedules and cancels the daily reading-reminder local notification.
///
/// The testable logic lives in `ReadingReminderPolicy`; this type only owns the
/// `UNUserNotificationCenter` I/O.
final class ReadingReminderScheduler {
    static let shared = ReadingReminderScheduler()

    private init() {}

    private var center: UNUserNotificationCenter { UNUserNotificationCenter.current() }

    /// Requests notification authorization. Returns whether the user granted it.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Reschedules the daily reminder from `ReadingPreferences`, or cancels it when
    /// disabled. Safe to call on every launch and on every setting change.
    func reschedule() async {
        guard ReadingPreferences.reminderEnabled else {
            cancelAll()
            return
        }

        cancelAll()

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("reminder_title", comment: "")
        content.body = NSLocalizedString("reminder_body", comment: "")
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: ReadingReminderPolicy.triggerComponents(
                hour: ReadingPreferences.reminderHour,
                minute: ReadingPreferences.reminderMinute
            ),
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: ReadingReminderPolicy.identifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }

    func cancelAll() {
        center.removePendingNotificationRequests(withIdentifiers: [ReadingReminderPolicy.identifier])
    }
}

import Foundation
import UserNotifications

/// Opt-in local session reminders — no streak shame, no tracking, on-device only.
enum SessionReminderScheduler {
    static let morningID = "openpulse.reminder.morning"
    static let eveningID = "openpulse.reminder.evening"

    /// Quiet wellness body (unit-tested). Never “you missed a day”.
    static func body() -> String {
        "When you’re ready, a short session is here."
    }

    static func title() -> String {
        "Open Pulse"
    }

    /// Pure: identifiers to cancel/schedule for the opt-in times.
    static func identifiers(morning: Bool, evening: Bool) -> [String] {
        var ids: [String] = []
        if morning { ids.append(morningID) }
        if evening { ids.append(eveningID) }
        return ids
    }

    /// Rebuild pending local notifications from preferences.
    static func reschedule(
        enabled: Bool,
        morningHour: Int,
        eveningHour: Int,
        center: UNUserNotificationCenter = .current()
    ) {
        center.removePendingNotificationRequests(
            withIdentifiers: identifiers(morning: true, evening: true)
        )
        guard enabled else { return }

        let morning = (0...23).contains(morningHour)
        let evening = (0...23).contains(eveningHour) && eveningHour != morningHour
        for id in identifiers(morning: morning, evening: evening) {
            let hour = id == morningID ? morningHour : eveningHour
            scheduleDaily(id: id, hour: hour, center: center)
        }
    }

    private static func scheduleDaily(
        id: String,
        hour: Int,
        center: UNUserNotificationCenter
    ) {
        let content = UNMutableNotificationContent()
        content.title = title()
        content.body = body()
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }
}

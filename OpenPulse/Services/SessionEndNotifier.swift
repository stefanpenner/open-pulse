import Foundation
import UserNotifications

// MARK: - Testable seam (VM lifecycle unit tests)

/// Local session-end alert surface. Production uses system notifications;
/// tests inject a recording double (no UNUserNotificationCenter).
@MainActor
protocol SessionEndNotifying: AnyObject {
    func cancel()
    func schedule(endsAt: Date, modeName: String, enabled: Bool, now: Date)
    /// Completion always delivered on the main actor.
    func requestAuthorizationIfNeeded(completion: (@MainActor @Sendable (Bool) -> Void)?)
    func fetchCanDeliver(completion: @escaping @MainActor @Sendable (Bool) -> Void)
}

/// Default production notifier (static helpers + system center).
@MainActor
final class SystemSessionEndNotifier: SessionEndNotifying {
    func cancel() {
        SessionEndNotifier.cancel()
    }

    func schedule(endsAt: Date, modeName: String, enabled: Bool, now: Date) {
        SessionEndNotifier.schedule(endsAt: endsAt, modeName: modeName, enabled: enabled, now: now)
    }

    func requestAuthorizationIfNeeded(completion: (@MainActor @Sendable (Bool) -> Void)?) {
        SessionEndNotifier.requestAuthorizationIfNeeded { granted in
            Task { @MainActor in
                completion?(granted)
            }
        }
    }

    func fetchCanDeliver(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        SessionEndNotifier.fetchCanDeliver { canDeliver in
            Task { @MainActor in
                completion(canDeliver)
            }
        }
    }
}

/// Opt-in local notification when a session ends while the phone is locked / app backgrounded.
/// Privacy-first: no network, no tracking, on-device only. Wellness framing only.
enum SessionEndNotifier {
    static let requestIdentifier = "openpulse.session.end"

    /// Cancel any pending end-of-session alert.
    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
    }

    /// Notification body copy (unit-tested, wellness-safe).
    static func body(modeName: String) -> String {
        let name = modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Your session has finished. Device will stop when Open Pulse can connect."
        }
        return "\(name) session finished. Device will stop when Open Pulse can connect."
    }

    /// Title copy (unit-tested).
    static func title() -> String {
        "Session complete"
    }

    /// User-facing status when alerts are enabled but system denied permission.
    static func deniedHelpText() -> String {
        "Notifications are off for Open Pulse. Enable them in Settings → Notifications to get session end alerts."
    }

    /// Whether the system currently allows alert delivery (pure helper for tests).
    static func canDeliverAlerts(authorizationStatus: UNAuthorizationStatus) -> Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    /// Schedule a one-shot local alert at `endsAt` if enabled and still in the future.
    static func schedule(endsAt: Date, modeName: String, enabled: Bool, now: Date = Date()) {
        cancel()
        guard enabled, endsAt > now else { return }

        let content = UNMutableNotificationContent()
        content.title = title()
        content.body = body(modeName: modeName)
        content.sound = .default

        let interval = max(1, endsAt.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Request alert permission (call when user opts in).
    static func requestAuthorizationIfNeeded(completion: (@Sendable (Bool) -> Void)? = nil) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        completion?(granted)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    completion?(true)
                }
            case .denied:
                DispatchQueue.main.async {
                    completion?(false)
                }
            @unknown default:
                DispatchQueue.main.async {
                    completion?(false)
                }
            }
        }
    }

    /// Fetch whether alerts can currently be delivered (async).
    static func fetchCanDeliver(completion: @escaping @Sendable (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let ok = canDeliverAlerts(authorizationStatus: settings.authorizationStatus)
            DispatchQueue.main.async {
                completion(ok)
            }
        }
    }
}

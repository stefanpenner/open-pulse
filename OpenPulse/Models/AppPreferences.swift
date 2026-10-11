import Foundation

/// Local-only preferences (no accounts, no cloud).
enum AppPreferences {
    static let onboardingCompletedKey = "prefs.onboardingCompleted"
    static let lastStrengthKey = "prefs.lastStrength"
    static let pendingDeactivateKey = "prefs.pendingDeactivate"
    static let customChannelKey = "prefs.customChannel"
    static let mindfulMinutesEnabledKey = "prefs.mindfulMinutesEnabled"
    static let sessionEndAlertsEnabledKey = "prefs.sessionEndAlertsEnabled"
    static let sessionRemindersEnabledKey = "prefs.sessionRemindersEnabled"
    static let sessionReminderMorningHourKey = "prefs.sessionReminderMorningHour"
    static let sessionReminderEveningHourKey = "prefs.sessionReminderEveningHour"
    static let ambientMusicEnabledKey = "prefs.ambientMusicEnabled"

    static func hasCompletedOnboarding(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: onboardingCompletedKey)
    }

    static func markOnboardingCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: onboardingCompletedKey)
    }

    static func resetOnboarding(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: onboardingCompletedKey)
    }

    /// Last intensity the user settled on (1…9). Official apps auto-save this for comfort.
    static func lastStrength(defaults: UserDefaults = .standard) -> Int? {
        let v = defaults.integer(forKey: lastStrengthKey)
        guard (1...9).contains(v) else { return nil }
        return v
    }

    static func saveLastStrength(_ strength: Int, defaults: UserDefaults = .standard) {
        let clamped = max(1, min(9, strength))
        defaults.set(clamped, forKey: lastStrengthKey)
    }

    /// Durable "device must be off" flag across process death (SessionBLE idle off).
    static func pendingDeactivate(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: pendingDeactivateKey)
    }

    static func setPendingDeactivate(_ value: Bool, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: pendingDeactivateKey)
    }

    /// Last custom channel: "A" | "B" | "C" | "D" | "0"
    static func customChannel(defaults: UserDefaults = .standard) -> String {
        let v = defaults.string(forKey: customChannelKey) ?? "D"
        switch v {
        case "A", "B", "C", "D", "0": return v
        default: return "D"
        }
    }

    static func saveCustomChannel(_ cmd: String, defaults: UserDefaults = .standard) {
        let v: String
        switch cmd {
        case "A", "B", "C", "D", "0": v = cmd
        default: v = "D"
        }
        defaults.set(v, forKey: customChannelKey)
    }

    /// Opt-in: write completed breathing sessions to Apple Health as Mindful Minutes.
    static func mindfulMinutesEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: mindfulMinutesEnabledKey)
    }

    static func setMindfulMinutesEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: mindfulMinutesEnabledKey)
    }

    /// Opt-in: local notification when a session ends in the background (no network).
    static func sessionEndAlertsEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: sessionEndAlertsEnabledKey)
    }

    static func setSessionEndAlertsEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: sessionEndAlertsEnabledKey)
    }

    /// Opt-in local “when you’re ready” reminders (morning/evening). Off by default. No guilt nags.
    static func sessionRemindersEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: sessionRemindersEnabledKey)
    }

    static func setSessionRemindersEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: sessionRemindersEnabledKey)
    }

    /// Hour 0…23 for morning reminder (default 9).
    static func sessionReminderMorningHour(defaults: UserDefaults = .standard) -> Int {
        if defaults.object(forKey: sessionReminderMorningHourKey) == nil { return 9 }
        return clampHour(defaults.integer(forKey: sessionReminderMorningHourKey))
    }

    static func setSessionReminderMorningHour(_ hour: Int, defaults: UserDefaults = .standard) {
        defaults.set(clampHour(hour), forKey: sessionReminderMorningHourKey)
    }

    /// Hour 0…23 for evening reminder (default 20).
    static func sessionReminderEveningHour(defaults: UserDefaults = .standard) -> Int {
        if defaults.object(forKey: sessionReminderEveningHourKey) == nil { return 20 }
        return clampHour(defaults.integer(forKey: sessionReminderEveningHourKey))
    }

    static func setSessionReminderEveningHour(_ hour: Int, defaults: UserDefaults = .standard) {
        defaults.set(clampHour(hour), forKey: sessionReminderEveningHourKey)
    }

    static func clampHour(_ hour: Int) -> Int {
        max(0, min(23, hour))
    }

    /// Opt-in local ambient pad during sessions. Off by default. Bundled audio only — no streaming.
    static func ambientMusicEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: ambientMusicEnabledKey)
    }

    static func setAmbientMusicEnabled(_ enabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: ambientMusicEnabledKey)
    }
}

/// Expand the idle intensity control until a level is stored.
enum IntensityIdlePolicy {
    /// True when Still should open the intensity control by default.
    static func expandByDefault(hasStoredStrength: Bool) -> Bool {
        !hasStoredStrength
    }
}

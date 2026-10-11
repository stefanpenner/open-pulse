import Foundation

/// Cross-target intent signals (app ↔ Live Activity widget extension).
/// Live Activity control buttons compile in the widget module; `LiveActivityIntent`
/// may execute without a bound `SessionActionBridge` in that module. Darwin notify
/// reaches the app process where the VM is bound (privacy-first, on-device only).
enum OpenPulseIntentRelay {
    static let pause = "io.github.stefanpenner.OpenPulse.intent.pause"
    static let resume = "io.github.stefanpenner.OpenPulse.intent.resume"
    static let start = "io.github.stefanpenner.OpenPulse.intent.start"
    static let stop = "io.github.stefanpenner.OpenPulse.intent.stop"
    static let intensityUp = "io.github.stefanpenner.OpenPulse.intent.intensityUp"
    static let intensityDown = "io.github.stefanpenner.OpenPulse.intent.intensityDown"

    static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    static func postPause() { post(pause) }
    static func postResume() { post(resume) }
    static func postStart() { post(start) }
    static func postStop() { post(stop) }
    static func postIntensityUp() { post(intensityUp) }
    static func postIntensityDown() { post(intensityDown) }
}

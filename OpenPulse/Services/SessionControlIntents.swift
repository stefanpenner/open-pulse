import AppIntents
import Foundation

/// Routes Island / Shortcuts actions to the app session bridge.
/// - App target: call `SessionActionBridge` directly (bound VM).
/// - Widget extension: Darwin notify so the app process can handle.
@MainActor
private enum OpenPulseIntentDispatch {
    static func pause() {
        #if OPENPULSE_APP_EXTENSION
        OpenPulseIntentRelay.postPause()
        #else
        SessionActionBridge.shared.requestPause()
        #endif
    }

    static func resume() {
        #if OPENPULSE_APP_EXTENSION
        OpenPulseIntentRelay.postResume()
        #else
        SessionActionBridge.shared.requestResume()
        #endif
    }

    static func start() {
        #if OPENPULSE_APP_EXTENSION
        OpenPulseIntentRelay.postStart()
        #else
        SessionActionBridge.shared.requestStart()
        #endif
    }

    static func stop() {
        #if OPENPULSE_APP_EXTENSION
        OpenPulseIntentRelay.postStop()
        #else
        SessionActionBridge.shared.requestStop()
        #endif
    }

    static func intensityUp() {
        #if OPENPULSE_APP_EXTENSION
        OpenPulseIntentRelay.postIntensityUp()
        #else
        SessionActionBridge.shared.requestNudgeStrength(by: 1)
        #endif
    }

    static func intensityDown() {
        #if OPENPULSE_APP_EXTENSION
        OpenPulseIntentRelay.postIntensityDown()
        #else
        SessionActionBridge.shared.requestNudgeStrength(by: -1)
        #endif
    }
}

/// Lock Screen / Island pause — runs in app process (LiveActivityIntent).
struct PauseOpenPulseSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause session"
    static let description = IntentDescription("Pauses the Open Pulse session and turns the device off.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            OpenPulseIntentDispatch.pause()
        }
        return .result()
    }
}

/// Lock Screen / Island resume — only effective when BLE is ready (VM enforces).
struct ResumeOpenPulseSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume session"
    static let description = IntentDescription("Resumes the Open Pulse session when the device is connected.")

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            OpenPulseIntentDispatch.resume()
        }
        return .result()
    }
}

/// Siri / Shortcuts start — opens app when needed; starts only if link ready.
struct StartOpenPulseSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start session"
    static let description = IntentDescription(
        "Starts an Open Pulse session when your Pulsetto is connected. Privacy-first — no accounts."
    )
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            OpenPulseIntentDispatch.start()
        }
        return .result()
    }
}

/// Lock Screen / Island / Siri stop — ends session and requests hardware off.
/// LiveActivityIntent so Island can offer Stop when Resume is unavailable (offline pause).
struct StopOpenPulseSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop session"
    static let description = IntentDescription(
        "Stops the Open Pulse session and turns the device off. On-device only."
    )
    /// Siri / Shortcuts may open app; Island uses same intent in-process via bridge.
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            OpenPulseIntentDispatch.stop()
        }
        return .result()
    }
}

/// Island / Shortcuts — raise intensity one step (1…9). On-device only.
struct IncreaseOpenPulseIntensityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Increase intensity"
    static let description = IntentDescription(
        "Raises Open Pulse intensity by one level during a session. Privacy-first — no accounts."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            OpenPulseIntentDispatch.intensityUp()
        }
        return .result()
    }
}

/// Island / Shortcuts — lower intensity one step (1…9). On-device only.
struct DecreaseOpenPulseIntensityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Decrease intensity"
    static let description = IntentDescription(
        "Lowers Open Pulse intensity by one level during a session. Privacy-first — no accounts."
    )

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            OpenPulseIntentDispatch.intensityDown()
        }
        return .result()
    }
}

#if !OPENPULSE_APP_EXTENSION
/// Siri / Shortcuts discovery (app target only — bridge-only, privacy-first).
struct OpenPulseShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartOpenPulseSessionIntent(),
            phrases: [
                "Start \(.applicationName) session",
                "Start my \(.applicationName) session",
            ],
            shortTitle: "Start session",
            systemImageName: "play.circle.fill"
        )
        AppShortcut(
            intent: PauseOpenPulseSessionIntent(),
            phrases: [
                "Pause \(.applicationName) session",
                "Pause my \(.applicationName) session",
            ],
            shortTitle: "Pause session",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: ResumeOpenPulseSessionIntent(),
            phrases: [
                "Resume \(.applicationName) session",
                "Resume my \(.applicationName) session",
            ],
            shortTitle: "Resume session",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: StopOpenPulseSessionIntent(),
            phrases: [
                "Stop \(.applicationName) session",
                "End my \(.applicationName) session",
            ],
            shortTitle: "Stop session",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: IncreaseOpenPulseIntensityIntent(),
            phrases: [
                "Increase \(.applicationName) intensity",
                "Raise \(.applicationName) intensity",
            ],
            shortTitle: "Increase intensity",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: DecreaseOpenPulseIntensityIntent(),
            phrases: [
                "Decrease \(.applicationName) intensity",
                "Lower \(.applicationName) intensity",
            ],
            shortTitle: "Decrease intensity",
            systemImageName: "minus.circle.fill"
        )
    }
}
#endif

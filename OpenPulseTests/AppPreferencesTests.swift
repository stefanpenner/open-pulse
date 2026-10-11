import Foundation
import Testing
@testable import OpenPulse

@Suite("AppPreferences")
struct AppPreferencesTests {
    @Test("Onboarding defaults to incomplete")
    func onboardingDefaultIncomplete() {
        let suite = "test.prefs.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        #expect(!AppPreferences.hasCompletedOnboarding(defaults: d))
    }

    @Test("Marking onboarding completed is sticky")
    func markOnboardingCompleted() {
        let suite = "test.prefs.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        AppPreferences.markOnboardingCompleted(defaults: d)
        #expect(AppPreferences.hasCompletedOnboarding(defaults: d))
    }

    @Test("Reset clears onboarding flag")
    func resetOnboarding() {
        let suite = "test.prefs.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        AppPreferences.markOnboardingCompleted(defaults: d)
        AppPreferences.resetOnboarding(defaults: d)
        #expect(!AppPreferences.hasCompletedOnboarding(defaults: d))
    }

    @Test("Session end alerts default off and stick when enabled")
    func sessionEndAlertsToggle() {
        let suite = "test.prefs.alerts.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        #expect(!AppPreferences.sessionEndAlertsEnabled(defaults: d))
        AppPreferences.setSessionEndAlertsEnabled(true, defaults: d)
        #expect(AppPreferences.sessionEndAlertsEnabled(defaults: d))
        AppPreferences.setSessionEndAlertsEnabled(false, defaults: d)
        #expect(!AppPreferences.sessionEndAlertsEnabled(defaults: d))
    }

    @Test("Intensity expands on idle until a last strength is stored")
    func intensityIdleExpandPolicy() {
        #expect(IntensityIdlePolicy.expandByDefault(hasStoredStrength: false))
        #expect(!IntensityIdlePolicy.expandByDefault(hasStoredStrength: true))
    }

    @Test("Ambient music defaults off and sticks when enabled")
    func ambientMusicToggle() {
        let suite = "test.prefs.ambient.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        #expect(!AppPreferences.ambientMusicEnabled(defaults: d))
        AppPreferences.setAmbientMusicEnabled(true, defaults: d)
        #expect(AppPreferences.ambientMusicEnabled(defaults: d))
        AppPreferences.setAmbientMusicEnabled(false, defaults: d)
        #expect(!AppPreferences.ambientMusicEnabled(defaults: d))
    }
}

@Suite("AmbientAudioPolicy")
struct AmbientAudioPolicyTests {
    @Test("Plays only when enabled, running, foreground, not paused")
    func playConditions() {
        #expect(AmbientAudioPolicy.shouldPlay(
            enabled: true, isRunning: true, isPaused: false, isInBackground: false
        ))
        #expect(!AmbientAudioPolicy.shouldPlay(
            enabled: false, isRunning: true, isPaused: false, isInBackground: false
        ))
        #expect(!AmbientAudioPolicy.shouldPlay(
            enabled: true, isRunning: false, isPaused: false, isInBackground: false
        ))
        #expect(!AmbientAudioPolicy.shouldPlay(
            enabled: true, isRunning: true, isPaused: true, isInBackground: false
        ))
        #expect(!AmbientAudioPolicy.shouldPlay(
            enabled: true, isRunning: true, isPaused: false, isInBackground: true
        ))
    }
}

@Suite("SessionHistory")
struct SessionHistoryTests {
    @Test("Append stores newest first and caps size")
    func appendAndCap() {
        let suite = "test.history.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        for i in 0..<45 {
            SessionHistory.append(
                mode: .focus,
                durationSeconds: 60 + i,
                strength: 5,
                completed: i % 2 == 0,
                defaults: d,
                now: Date().addingTimeInterval(TimeInterval(i))
            )
        }
        let items = SessionHistory.load(defaults: d)
        #expect(items.count == SessionHistory.maxEntries)
        // Newest first: last appended has highest duration in this loop
        #expect(items.first?.durationSeconds == 60 + 44)
    }

    @Test("Clear empties history")
    func clear() {
        let suite = "test.history.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        SessionHistory.append(mode: .calm, durationSeconds: 120, strength: 4, completed: true, defaults: d)
        SessionHistory.clear(defaults: d)
        #expect(SessionHistory.load(defaults: d).isEmpty)
    }
}

@Suite("AppPreferences — custom channel")
struct CustomChannelPrefsTests {
    @Test("Persists and restores custom channel")
    func customChannelRoundTrip() {
        let suite = "test.channel.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        #expect(AppPreferences.customChannel(defaults: d) == "D")
        AppPreferences.saveCustomChannel("A", defaults: d)
        #expect(AppPreferences.customChannel(defaults: d) == "A")
        AppPreferences.saveCustomChannel("0", defaults: d)
        #expect(AppPreferences.customChannel(defaults: d) == "0")
        AppPreferences.saveCustomChannel("Z", defaults: d)
        #expect(AppPreferences.customChannel(defaults: d) == "D")
    }
}

@Suite("SessionHistory — week stats")
struct SessionHistoryWeekTests {
    @Test("Week helpers count only current week")
    func weekHelpers() {
        let suite = "test.week.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let cal = Calendar.current
        let now = Date()
        SessionHistory.append(mode: .calm, durationSeconds: 300, strength: 4, completed: true, defaults: d, now: now)
        SessionHistory.append(
            mode: .focus,
            durationSeconds: 600,
            strength: 5,
            completed: true,
            defaults: d,
            now: cal.date(byAdding: .day, value: -14, to: now)!
        )
        #expect(SessionHistory.completedThisWeek(defaults: d, now: now, calendar: cal) == 1)
        #expect(SessionHistory.minutesThisWeek(defaults: d, now: now, calendar: cal) == 5)
    }

    @Test("Streak counts consecutive completed days")
    func streak() {
        let suite = "test.streak.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        SessionHistory.append(mode: .calm, durationSeconds: 120, strength: 4, completed: true, defaults: d, now: today)
        SessionHistory.append(
            mode: .focus,
            durationSeconds: 120,
            strength: 5,
            completed: true,
            defaults: d,
            now: cal.date(byAdding: .day, value: -1, to: today)!
        )
        SessionHistory.append(
            mode: .sleep,
            durationSeconds: 120,
            strength: 5,
            completed: true,
            defaults: d,
            now: cal.date(byAdding: .day, value: -2, to: today)!
        )
        #expect(SessionHistory.currentStreak(defaults: d, now: now, calendar: cal) == 3)
    }
}

@Suite("MockDeviceTransport")
struct MockDeviceTransportTests {
    @Test("Records commands and cancelProgramWrites")
    @MainActor func mockTransportBasics() {
        let mock = MockDeviceTransport()
        mock.isReady = true
        mock.sendCommand("D\n")
        mock.sendCommand("5\n")
        mock.sendCommand(BLEConstants.deactivateCommand)
        #expect(mock.commands.count == 3)
        mock.cancelProgramWrites()
        #expect(mock.cancelProgramWritesCount == 1)
        #expect(mock.commands == [BLEConstants.deactivateCommand])
    }
}

@Suite("AppPreferences — mindful minutes")
struct MindfulPrefsTests {
    @Test("Mindful flag defaults off and toggles")
    func mindfulToggle() {
        let suite = "test.mindful.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        #expect(!AppPreferences.mindfulMinutesEnabled(defaults: d))
        AppPreferences.setMindfulMinutesEnabled(true, defaults: d)
        #expect(AppPreferences.mindfulMinutesEnabled(defaults: d))
    }
}

@Suite("AppPreferences — last strength")
struct LastStrengthTests {
    @Test("Saves and restores last strength")
    func saveRestore() {
        let suite = "test.laststr.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        #expect(AppPreferences.lastStrength(defaults: d) == nil)
        AppPreferences.saveLastStrength(7, defaults: d)
        #expect(AppPreferences.lastStrength(defaults: d) == 7)
        AppPreferences.saveLastStrength(99, defaults: d)
        #expect(AppPreferences.lastStrength(defaults: d) == 9)
    }
}

@Suite("SessionViewModel — Session duration")
struct SessionDurationTests {
    @Test("Idle duration follows timer minutes")
    @MainActor func idleDuration() {
        let suiteName = "test.duration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let vm = SessionViewModel(defaults: defaults, ble: MockDeviceTransport())
        vm.timerMinutes = 8
        #expect(vm.sessionDurationSeconds == 480)
    }

    @Test("Running duration uses wall-clock total")
    @MainActor func runningDuration() {
        let suiteName = "test.duration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let mock = MockDeviceTransport()
        let vm = SessionViewModel(defaults: defaults, ble: mock)
        mock.becomeReady()
        vm.selectMode(.sleep)
        vm.start()
        #expect(vm.sessionDurationSeconds == StimulationMode.sleep.defaultDurationMinutes * 60)
        vm.increaseTimer() // +60 while running
        #expect(vm.sessionDurationSeconds == StimulationMode.sleep.defaultDurationMinutes * 60 + 60)
    }
}

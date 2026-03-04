import Foundation
import Testing
@testable import OpenPulse

// MARK: - Helpers

/// Creates a VM with an isolated UserDefaults suite so tests don't interfere.
@MainActor
private func makeVM() -> (SessionViewModel, CommandSpy) {
    let suiteName = "test.session.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let vm = SessionViewModel(defaults: defaults)
    let spy = CommandSpy()
    vm.ble.onCommandSent = { spy.commands.append($0) }
    return (vm, spy)
}

/// Creates a VM that reads from the given UserDefaults (for restore tests).
@MainActor
private func makeVM(defaults: UserDefaults) -> (SessionViewModel, CommandSpy) {
    let vm = SessionViewModel(defaults: defaults)
    let spy = CommandSpy()
    vm.ble.onCommandSent = { spy.commands.append($0) }
    return (vm, spy)
}

private final class CommandSpy: @unchecked Sendable {
    var commands: [String] = []
    func reset() { commands = [] }
}

/// Puts the VM into a "running session" state by calling start() with a ready BLE.
@MainActor
private func simulateRunning(_ vm: SessionViewModel, mode: StimulationMode = .stressRelief, strength: Int = 5) {
    vm.selectMode(mode)
    vm.strength = strength

    // Make BLE appear ready so start() succeeds
    vm.ble.isConnected = true
    vm.ble.isReady = true
    vm.start()
}

// MARK: - Strength Tests

@Suite("SessionViewModel — setStrength")
struct SetStrengthTests {
    @Test("Clamps value to minimum 1")
    @MainActor func clampsMin() {
        let (vm, _) = makeVM()
        vm.setStrength(0)
        #expect(vm.strength == 1)
        vm.setStrength(-5)
        #expect(vm.strength == 1)
    }

    @Test("Clamps value to maximum 9")
    @MainActor func clampsMax() {
        let (vm, _) = makeVM()
        vm.setStrength(10)
        #expect(vm.strength == 9)
        vm.setStrength(99)
        #expect(vm.strength == 9)
    }

    @Test("Sets valid values directly")
    @MainActor func setsValidValues() {
        let (vm, _) = makeVM()
        for v in 1...9 {
            vm.setStrength(v)
            #expect(vm.strength == v)
        }
    }

    @Test("Does not send commands when not running")
    @MainActor func noCommandsWhenIdle() {
        let (vm, spy) = makeVM()
        vm.setStrength(7)
        #expect(spy.commands.isEmpty)
    }

    @Test("Does not send commands when not connected")
    @MainActor func noCommandsWhenDisconnected() {
        let (vm, spy) = makeVM()
        vm.isRunning = true
        vm.stimulationActive = true
        vm.ble.isConnected = false
        spy.reset()

        vm.setStrength(7)
        #expect(vm.strength == 7)
        #expect(spy.commands.isEmpty)
    }

    @Test("Does not send commands when stimulation inactive")
    @MainActor func noCommandsWhenStimOff() {
        let (vm, spy) = makeVM()
        vm.isRunning = true
        vm.stimulationActive = false
        vm.ble.isConnected = true
        spy.reset()

        vm.setStrength(7)
        #expect(vm.strength == 7)
        #expect(spy.commands.isEmpty)
    }

    @Test("Sends commands mid-session with engine mode")
    @MainActor func sendsCommandsMidSessionWithEngine() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        spy.reset()

        vm.setStrength(7)
        #expect(vm.strength == 7)
        // Just sends strength command — no channel reactivation
        #expect(spy.commands == ["7\n"])
    }

    @Test("Sends strength command mid-session in custom mode")
    @MainActor func sendsCommandsMidSessionCustom() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        spy.reset()

        vm.setStrength(3)
        #expect(vm.strength == 3)
        #expect(spy.commands == ["3\n"])
    }

    @Test("Sends clamped value, not raw input")
    @MainActor func sendsClampedValue() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        spy.reset()

        vm.setStrength(15)
        #expect(vm.strength == 9)
        #expect(spy.commands == ["9\n"])
    }
}

// MARK: - Mode Selection Tests

@Suite("SessionViewModel — Mode Selection")
struct ModeSelectionTests {
    @Test("selectMode sets mode, timer, and strength to defaults")
    @MainActor func selectModeSetsDefaults() {
        let (vm, _) = makeVM()
        vm.selectMode(.sleep)
        #expect(vm.selectedMode == .sleep)
        #expect(vm.timerMinutes == StimulationMode.sleep.defaultDurationMinutes)
        #expect(vm.strength == StimulationMode.sleep.defaultStrength)
    }

    @Test("selectMode clears selectedFeeling")
    @MainActor func selectModeClearsFeeling() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.stressed)
        #expect(vm.selectedFeeling == .stressed)

        vm.selectMode(.custom)
        #expect(vm.selectedFeeling == nil)
    }

    @Test("selectMode is ignored when running")
    @MainActor func selectModeIgnoredWhenRunning() {
        let (vm, _) = makeVM()
        vm.selectMode(.sleep)
        vm.isRunning = true

        vm.selectMode(.focus)
        #expect(vm.selectedMode == .sleep)
    }

    @Test("selectMode is ignored when paused")
    @MainActor func selectModeIgnoredWhenPaused() {
        let (vm, _) = makeVM()
        vm.selectMode(.sleep)
        vm.isPaused = true

        vm.selectMode(.focus)
        #expect(vm.selectedMode == .sleep)
    }
}

// MARK: - Feeling Selection Tests

@Suite("SessionViewModel — Feeling Selection")
struct FeelingSelectionTests {
    @Test("selectFeeling sets feeling and maps to correct mode")
    @MainActor func selectFeelingSetsMode() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.stressed)
        #expect(vm.selectedFeeling == .stressed)
        #expect(vm.selectedMode == .stressRelief)
    }

    @Test("selectFeeling maps all states to correct modes")
    @MainActor func allFeelingsMapCorrectly() {
        let expected: [(AutonomicState, StimulationMode)] = [
            (.stressed, .stressRelief),
            (.anxious, .calm),
            (.wired, .sleep),
            (.foggy, .focus),
            (.hurting, .painRelief),
        ]

        for (state, mode) in expected {
            let (vm, _) = makeVM()
            vm.selectFeeling(state)
            #expect(vm.selectedMode == mode, "Expected \(state) → \(mode)")
            #expect(vm.selectedFeeling == state)
        }
    }

    @Test("selectFeeling sets timer and strength from mapped mode")
    @MainActor func selectFeelingSetsDefaults() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.wired)
        #expect(vm.timerMinutes == StimulationMode.sleep.defaultDurationMinutes)
        #expect(vm.strength == StimulationMode.sleep.defaultStrength)
    }

    @Test("selectFeeling is ignored when running")
    @MainActor func ignoredWhenRunning() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.stressed)
        vm.isRunning = true

        vm.selectFeeling(.foggy)
        #expect(vm.selectedFeeling == .stressed)
        #expect(vm.selectedMode == .stressRelief)
    }

    @Test("Switching feelings updates everything")
    @MainActor func switchingFeelings() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.stressed)
        vm.selectFeeling(.hurting)
        #expect(vm.selectedFeeling == .hurting)
        #expect(vm.selectedMode == .painRelief)
        #expect(vm.strength == StimulationMode.painRelief.defaultStrength)
    }

    @Test("selectMode after selectFeeling clears feeling")
    @MainActor func modeAfterFeelingClearsFeeling() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.anxious)
        #expect(vm.selectedFeeling == .anxious)

        vm.selectMode(.custom)
        #expect(vm.selectedFeeling == nil)
        #expect(vm.selectedMode == .custom)
    }
}

// MARK: - Timer Tests

@Suite("SessionViewModel — Timer")
struct TimerTests {
    @Test("increaseTimer adds 1 minute")
    @MainActor func increase() {
        let (vm, _) = makeVM()
        let before = vm.timerMinutes
        vm.increaseTimer()
        #expect(vm.timerMinutes == before + 1)
    }

    @Test("decreaseTimer subtracts 1 minute")
    @MainActor func decrease() {
        let (vm, _) = makeVM()
        vm.timerMinutes = 5
        vm.decreaseTimer()
        #expect(vm.timerMinutes == 4)
    }

    @Test("decreaseTimer won't go below 1")
    @MainActor func decreaseFloor() {
        let (vm, _) = makeVM()
        vm.timerMinutes = 1
        vm.decreaseTimer()
        #expect(vm.timerMinutes == 1)
    }

    @Test("increaseTimer is ignored when running")
    @MainActor func increaseIgnoredWhenRunning() {
        let (vm, _) = makeVM()
        vm.timerMinutes = 5
        vm.isRunning = true
        vm.increaseTimer()
        #expect(vm.timerMinutes == 5)
    }

    @Test("decreaseTimer is ignored when paused")
    @MainActor func decreaseIgnoredWhenPaused() {
        let (vm, _) = makeVM()
        vm.timerMinutes = 5
        vm.isPaused = true
        vm.decreaseTimer()
        #expect(vm.timerMinutes == 5)
    }
}

// MARK: - Display Tests

@Suite("SessionViewModel — Display")
struct DisplayTests {
    @Test("displayTime formats minutes when idle")
    @MainActor func displayTimeIdle() {
        let (vm, _) = makeVM()
        vm.timerMinutes = 10
        #expect(vm.displayTime == "10:00")
    }

    @Test("displayTime shows remaining seconds when running")
    @MainActor func displayTimeRunning() {
        let (vm, _) = makeVM()
        vm.isRunning = true
        vm.remainingSeconds = 65
        #expect(vm.displayTime == "01:05")
    }

    @Test("progress is 0 when idle")
    @MainActor func progressIdle() {
        let (vm, _) = makeVM()
        #expect(vm.progress == 0)
    }
}

// MARK: - AutonomicState Tests

@Suite("AutonomicState")
struct AutonomicStateTests {
    @Test("All states have non-empty labels")
    func allLabels() {
        for state in AutonomicState.allCases {
            #expect(!state.label.isEmpty)
        }
    }

    @Test("All states have valid SF Symbol icons")
    func allIcons() {
        for state in AutonomicState.allCases {
            #expect(!state.icon.isEmpty)
        }
    }

    @Test("Case order matches grid layout")
    func caseOrder() {
        let cases = AutonomicState.allCases
        #expect(cases == [.stressed, .anxious, .wired, .foggy, .hurting])
    }

    @Test("Labels are user-facing feeling words")
    func feelingLabels() {
        #expect(AutonomicState.stressed.label == "Stressed")
        #expect(AutonomicState.anxious.label == "Anxious")
        #expect(AutonomicState.wired.label == "Can't Sleep")
        #expect(AutonomicState.foggy.label == "Foggy")
        #expect(AutonomicState.hurting.label == "In Pain")
    }
}

// MARK: - Wall-Clock Timer Tests

@Suite("SessionViewModel — Wall-Clock Timer")
struct WallClockTimerTests {
    @Test("recalculateFromWallClock updates remainingSeconds from wall clock")
    @MainActor func recalculateUpdatesRemaining() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)

        // Simulate 30 seconds passing by backdating the start
        vm.sessionStartDate = Date().addingTimeInterval(-30)
        vm.remainingSeconds = vm.timerMinutes * 60 // reset to full

        // Trigger recalculation via foreground transition
        vm.handleForegroundTransition()

        // Should be approximately totalDuration - 30
        let expected = vm.timerMinutes * 60 - 30
        #expect(vm.remainingSeconds >= expected - 1)
        #expect(vm.remainingSeconds <= expected + 1)
    }

    @Test("Session stops when wall clock shows time expired")
    @MainActor func sessionStopsWhenExpired() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)

        // Backdate start so session has expired
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 10))

        vm.handleForegroundTransition()

        #expect(!vm.isRunning)
        #expect(!vm.isPaused)
        #expect(vm.remainingSeconds == 0)
    }

    @Test("Pause time is excluded from elapsed calculation")
    @MainActor func pauseTimeExcluded() {
        let (vm, _) = makeVM()
        vm.selectMode(.custom)
        vm.timerMinutes = 10
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()

        // Simulate: started 120s ago, paused for 60s of that
        vm.sessionStartDate = Date().addingTimeInterval(-120)
        vm.accumulatedPauseTime = 60

        vm.handleForegroundTransition()

        // Active time = 120 - 60 = 60s, remaining = 600 - 60 = 540
        #expect(vm.remainingSeconds >= 539)
        #expect(vm.remainingSeconds <= 541)
    }
}

// MARK: - Scene Phase Tests

@Suite("SessionViewModel — Scene Phase")
struct ScenePhaseTests {
    @Test("Background transition stops countdown but keeps session running")
    @MainActor func backgroundKeepsSession() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief)

        vm.handleBackgroundTransition()

        #expect(vm.isRunning)
        #expect(vm.backgroundEntryDate != nil)
    }

    @Test("Background transition is ignored when not running")
    @MainActor func backgroundIgnoredWhenIdle() {
        let (vm, _) = makeVM()

        vm.handleBackgroundTransition()

        #expect(!vm.isRunning)
        #expect(vm.backgroundEntryDate == nil)
    }

    @Test("Foreground transition recalculates and keeps running if time remains")
    @MainActor func foregroundResumesSession() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        let totalDuration = vm.timerMinutes * 60

        // Simulate 10s in background
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleBackgroundTransition()
        vm.handleForegroundTransition()

        #expect(vm.isRunning)
        #expect(vm.remainingSeconds < totalDuration)
        #expect(vm.remainingSeconds > 0)
    }

    @Test("Foreground transition stops session if time expired while backgrounded")
    @MainActor func foregroundStopsExpiredSession() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)

        // Simulate time well past session end
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 100))
        vm.handleBackgroundTransition()
        vm.handleForegroundTransition()

        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == 0)
    }

    @Test("Foreground transition is ignored when not running")
    @MainActor func foregroundIgnoredWhenIdle() {
        let (vm, _) = makeVM()

        vm.handleForegroundTransition()

        #expect(!vm.isRunning)
    }
}

// MARK: - Session Persistence Tests

@Suite("SessionViewModel — Persistence")
struct SessionPersistenceTests {
    @Test("start() persists session state")
    @MainActor func startPersists() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .sleep, strength: 7)

        let d = vm.defaults
        #expect(d.object(forKey: "session.startDate") != nil)
        #expect(d.integer(forKey: "session.totalDuration") == StimulationMode.sleep.defaultDurationMinutes * 60)
        #expect(d.string(forKey: "session.mode") == "sleep")
        #expect(d.integer(forKey: "session.strength") == 7)
        #expect(d.bool(forKey: "session.isPaused") == false)
    }

    @Test("stop() clears persisted state")
    @MainActor func stopClears() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.stop()

        let d = vm.defaults
        #expect(d.object(forKey: "session.startDate") == nil)
        #expect(d.object(forKey: "session.totalDuration") == nil)
        #expect(d.object(forKey: "session.mode") == nil)
    }

    @Test("pause() persists paused state")
    @MainActor func pausePersists() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 3)
        vm.pause()

        let d = vm.defaults
        #expect(d.bool(forKey: "session.isPaused") == true)
        #expect(d.object(forKey: "session.pauseStartDate") != nil)
        #expect(d.string(forKey: "session.mode") == "focus")
    }

    @Test("resume() persists resumed state")
    @MainActor func resumePersists() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .calm, strength: 5)
        vm.pause()
        vm.resume()

        let d = vm.defaults
        #expect(d.bool(forKey: "session.isPaused") == false)
        #expect(d.double(forKey: "session.accumulatedPauseTime") >= 0)
    }

    @Test("background transition persists session for crash recovery")
    @MainActor func backgroundPersists() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .painRelief, strength: 6)

        // Clear to verify background re-persists
        vm.defaults.removeObject(forKey: "session.startDate")
        vm.handleBackgroundTransition()

        #expect(vm.defaults.object(forKey: "session.startDate") != nil)
    }

    @Test("Feeling is persisted and restored")
    @MainActor func feelingPersisted() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.anxious)
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()

        #expect(vm.defaults.string(forKey: "session.feeling") == "anxious")
        #expect(vm.defaults.string(forKey: "session.mode") == "calm")
    }
}

// MARK: - Session Restore Tests

@Suite("SessionViewModel — Restore")
struct SessionRestoreTests {
    @Test("Restores running session on init")
    @MainActor func restoreRunning() {
        // Set up persisted state as if a session started 30s ago with 10 min duration
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("stressRelief", forKey: "session.mode")
        d.set(7, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(vm.isRunning)
        #expect(!vm.isPaused)
        #expect(vm.selectedMode == .stressRelief)
        #expect(vm.strength == 7)
        // ~570s remaining (600 - 30)
        #expect(vm.remainingSeconds >= 568)
        #expect(vm.remainingSeconds <= 572)
        #expect(vm.stimulationActive)
    }

    @Test("Restores paused session on init")
    @MainActor func restorePaused() {
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-120)
        let pauseStart = Date().addingTimeInterval(-60) // paused 60s ago
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(pauseStart.timeIntervalSince1970, forKey: "session.pauseStartDate")
        d.set(true, forKey: "session.isPaused")
        d.set("focus", forKey: "session.mode")
        d.set(4, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(!vm.isRunning)
        #expect(vm.isPaused)
        #expect(vm.selectedMode == .focus)
        #expect(vm.strength == 4)
        // Active time = 120 - 0 - 60 = 60s, remaining = 600 - 60 = 540
        #expect(vm.remainingSeconds >= 538)
        #expect(vm.remainingSeconds <= 542)
    }

    @Test("Expired session is not restored")
    @MainActor func expiredNotRestored() {
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-700) // 700s ago, 600s session
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(!vm.isRunning)
        #expect(!vm.isPaused)
        #expect(vm.remainingSeconds == 0)
        // Persisted data should be cleared
        #expect(d.object(forKey: "session.startDate") == nil)
    }

    @Test("No persisted data means fresh VM")
    @MainActor func noPersistenceStartsFresh() {
        let (vm, _) = makeVM()

        #expect(!vm.isRunning)
        #expect(!vm.isPaused)
        #expect(vm.remainingSeconds == 0)
        #expect(vm.selectedMode == .custom)
    }

    @Test("Restores feeling when persisted")
    @MainActor func restoresFeeling() {
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.set(Date().addingTimeInterval(-10).timeIntervalSince1970, forKey: "session.startDate")
        d.set(300, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("calm", forKey: "session.mode")
        d.set("anxious", forKey: "session.feeling")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(vm.selectedMode == .calm)
        #expect(vm.selectedFeeling == .anxious)
        #expect(vm.isRunning)
    }

    @Test("Invalid totalDuration clears persisted state")
    @MainActor func invalidDurationClears() {
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.set(Date().timeIntervalSince1970, forKey: "session.startDate")
        d.set(0, forKey: "session.totalDuration")

        let (vm, _) = makeVM(defaults: d)

        #expect(!vm.isRunning)
        #expect(d.object(forKey: "session.startDate") == nil)
    }

    @Test("Strength defaults to 5 when persisted as 0")
    @MainActor func strengthDefaultsTo5() {
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.set(Date().addingTimeInterval(-10).timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(false, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        d.set(0, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(vm.strength == 5)
    }
}

// MARK: - Round-trip Persistence Tests

@Suite("SessionViewModel — Persistence Round-Trip")
struct PersistenceRoundTripTests {
    @Test("Start and restore produces equivalent state")
    @MainActor func startRestoreRoundTrip() {
        let suiteName = "test.roundtrip.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!

        // Start a session
        let (vm1, _) = makeVM(defaults: d)
        vm1.selectFeeling(.wired)
        vm1.ble.isConnected = true
        vm1.ble.isReady = true
        vm1.start()
        vm1.handleBackgroundTransition()

        // "Kill" and restore
        let (vm2, _) = makeVM(defaults: d)

        #expect(vm2.isRunning)
        #expect(vm2.selectedMode == .sleep)
        #expect(vm2.selectedFeeling == .wired)
        #expect(vm2.strength == vm1.strength)
        #expect(vm2.remainingSeconds > 0)
    }

    @Test("Pause and restore produces paused state")
    @MainActor func pauseRestoreRoundTrip() {
        let suiteName = "test.roundtrip.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!

        let (vm1, _) = makeVM(defaults: d)
        vm1.selectMode(.focus)
        vm1.ble.isConnected = true
        vm1.ble.isReady = true
        vm1.start()
        vm1.pause()

        let (vm2, _) = makeVM(defaults: d)

        #expect(vm2.isPaused)
        #expect(!vm2.isRunning)
        #expect(vm2.selectedMode == .focus)
        #expect(vm2.remainingSeconds > 0)
    }

    @Test("Stop then restore produces fresh state")
    @MainActor func stopRestoreRoundTrip() {
        let suiteName = "test.roundtrip.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!

        let (vm1, _) = makeVM(defaults: d)
        simulateRunning(vm1, mode: .stressRelief)
        vm1.stop()

        let (vm2, _) = makeVM(defaults: d)

        #expect(!vm2.isRunning)
        #expect(!vm2.isPaused)
        #expect(vm2.remainingSeconds == 0)
    }
}

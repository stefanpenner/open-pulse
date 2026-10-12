import Foundation
import UIKit
import Testing
@testable import OpenPulse

// MARK: - Helpers

/// Recording double for session-end local alerts (no system notifications).
@MainActor
final class RecordingSessionEndNotifier: SessionEndNotifying {
    private(set) var cancelCount = 0
    private(set) var scheduleCount = 0
    private(set) var lastSchedule: (endsAt: Date, modeName: String)?
    /// When set, drives requestAuthorization / fetchCanDeliver without system UI.
    var canDeliver: Bool = true
    var authGranted: Bool = true

    func cancel() {
        cancelCount += 1
        lastSchedule = nil
    }

    func schedule(endsAt: Date, modeName: String, enabled: Bool, now: Date) {
        guard enabled, endsAt > now else { return }
        scheduleCount += 1
        lastSchedule = (endsAt, modeName)
    }

    func requestAuthorizationIfNeeded(completion: (@MainActor @Sendable (Bool) -> Void)?) {
        // Synchronous on MainActor (matches unit-test inject contract)
        completion?(authGranted)
    }

    func fetchCanDeliver(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        completion(canDeliver)
    }
}

/// Recording double for mindful HealthKit writes (no HKHealthStore).
@MainActor
final class RecordingMindfulMinutesStore: MindfulMinutesWriting {
    private(set) var saveCalls: [(start: Date, end: Date)] = []
    private(set) var authRequestCount = 0
    var shouldThrow = false

    func requestAuthorization() async throws {
        authRequestCount += 1
        if shouldThrow { throw MindfulMinutesStore.MindfulError.unavailable }
    }

    func saveSession(start: Date, end: Date) async throws {
        if shouldThrow { throw MindfulMinutesStore.MindfulError.unavailable }
        saveCalls.append((start, end))
    }
}

/// Recording double for Live Activity (no ActivityKit).
@MainActor
final class RecordingLiveActivity: SessionLiveActivityPresenting {
    private(set) var startCount = 0
    private(set) var updateCount = 0
    private(set) var endCount = 0
    private(set) var lastEndReason: SessionLiveActivityController.EndReason?
    private(set) var lastEndModeName: String?
    private(set) var lastPendingDeviceOff = false
    private(set) var lastIsPaused = false
    private(set) var lastIsLinkReady = true
    private(set) var lastStatusText = ""

    func start(
        mode: StimulationMode,
        totalSeconds: Int,
        remainingSeconds: Int,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool,
        isPaused: Bool,
        isLinkReady: Bool
    ) {
        startCount += 1
        lastPendingDeviceOff = pendingDeviceOff
        lastIsPaused = isPaused
        lastIsLinkReady = isLinkReady
        lastStatusText = statusText
    }

    func update(
        remainingSeconds: Int,
        totalSeconds: Int,
        isPaused: Bool,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool,
        isLinkReady: Bool
    ) {
        updateCount += 1
        lastPendingDeviceOff = pendingDeviceOff
        lastIsPaused = isPaused
        lastIsLinkReady = isLinkReady
        lastStatusText = statusText
    }

    private(set) var lastEndPendingDeviceOff: Bool?
    private(set) var hardwareOffConfirmedCount = 0

    func end(
        reason: SessionLiveActivityController.EndReason,
        modeName: String,
        pendingDeviceOff: Bool
    ) {
        endCount += 1
        lastEndReason = reason
        lastEndModeName = modeName
        lastEndPendingDeviceOff = pendingDeviceOff
    }

    func noteHardwareOffConfirmed() {
        hardwareOffConfirmedCount += 1
        lastEndPendingDeviceOff = false
    }
}

/// Creates a VM with mock transport (no CoreBluetooth) + isolated UserDefaults.
@MainActor
private func makeVM(
    endNotifier: (any SessionEndNotifying)? = nil,
    mindfulStore: (any MindfulMinutesWriting)? = nil,
    liveActivity: (any SessionLiveActivityPresenting)? = nil,
    ambientAudio: (any SessionAmbientAudioPlaying)? = nil
) -> (SessionViewModel, MockDeviceTransport) {
    let suiteName = "test.session.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    let mock = MockDeviceTransport()
    // Known pack by default so Start gate grace does not block unrelated tests
    mock.batteryPercentage = 80
    mock.batterySampleConfirmed = true
    let vm = SessionViewModel(
        defaults: defaults,
        ble: mock,
        endNotifier: endNotifier,
        mindfulStore: mindfulStore,
        liveActivity: liveActivity,
        ambientAudio: ambientAudio ?? NullAmbientAudio()
    )
    return (vm, mock)
}

/// Creates a VM that reads from the given UserDefaults (for restore tests).
@MainActor
private func makeVM(
    defaults: UserDefaults,
    endNotifier: (any SessionEndNotifying)? = nil,
    mindfulStore: (any MindfulMinutesWriting)? = nil,
    liveActivity: (any SessionLiveActivityPresenting)? = nil,
    ambientAudio: (any SessionAmbientAudioPlaying)? = nil
) -> (SessionViewModel, MockDeviceTransport) {
    let mock = MockDeviceTransport()
    let vm = SessionViewModel(
        defaults: defaults,
        ble: mock,
        endNotifier: endNotifier,
        mindfulStore: mindfulStore,
        liveActivity: liveActivity,
        ambientAudio: ambientAudio ?? NullAmbientAudio()
    )
    return (vm, mock)
}

/// Puts the VM into a "running session" state by calling start() with a ready mock link.
@MainActor
private func simulateRunning(_ vm: SessionViewModel, mode: StimulationMode = .stressRelief, strength: Int = 5) {
    vm.selectMode(mode)
    vm.strength = strength
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

    @Test("setStrength clears soft effectiveStrength so keepalive uses user target")
    @MainActor func setStrengthClearsSoftEffective() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        // processTick at start should show soft ease-in for target ≥ 3
        if SoftStart.isNeeded(target: 5) {
            #expect(vm.effectiveStrength == SoftStart.initialStrength(target: 5)
                    || vm.modeStatus.contains("Easing"))
        }
        spy.reset()
        vm.setStrength(7)
        #expect(vm.strength == 7)
        #expect(vm.effectiveStrength == nil, "Must not keep soft override after user raise")
        #expect(spy.commands.contains("7\n"))
    }

    @Test("setStrength same value is a no-op (no BLE, pin untouched)")
    @MainActor func setStrengthSameValueNoOp() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .sleep, strength: 5)
        // Settle past soft so pin is not mid-soft noise
        for _ in 0..<6 {
            vm.sessionStartDate = Date().addingTimeInterval(-12)
            vm.handleForegroundTransition()
        }
        spy.reset()
        let pinBefore = vm.defaults.integer(forKey: "session.userStrengthFloor")
        let cmdCountBefore = spy.commands.count
        vm.setStrength(5)
        #expect(vm.strength == 5)
        #expect(spy.commands.count == cmdCountBefore, "Same strength must not re-send BLE")
        #expect(vm.defaults.integer(forKey: "session.userStrengthFloor") == pinBefore)
    }

    @Test("Pain setStrength does not base-then-wave double write")
    @MainActor func painSetStrengthNoBaseSpike() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .painRelief, strength: 5)
        // Past soft into wave
        vm.sessionStartDate = Date().addingTimeInterval(-20)
        vm.handleForegroundTransition()
        spy.reset()
        vm.setStrength(7)
        #expect(vm.strength == 7)
        // Strength lines only — must not be [7, wave] blip; wave is 6…8
        let strengths = spy.commands.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { $0 >= 1 && $0 <= 9 }
        #expect(!strengths.isEmpty, "cmds=\(spy.commands)")
        #expect(!strengths.contains(where: { $0 == 7 }) || strengths.count == 1,
                "Must not send absolute 7 then wave, cmds=\(spy.commands)")
        // All strength writes in 6…8 (base 7 ±1) — never bare 5 leftover
        #expect(strengths.allSatisfy { (6...8).contains($0) }, "cmds=\(spy.commands)")
    }

    @Test("Stress start shows easing status immediately")
    @MainActor func stressStartShowsEasing() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(vm.modeStatus.contains("Easing") || vm.effectiveStrength == 3)
        #expect(vm.stimulationActive)
    }

    @Test("Disconnect mid-run shows Reconnecting not stim-on copy")
    @MainActor func disconnectShowsReconnecting() {
        let la = RecordingLiveActivity()
        let (vm, _) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(vm.isRunning)
        #expect(la.lastIsLinkReady == true)
        vm.ble.isReady = false
        vm.ble.isConnected = false
        // onDisconnect is @MainActor — handleDisconnect runs same turn
        vm.ble.onDisconnect?()
        #expect(vm.isRunning)
        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
        #expect(vm.modeStatus.contains("Reconnecting"))
        #expect(vm.sessionStatusText == "Reconnecting…")
        #expect(la.updateCount >= 1 || la.startCount >= 1)
        #expect(la.lastIsLinkReady == false, "LA must drop link honesty")
        #expect(
            la.lastStatusText.contains("Reconnecting")
                || vm.sessionStatusText.contains("Reconnecting"),
            "status=\(la.lastStatusText) / \(vm.sessionStatusText)"
        )
    }

    @Test("Ready false mid-run freezes LA without full disconnect callback")
    @MainActor func readyFalseFreezesLAWithoutDisconnect() {
        let la = RecordingLiveActivity()
        let (vm, _) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let updatesBefore = la.updateCount
        // UART lost readiness only — common mid-session blip path
        vm.ble.isReady = false
        #expect(vm.isRunning)
        #expect(vm.offlineSince != nil)
        #expect(vm.pendingDeactivate)
        #expect(vm.modeStatus.contains("Reconnecting"))
        #expect(!vm.stimulationActive)
        #expect(la.updateCount > updatesBefore, "must push Island before process may die")
        #expect(la.lastIsLinkReady == false)
        #expect(
            la.lastStatusText.contains("Reconnecting")
                || vm.sessionStatusText.contains("Reconnecting")
        )
    }

    @Test("Background transition pushes LA while running")
    @MainActor func backgroundPushesLiveActivity() {
        let la = RecordingLiveActivity()
        let (vm, _) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let updatesBefore = la.updateCount
        vm.handleBackgroundTransition()
        #expect(vm.isRunning)
        #expect(la.updateCount > updatesBefore, "BG must refresh Island before suspend")
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

    @Test("selectFeeling maps picker + legacy states to primary modes")
    @MainActor func allFeelingsMapCorrectly() {
        // Primary picker (5) + legacy merges (learn→focus, med→calm, nausea→stress, head→pain)
        let expected: [(AutonomicState, StimulationMode)] = [
            (.stressed, .stressRelief),
            (.anxious, .calm),
            (.wired, .sleep),
            (.foggy, .focus),
            (.learning, .focus),
            (.hurting, .painRelief),
            (.headachy, .painRelief),
            (.nauseous, .stressRelief),
            (.scattered, .calm),
        ]

        for (state, mode) in expected {
            let (vm, _) = makeVM()
            vm.selectFeeling(state)
            #expect(vm.selectedMode == mode, "Expected \(state) → \(mode)")
            #expect(vm.selectedFeeling == state)
        }
    }

    @Test("Picker exposes five feelings only")
    @MainActor func pickerFiveFeelings() {
        #expect(AutonomicState.pickerCases.count == 5)
        #expect(AutonomicState.pickerCases == [.stressed, .anxious, .wired, .foggy, .hurting])
    }

    @Test("Legacy learning selects focus with study duration")
    @MainActor func learningMapsToFocusStudy() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.learning)
        #expect(vm.selectedMode == .focus)
        #expect(vm.timerMinutes == 10)
    }

    @Test("Legacy scattered selects breathe with meditate pace")
    @MainActor func scatteredMapsToBreatheMeditate() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.scattered)
        #expect(vm.selectedMode == .calm)
        #expect(vm.breathePace == .meditate)
    }

    @Test("Legacy headachy selects ease with burst pattern")
    @MainActor func headachyMapsToEaseBurst() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.headachy)
        #expect(vm.selectedMode == .painRelief)
        #expect(vm.easePattern == .burst)
    }

    @Test("Default mode is Stress (Still shell)")
    @MainActor func defaultModeIsStress() {
        let (vm, _) = makeVM()
        #expect(vm.selectedMode == .stressRelief)
        #expect(vm.selectedFeeling == .stressed)
    }

    @Test("resolveEngine uses breathe pace and ease pattern")
    @MainActor func resolveEngineOptions() {
        let (vm, _) = makeVM()
        vm.selectMode(.calm)
        vm.breathePace = .meditate
        let med = vm.resolveEngine()
        #expect(med != nil)
        // Meditation cycle is slower than calm — different type via start cmds both begin off
        var eng = med!
        let cmds = eng.start(baseStrength: 5, totalDuration: 300)
        #expect(cmds.contains(where: { $0.hasPrefix("0") || $0 == "0\n" || $0.trimmingCharacters(in: .whitespacesAndNewlines) == "0" }))

        vm.selectMode(.painRelief)
        vm.easePattern = .burst
        #expect(vm.resolveEngine() != nil)
        vm.easePattern = .wave
        #expect(vm.resolveEngine() != nil)
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

    @Test("increaseTimer extends remaining while running (not timerMinutes)")
    @MainActor func increaseExtendsRemainingWhenRunning() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        let before = vm.remainingSeconds
        let planned = vm.timerMinutes
        vm.increaseTimer()
        #expect(vm.timerMinutes == planned, "Planned minutes stay fixed mid-session")
        #expect(vm.remainingSeconds == before + 60)
    }

    @Test("decreaseTimer shortens remaining while paused")
    @MainActor func decreaseShortensRemainingWhenPaused() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        vm.pause()
        // Ensure enough remaining to decrease by 60s without floor at 60
        vm.remainingSeconds = 180
        vm.decreaseTimer()
        #expect(vm.isPaused)
        #expect(vm.remainingSeconds == 120)
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

    @Test("Picker order is five primary feelings")
    func caseOrder() {
        #expect(AutonomicState.pickerCases == [.stressed, .anxious, .wired, .foggy, .hurting])
        // Legacy cases remain decodable for history/restore
        #expect(AutonomicState.allCases.contains(.learning))
        #expect(AutonomicState.allCases.contains(.scattered))
    }

    @Test("Primary modes surface is five plus custom")
    func primaryModesCatalog() {
        #expect(StimulationMode.primaryModes == [
            .stressRelief, .sleep, .focus, .calm, .painRelief
        ])
        #expect(StimulationMode.calm.name == "Breathe")
        #expect(StimulationMode.painRelief.name == "Ease")
    }

    @Test("Labels are user-facing feeling words")
    func feelingLabels() {
        #expect(AutonomicState.stressed.label == "Stressed")
        #expect(AutonomicState.anxious.label == "Anxious")
        #expect(AutonomicState.wired.label == "Can't Sleep")
        #expect(AutonomicState.foggy.label == "Foggy")
        #expect(AutonomicState.learning.label == "Learning")
        #expect(AutonomicState.hurting.label == "Aching")
        #expect(AutonomicState.headachy.label == "Head-heavy")
        #expect(AutonomicState.nauseous.label == "Queasy")
        #expect(AutonomicState.scattered.label == "Scattered")
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

// MARK: - Start gate (device ready)

@Suite("SessionViewModel — Start Gate")
struct StartGateTests {
    @Test("canStart is false when BLE not ready")
    @MainActor func canStartRequiresReady() {
        let (vm, _) = makeVM()
        vm.ble.isConnected = false
        vm.ble.isReady = false
        #expect(!vm.canStart)
        #expect(vm.startBlockedReason != nil)
    }

    @Test("canStart is true when idle and ready")
    @MainActor func canStartWhenReady() {
        let (vm, _) = makeVM()
        vm.ble.isConnected = true
        vm.ble.isReady = true
        #expect(vm.canStart)
        #expect(vm.startBlockedReason == nil)
    }

    @Test("start() is ignored when device not ready")
    @MainActor func startIgnoredWhenNotReady() {
        let (vm, spy) = makeVM()
        vm.ble.isConnected = false
        vm.ble.isReady = false
        vm.selectMode(.stressRelief)

        vm.start()

        #expect(!vm.isRunning)
        #expect(spy.commands.isEmpty)
    }

    @Test("start() succeeds when ready")
    @MainActor func startSucceedsWhenReady() {
        let (vm, _) = makeVM()
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(vm.isRunning)
    }

    @Test("canStart is false while running")
    @MainActor func canStartFalseWhileRunning() {
        let (vm, _) = makeVM()
        simulateRunning(vm)
        #expect(!vm.canStart)
    }

    @Test("canStart is false when battery empty")
    @MainActor func canStartFalseWhenBatteryEmpty() {
        let (vm, _) = makeVM()
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.ble.batteryPercentage = 0
        vm.ble.batterySampleConfirmed = true
        vm.ble.isCharging = false
        #expect(!vm.canStart)
        #expect(vm.startBlockedReason == BatteryPresentation.startBlockedEmptyCopy)
    }

    @Test("start() is ignored when battery empty")
    @MainActor func startIgnoredWhenBatteryEmpty() {
        let (vm, spy) = makeVM()
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.ble.batteryPercentage = 0
        vm.ble.batterySampleConfirmed = true
        vm.ble.isCharging = false
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(!vm.isRunning)
        #expect(spy.commands.isEmpty)
    }

    @Test("canStart when empty pack is charging")
    @MainActor func canStartWhenEmptyButCharging() {
        let (vm, _) = makeVM()
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.ble.batteryPercentage = 0
        vm.ble.batterySampleConfirmed = true
        vm.ble.isCharging = true
        #expect(vm.canStart)
        #expect(vm.startBlockedReason == nil)
    }

    @Test("canStart blocked while battery unknown within grace")
    @MainActor func canStartBlockedWhileReadingBattery() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        vm.now = { t0 }
        mock.isConnected = true
        mock.batteryPercentage = nil
        mock.batterySampleConfirmed = false
        mock.isCharging = false
        mock.becomeReady(confirmBattery: false)
        // Within grace — awaiting first Q
        #expect(!vm.canStart)
        #expect(vm.startBlockedReason == BatteryPresentation.startBlockedReadingCopy)
    }

    @Test("canStart when battery still nil after grace")
    @MainActor func canStartWhenBatteryUnknownAfterGrace() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_100)
        vm.now = { t0 }
        mock.isConnected = true
        mock.batteryPercentage = nil
        mock.batterySampleConfirmed = false
        mock.isCharging = false
        mock.becomeReady(confirmBattery: false)
        // Past grace — mute UART must not brick Start forever
        vm.now = { t0.addingTimeInterval(BatteryPresentation.unknownGraceSeconds + 0.1) }
        #expect(vm.canStart)
        #expect(vm.startBlockedReason == nil)
    }

    @Test("canStart when battery arrives during grace")
    @MainActor func canStartWhenBatteryArrivesDuringGrace() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_200)
        vm.now = { t0 }
        mock.isConnected = true
        mock.batteryPercentage = nil
        mock.batterySampleConfirmed = false
        mock.becomeReady(confirmBattery: false)
        #expect(!vm.canStart)
        mock.batteryPercentage = 60
        mock.batterySampleConfirmed = true
        #expect(vm.canStart)
    }

    @Test("Short offline blip keeps running session")
    @MainActor func shortOfflineKeepsRunning() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_300)
        vm.now = { t0 }
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        mock.isReady = false
        mock.isConnected = false
        #expect(vm.isRunning)
        #expect(vm.offlineSince != nil)
        #expect(vm.pendingDeactivate, "mid-run drop arms durable off immediately")
        // Before threshold
        vm.now = { t0.addingTimeInterval(SessionLinkSafety.offlineAutoPauseSeconds - 10) }
        vm.considerOfflineAutoPause()
        #expect(vm.isRunning)
        #expect(!vm.isPaused)
        mock.becomeReady()
        #expect(vm.isRunning, "short blip reconnect keeps running")
        #expect(vm.offlineSince == nil)
        // Lead-0 ACK clears durable pending after reprogram
        mock.completeWrite("0\n", success: true)
        #expect(!vm.pendingDeactivate)
    }

    @Test("Long offline auto-pauses and arms durable off")
    @MainActor func longOfflineAutoPauses() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_400)
        vm.now = { t0 }
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        mock.isReady = false
        mock.isConnected = false
        #expect(vm.isRunning)
        #expect(vm.pendingDeactivate, "mid-run drop arms durable off")
        vm.now = { t0.addingTimeInterval(SessionLinkSafety.offlineAutoPauseSeconds + 1) }
        vm.considerOfflineAutoPause()
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate, "auto-pause keeps HW off")
        #expect(vm.offlineSince == nil)
        // Late ready must not auto-resume
        mock.becomeReady()
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
    }

    @Test("Late ready after long offline pauses and does not reprogram")
    @MainActor func lateReadyAfterLongOfflineDoesNotRestim() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_500)
        vm.now = { t0 }
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let remainingAtDrop = vm.remainingSeconds
        mock.reset()
        mock.isReady = false
        mock.isConnected = false
        #expect(vm.offlineSince != nil)
        vm.now = { t0.addingTimeInterval(SessionLinkSafety.offlineAutoPauseSeconds + 30) }
        mock.becomeReady()
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate)
        #expect(
            !mock.commands.contains(BLEConstants.activateCommand),
            "late ready must not reprogram stim, got \(mock.commands)"
        )
        #expect(mock.commands.contains(BLEConstants.deactivateCommand))
        let burned = remainingAtDrop - vm.remainingSeconds
        #expect(burned == Int(SessionLinkSafety.offlineAutoPauseSeconds))
    }

    @Test("Late auto-pause freezes practice at the threshold, not at wake")
    @MainActor func lateAutoPauseFreezesAtThreshold() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_600)
        vm.now = { t0 }
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let remainingAtDrop = vm.remainingSeconds
        mock.isReady = false
        mock.isConnected = false
        #expect(vm.offlineSince != nil)
        vm.now = { t0.addingTimeInterval(SessionLinkSafety.offlineAutoPauseSeconds + 30) }
        vm.considerOfflineAutoPause()
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        let burned = remainingAtDrop - vm.remainingSeconds
        #expect(burned == Int(SessionLinkSafety.offlineAutoPauseSeconds),
                "late wake must not burn the extra 30s, burned=\(burned)")
    }

    @Test("Cold launch already ready after long offline does not reprogram")
    @MainActor func coldLaunchReadyLongOfflineDoesNotRestim() {
        let suite = "test.offline.ready.cold.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let now = Date()
        let start = now.addingTimeInterval(-200)
        let offlineAt = now.addingTimeInterval(-120)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(offlineAt.timeIntervalSince1970, forKey: "session.offlineSince")
        // Fresh lastAlive must not win over the durable offline clock.
        d.set(now.addingTimeInterval(-10).timeIntervalSince1970, forKey: "session.lastAlive")
        AppPreferences.setPendingDeactivate(true, defaults: d)

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isPaused, "ready cold launch must pause a long drop")
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate)
        #expect(
            !mock.commands.contains(BLEConstants.activateCommand),
            "must not reprogram, cmds=\(mock.commands)"
        )
        let freeze = SessionLinkSafety.autoPauseFreezeDate(offlineSince: offlineAt)
        let expected = 600 - Int(freeze.timeIntervalSince(start))
        #expect(abs(vm.remainingSeconds - expected) <= 2,
                "remaining=\(vm.remainingSeconds) expected~\(expected)")
    }

    @Test("Cold launch already ready after a short drop stays running")
    @MainActor func coldLaunchReadyShortOfflineKeepsRunning() {
        let suite = "test.offline.ready.short.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let now = Date()
        let start = now.addingTimeInterval(-100)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(now.addingTimeInterval(-20).timeIntervalSince1970, forKey: "session.offlineSince")
        d.set(now.addingTimeInterval(-10).timeIntervalSince1970, forKey: "session.lastAlive")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(!vm.isPaused)
        let programs = mock.commands.filter { $0 == BLEConstants.activateCommand }
        #expect(programs.count == 1, "one reprogram, cmds=\(mock.commands)")
    }

    @Test("Process kill after long offline restores paused not running")
    @MainActor func longOfflineSurvivesProcessKillAsPaused() {
        let suite = "test.offline.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-200)
        let offlineAt = Date().addingTimeInterval(-(SessionLinkSafety.offlineAutoPauseSeconds + 30))
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(offlineAt.timeIntervalSince1970, forKey: "session.offlineSince")
        AppPreferences.setPendingDeactivate(true, defaults: d)

        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isPaused, "long offline after kill must not restore as running")
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate)
        // Soft-after-pause armed for resume comfort
        mock.becomeReady()
        #expect(vm.isPaused, "ready alone never auto-resumes")
    }

    @Test("Kill restore remaining matches live auto-pause freeze (not drop time)")
    @MainActor func killRestoreRemainingMatchesLiveAutoPause() {
        let suite = "test.offline.kill.remaining.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // 600s session; started 200s ago; offline for 120s (threshold 90)
        // Live path freezes at offline+90 (= now-30); active = 170; remaining = 430
        let now = Date()
        let start = now.addingTimeInterval(-200)
        let offlineAt = now.addingTimeInterval(-120)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(offlineAt.timeIntervalSince1970, forKey: "session.offlineSince")

        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        // Threshold freeze: active = (offlineAt+90) - start = 170 → remaining 430
        // Drop-time freeze would wrongly yield remaining 520
        let freeze = SessionLinkSafety.autoPauseFreezeDate(offlineSince: offlineAt)
        let activeAtFreeze = Int(freeze.timeIntervalSince(start))
        let expectedRemaining = max(0, 600 - activeAtFreeze)
        #expect(abs(vm.remainingSeconds - expectedRemaining) <= 2,
                "remaining=\(vm.remainingSeconds) expected~\(expectedRemaining)")
        #expect(vm.remainingSeconds < 500,
                "must not over-credit by full offline window")
    }

    @Test("Restore mid-offline uses remaining delay not full 90s")
    @MainActor func restoreMidOfflineAutoPausesWithRemainingDelay() {
        let suite = "test.offline.mid.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // Session started earlier; offline for ~80s of 90s threshold (wall clock)
        let start = Date().addingTimeInterval(-200)
        let offlineAt = Date().addingTimeInterval(-80)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(offlineAt.timeIntervalSince1970, forKey: "session.offlineSince")

        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning, "80s offline still under threshold — keep running")
        #expect(vm.offlineSince != nil)
        #expect(vm.pendingDeactivate)
        // Remaining ~10s; jump past threshold via inject clock
        let base = Date()
        vm.now = { base.addingTimeInterval(20) }
        vm.considerOfflineAutoPause()
        #expect(vm.isPaused, "remaining delay must fire without waiting full 90s again")
        #expect(!vm.isRunning)
    }

    @Test("Jetsam with lastAlive restores paused not wall-finalized")
    @MainActor func jetsamLastAliveRestoresPaused() {
        let suite = "test.restore.lastalive.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let now = Date()
        let start = now.addingTimeInterval(-300)
        let lastAlive = now.addingTimeInterval(-150) // gap 150s > 90
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(lastAlive.timeIntervalSince1970, forKey: "session.lastAlive")
        // no offlineSince — pure jetsam path

        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == 450 || abs(vm.remainingSeconds - 450) <= 2,
                "remaining=\(vm.remainingSeconds) expected~450 (freeze at lastAlive)")
        #expect(vm.completionBanner == nil)
        #expect(d.bool(forKey: "session.isPaused") == true)
    }

    @Test("Restore clamps corrupt strength into 1…9 (or mode default if missing)")
    @MainActor func restoreClampsCorruptStrength() {
        let suite = "test.restore.strengthclamp.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-30)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(99, forKey: "session.strength") // corrupt

        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect((1...9).contains(vm.strength), "must not surface raw 99")
        #expect(vm.strength == StimulationMode.stressRelief.defaultStrength
                || vm.strength == StrengthPresentation.clamp(99),
                "corrupt → mode default or clamp")
        // 99 is out of range → mode default (not silent clamp of garbage)
        #expect(vm.strength == StimulationMode.stressRelief.defaultStrength)
    }

    @Test("Offline-freeze restore persists paused stamp (survives second kill)")
    @MainActor func offlineFreezeRestorePersistsPausedStamp() {
        // R89: first restore used to clear offlineSince without writing isPaused/pauseStart.
        // Second kill then treated wall as practice → false complete or burned remaining.
        let suite = "test.offline.kill.persist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let now = Date()
        let start = now.addingTimeInterval(-200)
        let offlineAt = now.addingTimeInterval(-120)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(offlineAt.timeIntervalSince1970, forKey: "session.offlineSince")

        let mock1 = MockDeviceTransport()
        mock1.isConnected = false
        mock1.isReady = false
        let vm1 = SessionViewModel(defaults: d, ble: mock1)
        #expect(vm1.isPaused)
        let rem1 = vm1.remainingSeconds
        #expect(rem1 > 300, "freeze remaining must leave practice left")

        // Durable after first restore (no extra user action)
        #expect(d.bool(forKey: "session.isPaused") == true,
                "must persist isPaused after offline-freeze restore")
        #expect(d.object(forKey: "session.pauseStartDate") != nil,
                "must persist pauseStart at freeze wall")
        #expect(d.object(forKey: "session.offlineSince") == nil,
                "offline stamp cleared only after pause is durable")

        // Second cold launch (process kill again) — no offlineSince, must stay paused
        let mock2 = MockDeviceTransport()
        mock2.isConnected = false
        mock2.isReady = false
        let vm2 = SessionViewModel(defaults: d, ble: mock2)
        #expect(vm2.isPaused, "second kill must not re-run as active")
        #expect(!vm2.isRunning)
        #expect(abs(vm2.remainingSeconds - rem1) <= 2,
                "remaining must not burn wall between kills: \(vm2.remainingSeconds) vs \(rem1)")
        #expect(vm2.completionBanner == nil, "must not false-finalize")
    }
}

// MARK: - Safety: Background Expiry & Engine Ticks

@Suite("SessionViewModel — Background Safety")
struct BackgroundSafetyTests {
    @Test("Background BLE wake expires session when wall clock is past end")
    @MainActor func backgroundWakeExpiresSession() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)

        // Session already expired by wall clock
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 30))
        vm.handleBackgroundTransition()
        #expect(vm.isRunning)

        spy.reset()
        // Simulate BLE TX notification that drives the background loop
        vm.ble.onNotification?()

        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == 0)
        #expect(spy.commands.contains("0\n"), "Must deactivate device on expire")
    }

    @Test("Ready after expire wall-clock does not reprogram stim")
    @MainActor func readyAfterExpireDoesNotReprogram() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        // Past endsAt while "running" with stale remaining
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 45))
        // Drop ready then restore — sink must wall-expire before resumeSessionOnDevice
        vm.ble.isReady = false
        spy.reset()
        vm.ble.isReady = true

        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == 0)
        // Ordering: final safety must be off — no channel after last 0
        if let lastOff = spy.commands.lastIndex(of: "0\n") {
            let after = spy.commands.suffix(from: spy.commands.index(after: lastOff))
            #expect(!after.contains("D\n") && !after.contains("A\n"),
                    "No activate after final off, cmds=\(spy.commands)")
        } else {
            #expect(vm.pendingDeactivate, "Must pending off if off not yet enqueued")
        }
    }

    @Test("Restore running past endsAt expires and requests off")
    @MainActor func restoreRunningPastEndExpires() {
        let suiteName = "test.restore.pastend.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        // Session started long ago — already past planned end
        let startDate = Date().addingTimeInterval(-900)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("stressRelief", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == 0)
        #expect(vm.pendingDeactivate)
    }

    @Test("Background BLE wake runs engine tick for duty-cycle modes")
    @MainActor func backgroundWakeTicksEngine() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // Focus: on for first 30s, off after
        // Backdate so elapsed is in off phase (~35s)
        vm.sessionStartDate = Date().addingTimeInterval(-35)
        vm.handleBackgroundTransition()
        spy.reset()

        vm.ble.onNotification?()

        // Still running (time left), but stim should be off in focus rest phase
        #expect(vm.isRunning)
        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
        #expect(spy.commands.contains("0\n"))
    }

    @Test("Small background poll gap does not absolute-reassert (no stim blip)")
    @MainActor func smallGapNoAbsoluteBlip() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        // Establish lastTick at ~10s
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        spy.reset()

        // 5s poll-sized gap (below absoluteReassertMinGapSeconds for continuous)
        vm.sessionStartDate = Date().addingTimeInterval(-15)
        vm.ble.onNotification?()

        #expect(vm.isRunning)
        // Keepalive strength OK; must NOT lead with forced absolute off reprogram
        // (no 0 followed by D/channel from absolute path for continuous stress)
        let hasForcedOffThenProgram =
            spy.commands.contains("0\n") &&
            (spy.commands.contains("D\n") || spy.commands.contains("A\n"))
        #expect(!hasForcedOffThenProgram,
                "5s gap must not absolute reassert, cmds=\(spy.commands)")
    }

    @Test("Sleep background mid-gap uses edge honesty threshold")
    @MainActor func sleepBackgroundMidGapReasserts() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .sleep, strength: 5)
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        spy.reset()
        // gap 12 (>= keepalive+1=11 edge threshold for Sleep)
        vm.sessionStartDate = Date().addingTimeInterval(-22)
        vm.ble.onNotification?()
        #expect(vm.isRunning)
        #expect(spy.commands.contains("0\n"), "Sleep edge honesty gap must reassert, cmds=\(spy.commands)")
    }

    @Test("Focus background mid-gap absolute reasserts edge honesty")
    @MainActor func focusBackgroundMidGapReasserts() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // lastTick ~10s (on phase)
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        spy.reset()

        // gap 12 (>= 11 edge, < 15 continuous) still on-phase
        vm.sessionStartDate = Date().addingTimeInterval(-22)
        vm.ble.onNotification?()

        #expect(vm.isRunning)
        #expect(spy.commands.contains("0\n"), "Edge honesty gap must reassert, cmds=\(spy.commands)")
    }

    @Test("Edge mode 10s BLE ping gap does not absolute-reassert")
    @MainActor func edgeModeKeepaliveGapNoBlip() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .sleep, strength: 5)
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        spy.reset()
        // exactly 10s gap (keepalive interval) — must NOT absolute off+reprogram
        vm.sessionStartDate = Date().addingTimeInterval(-20)
        vm.ble.onNotification?()
        let hasForcedOffThenProgram =
            spy.commands.contains("0\n") &&
            (spy.commands.contains("D\n") || spy.commands.contains("A\n") || spy.commands.contains("C\n"))
        #expect(!hasForcedOffThenProgram,
                "10s keepalive gap must not blip Sleep, cmds=\(spy.commands)")
    }

    @Test("Background large elapsed jump absolute reassert skips missed rest")
    @MainActor func backgroundLargeJumpAbsoluteReassert() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // Establish wasOn=true mid first on-window (~15s)
        vm.sessionStartDate = Date().addingTimeInterval(-15)
        // Force a tick at e≈15 so lastTickElapsed is set while on
        vm.handleForegroundTransition() // no-op if not bg; use notify after bg
        // Put in background with engine already ticked at ~15
        // Simulate tick via wall clock recalculate: jump to 15 first
        // Start at now, processTick at start established last at 0
        // Jump to 15s: may absolute reassert if last was 0 (jump >1)
        // Better: tick at 1s interval by backdating slightly
        spy.reset()
        // Elapsed ~15: on phase. Push background then jump +60s into next on (e≈75)
        // First establish lastTick at 15 via background notify
        vm.sessionStartDate = Date().addingTimeInterval(-15)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        #expect(vm.isRunning)
        spy.reset()

        // Large jump: skip rest window entirely (e 15 → 75, both on)
        vm.sessionStartDate = Date().addingTimeInterval(-75)
        vm.ble.onNotification?()

        #expect(vm.isRunning)
        // Forced comfort rest + absolute on-phase reassert (not keepalive strength alone)
        #expect(spy.commands.contains("0\n"), "Large jump must lead with off, cmds=\(spy.commands)")
        #expect(spy.commands.contains("A\n"), "On-phase absolute must reassert left, cmds=\(spy.commands)")
        // At e=75: on phase again — stim should be active after reassert
        #expect(vm.stimulationActive)
        #expect(vm.activeChannel == .left)
    }

    @Test("Background jump into Focus rest deactivates device")
    @MainActor func backgroundJumpIntoRestOff() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // Tick at e=10 (on)
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        spy.reset()

        // Jump into rest (e=40)
        vm.sessionStartDate = Date().addingTimeInterval(-40)
        vm.ble.onNotification?()

        #expect(vm.isRunning)
        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
        #expect(spy.commands.contains("0\n"))
    }

    @Test("start() is ignored when already running")
    @MainActor func startIgnoredWhenRunning() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let startDate = vm.sessionStartDate
        spy.reset()

        vm.start()

        #expect(vm.sessionStartDate == startDate)
        #expect(spy.commands.isEmpty)
    }

    @Test("start() is ignored when paused")
    @MainActor func startIgnoredWhenPaused() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.pause()
        let remaining = vm.remainingSeconds

        vm.start()

        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == remaining)
    }

    @Test("Meditation start begins with stim off and inhale phase")
    @MainActor func meditationStartsWithInhale() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .meditation, strength: 4)

        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
        if case .inhale = vm.breathingPhase {
            // expected
        } else {
            Issue.record("Expected inhale breathing phase at meditation start")
        }
        // Absolute-off first; no activate at start (same as calm)
        #expect(spy.commands.first == "0\n")
        #expect(!spy.commands.contains("D\n"))
    }

    @Test("Custom start leads with absolute off then channel")
    @MainActor func customStartLeadingOff() {
        let suiteName = "test.customstart.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        AppPreferences.saveCustomChannel("A", defaults: d)
        let (vm, spy) = makeVM(defaults: d)
        #expect(vm.customChannelCommand == "A")
        vm.selectMode(.custom)
        vm.strength = 5
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()

        #expect(vm.isRunning)
        #expect(spy.commands.first == "0\n", "Safety off before custom channel")
        #expect(spy.commands.contains("A\n"))
        // Soft-start first start (strength 5 → initial 3)
        #expect(spy.commands.contains("3\n"), "Custom soft-starts, cmds=\(spy.commands)")
        #expect(!spy.commands.contains("5\n") || spy.commands.last == "5\n")
        // Pending clears only after lead-0 ACK (not optimistically)
        spy.completeWrite("0\n", success: true)
        #expect(!vm.pendingDeactivate)
        #expect(vm.modeStatus.contains("Easing") || vm.effectiveStrength == 3)
    }

    @Test("Custom start soft-starts when strength warrants")
    @MainActor func customStartSoftStarts() {
        let (vm, spy) = makeVM()
        vm.selectMode(.custom)
        vm.strength = 6
        vm.ble.isConnected = true
        vm.ble.isReady = true
        spy.reset()
        vm.start()
        #expect(spy.commands.contains("4\n"), "initial soft = 6-2, cmds=\(spy.commands)")
        #expect(!spy.commands.contains("6\n") || spy.commands.firstIndex(of: "6\n") == nil
            || (spy.commands.firstIndex(of: "4\n") ?? 99) < (spy.commands.firstIndex(of: "6\n") ?? 0))
    }

    @Test("Custom soft-start advances without undercutting target ladder")
    @MainActor func customSoftStartAdvances() {
        let (vm, spy) = makeVM()
        vm.selectMode(.custom)
        vm.strength = 5
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()
        #expect(spy.commands.contains("3\n"))
        spy.reset()
        // Advance ~2s into soft ladder → strength 4
        vm.sessionStartDate = Date().addingTimeInterval(-2)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        let nums = spy.commands.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { (1...9).contains($0) }
        if let maxSent = nums.max() {
            #expect(maxSent >= 3 && maxSent <= 5, "soft ladder cmds=\(spy.commands)")
        }
        #expect(vm.isRunning)
    }

    @Test("Start keeps sticky pending until lead-0 ACK")
    @MainActor func startClearsPendingAfterLeadOffAck() {
        let suiteName = "test.startclear.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        AppPreferences.setPendingDeactivate(true, defaults: d)
        let (vm, spy) = makeVM(defaults: d)
        #expect(vm.pendingDeactivate)
        vm.selectMode(.custom)
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()
        #expect(vm.isRunning)
        #expect(spy.commands.first == "0\n")
        // Durable off stays until lead-0 confirms (process death cannot drop sticky off)
        #expect(vm.pendingDeactivate)
        #expect(AppPreferences.pendingDeactivate(defaults: d) == true)
        spy.completeWrite("0\n", success: true)
        #expect(!vm.pendingDeactivate)
        #expect(AppPreferences.pendingDeactivate(defaults: d) == false)
    }

    @Test("Calm start enqueues absolute off only")
    @MainActor func calmStartAbsoluteOff() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .calm, strength: 5)
        #expect(spy.commands == ["0\n"] || spy.commands.first == "0\n")
        #expect(!vm.stimulationActive)
        spy.completeWrite("0\n", success: true)
        #expect(!vm.pendingDeactivate)
        #expect(vm.modeStatus == "Inhale")
        #expect(!vm.modeStatus.contains("Paused"))
    }

    @Test("resume() mid-focus-rest does not claim stim active")
    @MainActor func resumeRespectsDutyCycleOff() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // Elapsed into off phase
        vm.sessionStartDate = Date().addingTimeInterval(-35)
        vm.pause()
        vm.resume()

        #expect(vm.isRunning)
        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
    }

    @Test("Reconnect while idle sends pending deactivate")
    @MainActor func pendingDeactivateOnReconnect() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        // Expire while "disconnected"
        vm.ble.isConnected = false
        vm.ble.isReady = false
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 10))
        vm.handleForegroundTransition()
        #expect(!vm.isRunning)

        spy.reset()
        // Device comes back
        vm.ble.isConnected = true
        vm.ble.isReady = true
        // Manually trigger ready sink behavior
        vm.flushPendingDeactivateIfNeeded()

        #expect(spy.commands.contains("0\n"))
    }

    @Test("Pause sets pending deactivate for hardware off")
    @MainActor func pauseSetsPendingOff() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        spy.reset()
        vm.pause()
        #expect(vm.isPaused)
        #expect(vm.pendingDeactivate)
        #expect(spy.commands.contains("0\n"))
    }

    @Test("Stop while connected-but-not-ready queues pending deactivate")
    @MainActor func stopWhileConnectingQueuesPendingOff() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.ble.isReady = false
        // still "connected" mid-handshake
        vm.ble.isConnected = true
        spy.reset()

        vm.stop(reason: .user)

        #expect(vm.pendingDeactivate)
        #expect(!spy.commands.contains("0\n"))
    }

    @Test("Custom OFF clears stimulationActive so keepalive stops")
    @MainActor func customOffStopsKeepaliveFlags() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        #expect(vm.stimulationActive)
        vm.sendDebugCommand("0")
        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
    }

    @Test("adjustRemainingTime persists session")
    @MainActor func adjustRemainingPersists() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        let before = vm.defaults.integer(forKey: "session.totalDuration")

        vm.increaseTimer() // +60s while running

        let after = vm.defaults.integer(forKey: "session.totalDuration")
        #expect(after == before + 60)
    }

    @Test("stop records local history and last strength")
    @MainActor func stopRecordsHistory() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .learn, strength: 6)
        vm.stop(reason: .user)

        #expect(!vm.recentSessions.isEmpty)
        #expect(vm.recentSessions.first?.modeRaw == "learn")
        #expect(vm.recentSessions.first?.strength == 6)
        #expect(vm.recentSessions.first?.completed == false)
        #expect(AppPreferences.lastStrength(defaults: vm.defaults) == 6)
    }

    @Test("Natural complete marks history completed")
    @MainActor func completeMarksHistory() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 5))
        vm.handleForegroundTransition()

        #expect(!vm.isRunning)
        #expect(vm.recentSessions.first?.completed == true)
        #expect(vm.recentSessions.first?.modeRaw == "focus")
    }

    @Test("Learn mode starts on left channel like Focus")
    @MainActor func learnStartsLeft() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .learn, strength: 5)
        #expect(vm.activeChannel == .left)
        #expect(vm.stimulationActive)
    }

    @Test("resume requires BLE ready")
    @MainActor func resumeRequiresReady() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.pause()
        vm.ble.isReady = false
        vm.ble.isConnected = true
        #expect(!vm.canResume)
        vm.resume()
        #expect(vm.isPaused)
        #expect(!vm.isRunning)

        vm.ble.isReady = true
        #expect(vm.canResume)
        vm.resume()
        #expect(vm.isRunning)
    }

    @Test("Sleep preset minutes can be selected before start")
    @MainActor func sleepPresetSelection() {
        let (vm, _) = makeVM()
        vm.selectMode(.sleep)
        #expect(vm.timerMinutes == 10)
        vm.timerMinutes = 20
        #expect(vm.timerMinutes == 20)
        #expect(vm.sessionDurationSeconds == 1200)
        vm.timerMinutes = 30
        #expect(vm.sessionDurationSeconds == 1800)
    }

    @Test("pendingDeactivate survives process via UserDefaults")
    @MainActor func pendingDeactivatePersists() {
        let suiteName = "test.pending.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let (vm, _) = makeVM(defaults: d)
        simulateRunning(vm, mode: .stressRelief)
        vm.ble.isReady = false
        vm.ble.isConnected = true
        vm.stop(reason: .user)
        #expect(vm.pendingDeactivate)
        #expect(AppPreferences.pendingDeactivate(defaults: d))

        // "Relaunch"
        let (vm2, spy) = makeVM(defaults: d)
        #expect(vm2.pendingDeactivate)
        vm2.ble.isConnected = true
        vm2.ble.isReady = true
        vm2.flushPendingDeactivateIfNeeded()
        #expect(spy.commands.contains("0\n"))
        // Durable flag stays true until lead-0 ACK on Start
        #expect(vm2.pendingDeactivate)
        vm2.selectMode(.stressRelief)
        vm2.start()
        #expect(vm2.pendingDeactivate, "still sticky until off ACK")
        spy.completeWrite("0\n", success: true)
        #expect(!vm2.pendingDeactivate)
    }

    @Test("Custom channel survives process relaunch")
    @MainActor func customChannelSurvivesRelaunch() {
        let suiteName = "test.chpersist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let (vm, _) = makeVM(defaults: d)
        simulateRunning(vm, mode: .custom, strength: 5)
        vm.sendDebugCommand("C")
        #expect(vm.customChannelCommand == "C")
        #expect(AppPreferences.customChannel(defaults: d) == "C")

        let (vm2, _) = makeVM(defaults: d)
        #expect(vm2.customChannelCommand == "C")
    }

    @Test("setStrength persists last strength even when idle")
    @MainActor func setStrengthPersistsIdle() {
        let suiteName = "test.strpersist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let (vm, _) = makeVM(defaults: d)
        vm.setStrength(8)
        #expect(AppPreferences.lastStrength(defaults: d) == 8)
    }

    @Test("Natural complete sets celebration banner")
    @MainActor func completeSetsBanner() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .calm, strength: 5)
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 5))
        vm.handleForegroundTransition()
        #expect(!vm.isRunning)
        #expect(vm.completionBanner?.contains("complete") == true)
        vm.clearCompletionBanner()
        #expect(vm.completionBanner == nil)
    }

    @Test("Failed deactivate write re-arms pending off")
    @MainActor func writeFailRearmsPending() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.stop(reason: .user)
        // After stop with ready, pending is true (sticky)
        #expect(vm.pendingDeactivate)
        mock.completeWrite(BLEConstants.deactivateCommand, success: false)
        #expect(vm.pendingDeactivate)
    }

    @Test("Mid-session off fail while ready reasserts program")
    @MainActor func midSessionOffFailReasserts() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        mock.reset()
        // Duty-cycle off fails while still running and ready
        mock.completeWrite(BLEConstants.deactivateCommand, success: false)
        #expect(vm.isRunning)
        // Absolute reprogram should re-enqueue channel/strength (and often leading 0)
        #expect(!mock.commands.isEmpty, "Must reassert device program after mid-session off fail")
        #expect(
            mock.commands.contains("D\n") || mock.commands.contains("5\n") || mock.commands.contains("0\n")
        )
    }

    @Test("Mid-session off fail offline reprograms on becomeReady")
    @MainActor func midSessionOffFailThenReady() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        mock.isReady = false
        mock.isConnected = false
        mock.reset()
        mock.completeWrite(BLEConstants.deactivateCommand, success: false)
        #expect(vm.isRunning)
        #expect(mock.commands.isEmpty, "No program while link down")
        mock.becomeReady()
        // Ready sink → resumeSessionOnDevice
        #expect(!mock.commands.isEmpty, "ready must reprogram, cmds=\(mock.commands)")
        #expect(
            mock.commands.contains("A\n")
                || mock.commands.contains("0\n")
                || mock.commands.contains("5\n")
                || mock.commands.contains("D\n")
                || mock.commands.contains("3\n"),
            "cmds=\(mock.commands)"
        )
    }

    @Test("Successful deactivate write clears pending when idle")
    @MainActor func writeSuccessClearsPendingWhenIdle() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.stop(reason: .user)
        #expect(vm.pendingDeactivate)
        #expect(!vm.isRunning)
        let tokenBefore = vm.deviceOffConfirmedToken
        mock.completeWrite(BLEConstants.deactivateCommand)
        #expect(!vm.pendingDeactivate)
        #expect(vm.deviceOffConfirmedToken == tokenBefore + 1, "Off ACK bumps confirmed token for haptic")
    }

    @Test("Start without sticky pending: lead-0 ACK does not bump off-confirmed token")
    @MainActor func startLeadOffWithoutStickyNoToken() {
        let (vm, spy) = makeVM()
        #expect(!vm.pendingDeactivate)
        let tokenBefore = vm.deviceOffConfirmedToken
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(vm.isRunning)
        // No sticky pending — ACK of lead-0 is session program, not idle off confirm haptic
        spy.completeWrite("0\n", success: true)
        #expect(vm.deviceOffConfirmedToken == tokenBefore, "fresh Start lead-0 must not fire off haptic")
    }

    @Test("Start with sticky pending: lead-0 ACK clears durable off")
    @MainActor func startLeadOffClearsStickyPending() {
        let suiteName = "test.offtoken.sticky.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        AppPreferences.setPendingDeactivate(true, defaults: d)
        let (vm, spy) = makeVM(defaults: d)
        #expect(vm.pendingDeactivate)
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(vm.pendingDeactivate, "optimistic clear removed — still sticky")
        spy.completeWrite("0\n", success: true)
        #expect(!vm.pendingDeactivate)
    }

    @Test("Off ACK while paused clears pending (LA can stop saying stopping)")
    @MainActor func writeSuccessClearsPendingWhenPaused() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.pause()
        #expect(vm.isPaused)
        #expect(vm.pendingDeactivate)
        mock.completeWrite(BLEConstants.deactivateCommand)
        #expect(!vm.pendingDeactivate)
        // Use real VM modeStatus (may still hold last phase) — presentation must force Paused
        let status = LiveActivityPresentation.statusLine(
            isPaused: vm.isPaused,
            isRunning: vm.isRunning,
            pendingDeviceOff: vm.pendingDeactivate,
            modeStatus: vm.modeStatus,
            modeName: vm.selectedMode.name,
            isLinkReady: vm.ble.isReady
        )
        #expect(status == "Paused")
        #expect(!status.contains("stopping"))
    }

    @Test("Pause clears idle timer lock so screen can sleep")
    @MainActor func pauseReleasesIdleTimer() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .sleep)
        #expect(UIApplication.shared.isIdleTimerDisabled)
        vm.pause()
        #expect(!UIApplication.shared.isIdleTimerDisabled)
        vm.ble.isReady = true
        vm.resume()
        #expect(UIApplication.shared.isIdleTimerDisabled)
    }

    @Test("Off ACK does not clear pending while program writes still outstanding")
    @MainActor func programWritesBlockPendingClear() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.stop(reason: .user)
        #expect(vm.pendingDeactivate)
        mock.setPendingProgramWrites(true)
        mock.completeWrite(BLEConstants.deactivateCommand)
        #expect(vm.pendingDeactivate, "Status/program still outstanding → keep sticky off")
        mock.setPendingProgramWrites(false)
        mock.completeWrite(BLEConstants.deactivateCommand)
        #expect(!vm.pendingDeactivate)
    }

    @Test("Start cancels program writes on mock transport")
    @MainActor func startCancelsProgramWrites() {
        let (vm, mock) = makeVM()
        mock.becomeReady()
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(mock.cancelProgramWritesCount >= 1)
        #expect(mock.commands.first == "0\n" || mock.commands.contains("0\n"))
    }

    @Test("flush while ready enqueues another off when still pending")
    @MainActor func flushRetriesWhilePending() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief)
        vm.stop(reason: .user)
        #expect(vm.pendingDeactivate)
        spy.reset()
        vm.ble.isReady = true
        vm.flushPendingDeactivateIfNeeded()
        #expect(spy.commands.contains("0\n"))
        // Still pending until success callback
        #expect(vm.pendingDeactivate)
        spy.reset()
        vm.flushPendingDeactivateIfNeeded()
        #expect(spy.commands.contains("0\n"))
    }

    @Test("Timer cannot exceed max session minutes when idle")
    @MainActor func timerRespectsMaxMinutes() {
        let (vm, _) = makeVM()
        vm.timerMinutes = BLEConstants.maxSessionMinutes
        vm.increaseTimer()
        #expect(vm.timerMinutes == BLEConstants.maxSessionMinutes)
    }

    @Test("Mid-session extend is capped at max duration")
    @MainActor func midSessionExtendCapped() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        // Force near-max remaining
        vm.sessionStartDate = Date()
        // inflate total via repeated +60 until cap
        for _ in 0..<100 {
            vm.increaseTimer()
        }
        #expect(vm.sessionDurationSeconds <= BLEConstants.maxSessionMinutes * 60)
    }

    @Test("selectMode keeps last strength when available")
    @MainActor func selectModeKeepsLastStrength() {
        let suiteName = "test.lastmode.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        AppPreferences.saveLastStrength(7, defaults: d)
        let (vm, _) = makeVM(defaults: d)
        #expect(vm.strength == 7)
        vm.selectMode(.sleep)
        #expect(vm.strength == 7) // not wiped to sleep default 5
        vm.selectMode(.headache)
        #expect(vm.strength == 7) // not forced to headache 7 only by coincidence
    }

    @Test("Custom channel reconnect restores left after pause")
    @MainActor func customChannelReconnectLeft() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        #expect(vm.selectedMode == .custom)
        #expect(vm.ble.isReady)
        vm.sendDebugCommand("A")
        #expect(vm.customChannelCommand == "A")
        #expect(vm.activeChannel == .left)
        #expect(vm.stimulationActive)

        vm.pause()
        #expect(vm.isPaused)
        #expect(vm.customChannelCommand == "A") // OFF not stored as channel preference

        spy.reset()
        vm.resume()
        #expect(vm.isRunning)
        #expect(vm.customChannelCommand == "A")
        #expect(vm.stimulationActive)
        #expect(vm.activeChannel == .left)
        #expect(spy.commands.contains("A\n"))
    }

    @Test("Paused restore queues pending deactivate")
    @MainActor func pausedRestoreQueuesOff() {
        let suiteName = "test.pausedoff.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(Date().timeIntervalSince1970, forKey: "session.pauseStartDate")
        d.set(true, forKey: "session.isPaused")
        d.set("focus", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.isPaused)
        #expect(vm.pendingDeactivate)
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

    @Test("Short FG return while linked does not send lead-0 (no stim blip)")
    @MainActor func shortForegroundDoesNotBlipDevice() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        spy.reset()
        vm.handleBackgroundTransition()
        // Immediate return — device was still running in background
        vm.handleForegroundTransition()
        #expect(vm.isRunning)
        #expect(
            !spy.commands.contains("0\n"),
            "short app-switch must not force off+reprogram, cmds=\(spy.commands)"
        )
    }

    @Test("Long FG return while linked reasserts with lead-0")
    @MainActor func longForegroundReassertsDevice() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.handleBackgroundTransition()
        // Backdate background entry past absolute reassert gap
        vm.backgroundEntryDate = Date().addingTimeInterval(-20)
        spy.reset()
        vm.handleForegroundTransition()
        #expect(vm.isRunning)
        #expect(
            spy.commands.contains("0\n"),
            "long BG needs absolute reassert, cmds=\(spy.commands)"
        )
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
        // Offline restore never claims stim until BLE is ready
        #expect(!vm.stimulationActive)
    }

    @Test("Sleep restore mid-fade keeps comfort floor and phase anchor")
    @MainActor func sleepRestoreMidFadeAnchors() {
        let suiteName = "test.restore.sleepfade.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        // 540s into 600s sleep, extended total 660; faded to 3; phaseLen 120
        let startDate = Date().addingTimeInterval(-540)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(660, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("sleep", forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        d.set(120, forKey: "session.phaseLengthSeconds")
        d.set(3, forKey: "session.lastComfortStrength")

        let (vm, spy) = makeVM(defaults: d)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .sleep)
        #expect(vm.defaults.integer(forKey: "session.lastComfortStrength") == 3)
        #expect(vm.defaults.integer(forKey: "session.phaseLengthSeconds") == 120)

        // Ready path reprograms — must not re-raise above fade floor
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        }
        let strengths = spy.commands.compactMap { cmd -> Int? in
            Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        #expect(strengths.allSatisfy { $0 <= 3 },
                "Restore reconnect must hold fade floor, cmds=\(spy.commands)")
    }

    @Test("setStrength mid-session persists strength and pin keys")
    @MainActor func setStrengthPersistsSessionStrengthAndPin() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .sleep, strength: 5)
        // Drive into deep fade so noteUserStrength pins
        vm.sessionStartDate = Date().addingTimeInterval(-540)
        vm.handleForegroundTransition()
        // Process ticks to settle fadeFloor
        for _ in 0..<5 {
            vm.sessionStartDate = Date().addingTimeInterval(-540)
            vm.handleForegroundTransition()
        }
        vm.setStrength(7)
        #expect(vm.strength == 7)
        #expect(vm.defaults.integer(forKey: "session.strength") == 7,
                "Kill must restore raised base")
        // After deep fade settle + raise, pin must stick for kill restore
        let pin = vm.defaults.integer(forKey: "session.userStrengthFloor")
        #expect(pin == 7, "user pin must be durable after mid-fade raise, pin=\(pin)")
    }

    @Test("Sleep restore with user pin holds raised intensity")
    @MainActor func sleepRestoreUserPinHolds() {
        let suiteName = "test.restore.sleeppin.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-540)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("sleep", forKey: "session.mode")
        d.set(7, forKey: "session.strength")
        d.set(120, forKey: "session.phaseLengthSeconds")
        d.set(7, forKey: "session.lastComfortStrength")
        d.set(7, forKey: "session.userStrengthFloor")

        let (vm, spy) = makeVM(defaults: d)
        #expect(vm.isRunning)
        #expect(vm.strength == 7)
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        }
        let strengths = spy.commands.compactMap { cmd -> Int? in
            Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        #expect(strengths.allSatisfy { $0 >= 7 || $0 == 0 },
                "User pin restore must not undercut 7, cmds=\(spy.commands)")
        // Strength commands (exclude channel letters) should include pin
        let numeric = strengths.filter { $0 >= 1 && $0 <= 9 }
        #expect(!numeric.isEmpty, "ready restore must reprogram strength, cmds=\(spy.commands)")
        #expect(numeric.contains { $0 >= 7 }, "pin 7 must appear, cmds=\(spy.commands)")
        #expect(numeric.allSatisfy { $0 >= 7 }, "must not undercut pin, cmds=\(spy.commands)")
    }

    @Test("User adjust remaining bumps token; wall clock does not")
    @MainActor func userAdjustTokenNotWallClock() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        let before = vm.userAdjustedRemainingToken
        // Wall-clock recalculate path (background notify style)
        vm.sessionStartDate = Date().addingTimeInterval(-5)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        #expect(vm.userAdjustedRemainingToken == before)
        vm.increaseTimer()
        #expect(vm.userAdjustedRemainingToken == before + 1)
    }

    @Test("Decrease at floor does not extend remaining")
    @MainActor func decreaseAtFloorNoExtend() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        // Force remaining under floor
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.sessionDurationSeconds - 45))
        // Recalculate via background wake
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        let remaining = vm.remainingSeconds
        #expect(remaining <= 60)
        vm.decreaseTimer()
        #expect(vm.remainingSeconds == remaining, "Minus must not bump up to 60")
    }

    @Test("Pause then resume Focus soft-starts not full blast")
    @MainActor func pauseResumeFocusSoft() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // Mid on-window
        vm.sessionStartDate = Date().addingTimeInterval(-10)
        vm.handleForegroundTransition() // ensure ticks
        spy.reset()
        vm.pause()
        spy.reset()
        vm.resume()
        #expect(vm.isRunning)
        // Soft initial after pause, not full 5 jump
        #expect(spy.commands.contains("A\n") || spy.commands.contains("0\n"))
        let strengths = spy.commands.filter { $0 == "3\n" || $0 == "4\n" || $0 == "5\n" }
        #expect(strengths.contains("3\n") || strengths.first == "3\n" || spy.commands.contains("3\n"),
                "Expected soft initial, cmds=\(spy.commands)")
        #expect(vm.effectiveStrength == nil || (vm.effectiveStrength ?? 9) <= 5)
    }

    @Test("sessionStatusText matches LA honesty when paused offline")
    @MainActor func sessionStatusPausedOffline() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.pause()
        // Clear pending-off so status is offline honesty, not stopping
        if vm.pendingDeactivate {
            spy.completeWrite("0\n", success: true)
        }
        vm.ble.isReady = false
        vm.ble.isConnected = false
        #expect(vm.sessionStatusText == "Paused · waiting for device")
    }

    @Test("sessionStatusText shows stopping when pending off while paused")
    @MainActor func sessionStatusPausedPendingOff() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.pause()
        #expect(vm.pendingDeactivate, "pause must arm durable HW off")
        #expect(vm.sessionStatusText.contains("stopping"),
                "status=\(vm.sessionStatusText)")
    }

    @Test("Custom pause resume soft-starts intensity")
    @MainActor func customPauseResumeSoft() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        // Past any soft window
        vm.sessionStartDate = Date().addingTimeInterval(-30)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        spy.reset()
        vm.pause()
        spy.reset()
        vm.resume()
        #expect(vm.isRunning)
        #expect(spy.commands.contains("0\n"), "absolute lead-0, cmds=\(spy.commands)")
        #expect(spy.commands.contains("3\n"), "custom soft after pause, cmds=\(spy.commands)")
        #expect(vm.modeStatus.contains("Easing"), "status=\(vm.modeStatus)")
        #expect(vm.effectiveStrength == 3)
        #expect(!vm.sessionStatusText.localizedCaseInsensitiveContains("Paused"))
    }

    @Test("Custom first-start mid-soft setStrength does not undercut")
    @MainActor func customFirstStartMidSoftSetStrength() {
        let (vm, spy) = makeVM()
        vm.selectMode(.custom)
        vm.strength = 5
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()
        #expect(spy.commands.contains("3\n"))
        spy.reset()
        vm.setStrength(7)
        #expect(spy.commands.contains("7\n"))
        // Soft window closed — further ticks must not send below 7
        vm.sessionStartDate = Date().addingTimeInterval(-4)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        for cmd in spy.commands {
            if let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)),
               (1...9).contains(n) {
                #expect(n >= 7, "Must not undercut raise, cmds=\(spy.commands)")
            }
        }
    }

    @Test("Custom raise mid soft durable-clears soft begin (kill cannot undercut)")
    @MainActor func customRaiseMidSoftClearsDurableSoftBegin() {
        let suite = "test.custom.soft.raise.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let (vm, spy) = makeVM(defaults: d)
        vm.selectMode(.custom)
        vm.strength = 5
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()
        #expect(d.object(forKey: "session.customSoftBeginElapsed") != nil)
        spy.reset()
        vm.setStrength(7)
        // Durable clear without needing BG persist
        #expect(d.object(forKey: "session.customSoftBeginElapsed") == nil)
        // New VM must not rehydrate soft under 7
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        // Keep session keys but soft begin gone; strength 7 should be in prefs via setStrength
        d.set(vm.selectedMode.rawValue, forKey: "session.mode")
        // Simulate running restore with strength 7 and no soft begin
        let startDate = Date().addingTimeInterval(-2)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        d.set(7, forKey: "session.strength")
        let vm2 = SessionViewModel(defaults: d, ble: mock)
        if vm2.isRunning {
            mock.reset()
            mock.isReady = false
            mock.isReady = true
            for cmd in mock.commands {
                if let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)),
                   (1...9).contains(n) {
                    #expect(n >= 7, "raise must stick after kill, cmds=\(mock.commands)")
                }
            }
        }
    }

    @Test("Session end alerts toggle persists and cancels when off")
    @MainActor func sessionEndAlertsToggle() {
        let suite = "test.alerts.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let (vm, _) = makeVM(defaults: d)
        #expect(!vm.sessionEndAlertsEnabled)
        vm.setSessionEndAlertsEnabled(true)
        #expect(vm.sessionEndAlertsEnabled)
        #expect(AppPreferences.sessionEndAlertsEnabled(defaults: d))
        vm.setSessionEndAlertsEnabled(false)
        #expect(!vm.sessionEndAlertsEnabled)
    }

    @Test("Engine soft snapshot is written during ease-in and cleared after settle")
    @MainActor func engineSoftSnapshotPersistsWhileEasing() {
        let suite = "test.softsnap.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let (vm, spy) = makeVM(defaults: d)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(vm.isRunning)
        // Soft start at 5 always begins with initial step (typically 3)
        #expect(
            spy.commands.contains("3\n")
                || vm.effectiveStrength == 3
                || vm.modeStatus.localizedCaseInsensitiveContains("Eas")
                || d.data(forKey: "session.softSnapshot") != nil,
            "start should open soft window, cmds=\(spy.commands) status=\(vm.modeStatus)"
        )
        // BG persist while still near t=0 (soft open)
        vm.sessionStartDate = Date().addingTimeInterval(-1)
        vm.handleBackgroundTransition()
        #expect(
            d.data(forKey: "session.softSnapshot") != nil,
            "easing session must write softSnapshot for kill restore"
        )
        if let data = d.data(forKey: "session.softSnapshot"),
           let snap = try? JSONDecoder().decode(SoftStartSnapshot.self, from: data) {
            #expect(snap.enabled == true, "open soft window, snap=\(snap)")
            #expect(snap.lastSent >= SoftStart.initialStrength(target: 5))
        }
        // Advance past soft window (~ SoftStart settle for target 5)
        vm.sessionStartDate = Date().addingTimeInterval(-30)
        vm.handleForegroundTransition()
        // Drive ticks after settle
        for _ in 0..<5 {
            vm.ble.onNotification?()
        }
        if let data = d.data(forKey: "session.softSnapshot"),
           let snap = try? JSONDecoder().decode(SoftStartSnapshot.self, from: data) {
            #expect(!snap.enabled || snap.userTakenOver,
                    "settled soft should not leave open ease snap, snap=\(snap)")
        }
        // Cleared entirely is also correct after settle without takeover
    }

    @Test("Offline mid-soft raise persists soft takeover snapshot")
    @MainActor func offlineMidSoftRaisePersistsTakeover() {
        let suite = "test.soft.offline.raise.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let (vm, spy) = makeVM(defaults: d)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(vm.isRunning)
        // Drop link so setStrength early-returns after model update
        vm.ble.isReady = false
        vm.ble.isConnected = false
        spy.reset()
        vm.setStrength(7)
        #expect(vm.strength == 7)
        #expect(d.integer(forKey: "session.strength") == 7)
        // Durable soft snap must reflect takeover (no soft undercut after kill)
        let data = d.data(forKey: "session.softSnapshot")
        #expect(data != nil, "offline raise must persist softSnapshot")
        let snap = try! JSONDecoder().decode(SoftStartSnapshot.self, from: data!)
        #expect(snap.userTakenOver == true, "takeover flag, snap=\(snap)")
        #expect(snap.lastSent == 7, "floor lastSent, snap=\(snap)")
        #expect(snap.enabled == false, "ease stopped after user raise")
    }

    @Test("Offline mid-soft raise survives kill restore without undercut")
    @MainActor func offlineMidSoftRaiseSurvivesKillRestore() {
        let suite = "test.soft.offline.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let (vm1, _) = makeVM(defaults: d)
        simulateRunning(vm1, mode: .stressRelief, strength: 5)
        vm1.ble.isReady = false
        vm1.ble.isConnected = false
        vm1.setStrength(7)
        vm1.handleBackgroundTransition()

        // Process kill → cold restore with ready link
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm2 = SessionViewModel(defaults: d, ble: mock)
        #expect(vm2.isRunning || vm2.isPaused)
        #expect(vm2.strength == 7)
        // Reconnect strength numbers must not undercut raised floor
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "ready kill restore must reprogram, cmds=\(mock.commands)")
        #expect(nums.contains(7), "raised floor must appear, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 >= 7 },
                "kill restore must not undercut 7, cmds=\(mock.commands)")
    }

    @Test("Offline mid-soft lower survives kill restore at lowered floor")
    @MainActor func offlineMidSoftLowerSurvivesKillRestore() {
        let suite = "test.soft.offline.lower.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let (vm1, _) = makeVM(defaults: d)
        simulateRunning(vm1, mode: .stressRelief, strength: 7)
        vm1.ble.isReady = false
        vm1.ble.isConnected = false
        vm1.setStrength(3)
        #expect(vm1.strength == 3)
        if let data = d.data(forKey: "session.softSnapshot"),
           let snap = try? JSONDecoder().decode(SoftStartSnapshot.self, from: data) {
            #expect(snap.userTakenOver == true)
            #expect(snap.lastSent == 3)
        }
        vm1.handleBackgroundTransition()

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm2 = SessionViewModel(defaults: d, ble: mock)
        #expect(vm2.strength == 3)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "cmds=\(mock.commands)")
        // Must not thrash back up the soft ladder toward old 7
        #expect(nums.allSatisfy { $0 <= 3 },
                "lower floor must not re-step up, cmds=\(mock.commands)")
        #expect(nums.contains(3), "cmds=\(mock.commands)")
    }

    @Test("Sleep soft snapshot seeds kill restore ladder")
    @MainActor func sleepSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.sleep.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.sleep.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .sleep)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "sleep soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Stress mid-soft ready reconnect continues ladder")
    @MainActor func stressMidSoftReadyReconnectLadder() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(spy.commands.contains("3\n") || vm.modeStatus.localizedCaseInsensitiveContains("Eas"))
        // Drop + reassert ready mid soft (not process kill)
        vm.ble.isReady = false
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        } else {
            vm.ble.isConnected = true
            vm.ble.isReady = true
        }
        let nums = spy.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "ready reconnect cmds=\(spy.commands)")
        // Soft still open near t=0 — ladder includes step below full base
        #expect(nums.contains(where: { $0 < 5 }), "mid-soft ready ladder, cmds=\(spy.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(spy.commands)")
    }

    @Test("Sleep mid-soft ready reconnect continues ladder")
    @MainActor func sleepMidSoftReadyReconnectLadder() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .sleep, strength: 5)
        vm.ble.isReady = false
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        } else {
            vm.ble.isConnected = true
            vm.ble.isReady = true
        }
        let nums = spy.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "sleep ready reconnect cmds=\(spy.commands)")
        #expect(nums.contains(where: { $0 < 5 }), "sleep mid-soft ready ladder, cmds=\(spy.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(spy.commands)")
    }

    @Test("Pain soft snapshot seeds kill restore ladder")
    @MainActor func painSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.pain.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(360, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.painRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .painRelief)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "pain soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Ease burst soft snapshot seeds kill restore ladder")
    @MainActor func easeBurstSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.ease.burst.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(360, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.painRelief.rawValue, forKey: "session.mode")
        d.set(EasePattern.burst.rawValue, forKey: "session.easePattern")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .painRelief)
        #expect(vm.easePattern == .burst)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "burst soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Headache burst re-on soft snapshot kill restore ladder")
    @MainActor func headacheBurstReOnSoftKillRestoreLadder() throws {
        let suite = "test.headache.reon.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // Mid duty re-on soft at cycle wrap (beginElapsed=150).
        // Freeze the clock. A slow init must not finish the 4s ladder.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let frozen = start.addingTimeInterval(151)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.painRelief.rawValue, forKey: "session.mode")
        d.set(EasePattern.burst.rawValue, forKey: "session.easePattern")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 150
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock, now: { frozen })
        #expect(vm.isRunning)
        #expect(vm.easePattern == .burst)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "burst re-on soft cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "re-on soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Legacy nausea soft snapshot normalizes to Stress ladder")
    @MainActor func legacyNauseaSoftKillRestoreLadder() throws {
        let suite = "test.nausea.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(360, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("nausea", forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .stressRelief, "nausea merges to Stress")
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "nausea→stress soft cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Pain mid-soft ready reconnect continues ladder")
    @MainActor func painMidSoftReadyReconnectLadder() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .painRelief, strength: 5)
        vm.ble.isReady = false
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        } else {
            vm.ble.isConnected = true
            vm.ble.isReady = true
        }
        let nums = spy.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "pain ready reconnect cmds=\(spy.commands)")
        #expect(nums.contains(where: { $0 < 5 }), "pain mid-soft ready ladder, cmds=\(spy.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(spy.commands)")
    }

    @Test("Focus mid-soft ready reconnect continues ladder")
    @MainActor func focusMidSoftReadyReconnectLadder() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .focus, strength: 5)
        // Stay in first on-window soft
        vm.sessionStartDate = Date().addingTimeInterval(-2)
        vm.ble.isReady = false
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        } else {
            vm.ble.isConnected = true
            vm.ble.isReady = true
        }
        let nums = spy.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "focus ready reconnect cmds=\(spy.commands)")
        #expect(nums.contains(where: { $0 < 5 }), "focus mid-soft ready ladder, cmds=\(spy.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(spy.commands)")
    }

    @Test("Focus duty re-on mid-soft ready reconnect continues ladder")
    @MainActor func focusDutyReOnMidSoftReadyReconnectLadder() throws {
        // Seed mid duty re-on soft (beginElapsed=60) then ready drop/reassert.
        // Freeze the clock. A slow init must not finish the 4s ladder.
        let suite = "test.focus.reon.ready.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let frozen = start.addingTimeInterval(61)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.focus.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 60
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock, now: { frozen })
        #expect(vm.isRunning)
        mock.reset()
        mock.isReady = false
        mock.becomeReady()
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "focus duty re-on ready cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 < 5 }), "duty re-on soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Ease burst mid-soft ready reconnect continues ladder")
    @MainActor func easeBurstMidSoftReadyReconnectLadder() {
        let (vm, spy) = makeVM()
        vm.selectMode(.painRelief)
        vm.easePattern = .burst
        vm.strength = 5
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()
        vm.ble.isReady = false
        spy.reset()
        if let mock = vm.ble as? MockDeviceTransport {
            mock.becomeReady()
        } else {
            vm.ble.isConnected = true
            vm.ble.isReady = true
        }
        let nums = spy.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "burst ready reconnect cmds=\(spy.commands)")
        #expect(nums.contains(where: { $0 < 5 }), "burst mid-soft ready ladder, cmds=\(spy.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(spy.commands)")
    }

    @Test("Ease burst re-on mid-soft ready reconnect continues ladder")
    @MainActor func easeBurstReOnMidSoftReadyReconnectLadder() throws {
        // Seed mid cycle re-on soft (beginElapsed=150) then ready drop/reassert.
        // Freeze the clock one second into the window. A slow init must not send full strength.
        let suite = "test.burst.reon.ready.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let frozen = start.addingTimeInterval(151)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.painRelief.rawValue, forKey: "session.mode")
        d.set(EasePattern.burst.rawValue, forKey: "session.easePattern")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 150
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock, now: { frozen })
        #expect(vm.isRunning)
        #expect(vm.easePattern == .burst)
        mock.reset()
        mock.isReady = false
        mock.becomeReady()
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "burst re-on ready cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 < 5 }), "burst re-on soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Stress soft snapshot seeds kill restore ladder")
    @MainActor func stressSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.stress.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(360, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.stressRelief.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .stressRelief)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "stress soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Focus first soft snapshot seeds kill restore ladder")
    @MainActor func focusFirstSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.focus.first.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.focus.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .focus)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "focus first soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Focus duty soft snapshot seeds kill restore ladder")
    @MainActor func focusDutySoftSnapshotKillRestoreLadder() throws {
        let suite = "test.focus.duty.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // Seed a running Focus session mid duty re-on soft (beginElapsed=60).
        // Freeze the clock. A slow init must not finish the 4s ladder.
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let frozen = start.addingTimeInterval(61)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.focus.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 60
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock, now: { frozen })
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .focus)
        let cmds = mock.commands
        #expect(!cmds.isEmpty, "restore should reprogram, cmds=\(cmds)")
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "duty soft restore needs strength cmds, cmds=\(cmds)")
        // Soft ladder mid duty re-on: expect 3/4 present, not only full 5 spike
        #expect(
            nums.contains(where: { $0 <= 4 }),
            "duty soft kill restore ladder, cmds=\(cmds)"
        )
        #expect(
            nums.allSatisfy { $0 >= SoftStart.initialStrength(target: 5) },
            "cmds=\(cmds)"
        )
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(cmds)")
    }

    @Test("Live Activity start pause complete via inject seam")
    @MainActor func liveActivityInjectLifecycle() {
        let la = RecordingLiveActivity()
        let (vm, _) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(la.startCount >= 1, "start pushes Live Activity")
        let updatesBeforePause = la.updateCount
        vm.pause()
        #expect(vm.isPaused)
        #expect(la.updateCount > updatesBeforePause, "pause must push LA update")
        #expect(la.lastIsPaused == true)
        #expect(
            la.lastStatusText.localizedCaseInsensitiveContains("paus")
                || la.lastStatusText.localizedCaseInsensitiveContains("stop"),
            "LA status honesty, status=\(la.lastStatusText)"
        )
        #expect(la.lastPendingDeviceOff == true, "pause arms HW off — LA must show pending")
        let endsBefore = la.endCount
        vm.stop(reason: .completed)
        #expect(la.endCount > endsBefore)
        #expect(la.lastEndReason == .completed)
        #expect(la.lastEndModeName?.isEmpty == false)
        #expect(la.lastEndPendingDeviceOff == true, "complete while pending off claims turning off")
    }

    @Test("User stop ends Live Activity with user reason")
    @MainActor func liveActivityUserStop() {
        let la = RecordingLiveActivity()
        let (vm, _) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.stop(reason: .user)
        #expect(la.endCount >= 1)
        #expect(la.lastEndReason == .user)
    }

    @Test("Completed LA after pause off-ACK does not claim turning device off")
    @MainActor func completedLAHonestWhenOffAlreadyACKed() {
        let la = RecordingLiveActivity()
        let (vm, spy) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.pause()
        #expect(vm.pendingDeactivate)
        // Off ACK while paused clears pending
        spy.completeWrite(BLEConstants.deactivateCommand, success: true)
        #expect(!vm.pendingDeactivate)
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 30))
        // Wall complete from paused + off already done
        vm.stop(reason: .completed)
        #expect(la.lastEndReason == .completed)
        #expect(
            la.lastEndPendingDeviceOff == false,
            "off already ACKed — do not lie about turning device off"
        )
    }

    @Test("Completed LA from running claims turning device off")
    @MainActor func completedLAFromRunningClaimsPendingOff() {
        let la = RecordingLiveActivity()
        let (vm, _) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.stop(reason: .completed)
        #expect(la.lastEndReason == .completed)
        #expect(la.lastEndPendingDeviceOff == true, "running complete needs HW off")
    }

    @Test("Off ACK after complete clears LA turning-off claim")
    @MainActor func offACKAfterCompleteClearsLAPending() {
        let la = RecordingLiveActivity()
        let (vm, spy) = makeVM(liveActivity: la)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.stop(reason: .completed)
        #expect(la.lastEndPendingDeviceOff == true)
        #expect(vm.pendingDeactivate)
        spy.completeWrite(BLEConstants.deactivateCommand, success: true)
        #expect(!vm.pendingDeactivate)
        #expect(la.hardwareOffConfirmedCount >= 1)
        #expect(la.lastEndPendingDeviceOff == false, "linger must not keep lying")
    }

    @Test("Stale cached battery blocks Start until sample confirmed or grace")
    @MainActor func staleCachedBatteryBlocksStartDuringGrace() {
        let (vm, mock) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_800_000_600)
        vm.now = { t0 }
        mock.isConnected = true
        // Stale high % after disconnect — not yet confirmed on new link
        mock.batteryPercentage = 80
        mock.batterySampleConfirmed = false
        mock.isCharging = false
        mock.becomeReady(confirmBattery: false)
        #expect(!vm.canStart, "unconfirmed cache within grace")
        #expect(vm.startBlockedReason == BatteryPresentation.startBlockedReadingCopy)
        // Fresh Q
        mock.batterySampleConfirmed = true
        #expect(vm.canStart)
    }

    @Test("Confirmed empty pack mid-session auto-pauses")
    @MainActor func emptyBatteryMidSessionAutoPauses() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(vm.isRunning)
        mock.batteryPercentage = 0
        mock.batterySampleConfirmed = true
        mock.isCharging = false
        vm.considerEmptyBatteryPause()
        #expect(vm.isPaused)
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate, "empty pack pause arms HW off")
    }

    @Test("Unconfirmed empty does not auto-pause mid-session")
    @MainActor func unconfirmedEmptyDoesNotAutoPause() {
        let (vm, mock) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        // Unconfirm first so combineLatest/sink cannot pause on confirmed empty
        mock.batterySampleConfirmed = false
        mock.isCharging = false
        mock.batteryPercentage = 0
        vm.considerEmptyBatteryPause()
        #expect(vm.isRunning, "stale empty must not pause until confirmed")
    }

    @Test("Cold launch hydrates denied and BG does not schedule")
    @MainActor func coldLaunchDeniedHydratesBeforeBG() {
        let suite = "test.alerts.cold.denied.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        AppPreferences.setSessionEndAlertsEnabled(true, defaults: d)
        let notifier = RecordingSessionEndNotifier()
        notifier.canDeliver = false
        notifier.authGranted = false
        let (vm, _) = makeVM(defaults: d, endNotifier: notifier)
        #expect(vm.sessionEndAlertsEnabled)
        #expect(vm.sessionEndAlertsDenied, "init must hydrate denied from system status")
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let before = notifier.scheduleCount
        vm.handleBackgroundTransition()
        #expect(notifier.scheduleCount == before, "denied cold launch must not schedule")
    }

    @Test("Background arms end alert; pause and foreground cancel")
    @MainActor func sessionEndAlertLifecycleViaNotifier() {
        let suite = "test.alerts.lifecycle.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let notifier = RecordingSessionEndNotifier()
        let (vm, _) = makeVM(defaults: d, endNotifier: notifier)
        vm.setSessionEndAlertsEnabled(true)
        #expect(!vm.sessionEndAlertsDenied)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let cancelAfterStart = notifier.cancelCount
        vm.handleBackgroundTransition()
        #expect(notifier.scheduleCount >= 1, "BG should schedule end alert")
        #expect(notifier.lastSchedule != nil)
        let scheduleAfterBG = notifier.scheduleCount
        vm.pause()
        #expect(notifier.cancelCount > cancelAfterStart, "pause cancels end alert")
        // Resume + BG again, then FG cancels
        vm.ble.isReady = true
        vm.ble.isConnected = true
        vm.resume()
        if vm.isRunning {
            vm.handleBackgroundTransition()
            #expect(notifier.scheduleCount > scheduleAfterBG || notifier.lastSchedule != nil)
            let cancelBeforeFG = notifier.cancelCount
            vm.handleForegroundTransition()
            #expect(notifier.cancelCount > cancelBeforeFG, "FG cancels end alert")
        }
    }

    @Test("Denied alerts never schedule")
    @MainActor func deniedAlertsNeverSchedule() {
        let suite = "test.alerts.denied.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let notifier = RecordingSessionEndNotifier()
        notifier.authGranted = false
        notifier.canDeliver = false
        let (vm, _) = makeVM(defaults: d, endNotifier: notifier)
        vm.setSessionEndAlertsEnabled(true)
        #expect(vm.sessionEndAlertsDenied)
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let before = notifier.scheduleCount
        vm.handleBackgroundTransition()
        #expect(notifier.scheduleCount == before, "denied must not schedule")
    }

    @Test("Custom soft begin persists across process restore")
    @MainActor func customSoftBeginPersistsAcrossRestore() {
        let suiteName = "test.restore.customsoftbegin.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let (vm1, spy1) = makeVM(defaults: d)
        vm1.selectMode(.custom)
        vm1.strength = 5
        vm1.ble.isConnected = true
        vm1.ble.isReady = true
        vm1.start()
        #expect(spy1.commands.contains("3\n"))
        // Soft window open — persist happens on BG
        vm1.handleBackgroundTransition()
        #expect(d.object(forKey: "session.customSoftBeginElapsed") != nil)

        // Simulate process death: new VM restores running session
        let startTs = d.object(forKey: "session.startDate") as? TimeInterval
        #expect(startTs != nil)
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm2 = SessionViewModel(defaults: d, ble: mock)
        #expect(vm2.isRunning || vm2.isPaused || vm2.selectedMode == .custom)
        #expect(vm2.selectedMode == .custom)
        // Soft begin restored if still within window (session just started)
        #expect(vm2.isRunning, "fresh custom soft session should still be running")
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "custom soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 < 5 }),
                "soft ladder not full spike, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Mindful minutes save on complete via inject seam")
    @MainActor func mindfulMinutesSaveOnComplete() async {
        let suite = "test.mindful.save.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mindful = RecordingMindfulMinutesStore()
        let (vm, _) = makeVM(defaults: d, mindfulStore: mindful)
        vm.setMindfulMinutesEnabled(true)
        // Breathe mode writes mindful samples
        simulateRunning(vm, mode: .calm, strength: 5)
        // Backdate so active duration ≥ 60s meaningful floor
        vm.sessionStartDate = Date().addingTimeInterval(-120)
        vm.stop(reason: .completed)
        // Fire-and-forget Task — drain MainActor
        for _ in 0..<30 where mindful.saveCalls.isEmpty {
            await Task.yield()
        }
        #expect(!mindful.saveCalls.isEmpty, "complete must save mindful range")
        for call in mindful.saveCalls {
            #expect(call.end > call.start)
            #expect(call.end.timeIntervalSince(call.start) >= 30)
        }
    }

    @Test("Custom mid-soft reconnect continues ladder not full spike")
    @MainActor func customMidSoftReconnectContinuesLadder() {
        let (vm, spy) = makeVM()
        vm.selectMode(.custom)
        vm.strength = 5
        vm.ble.isConnected = true
        vm.ble.isReady = true
        vm.start()
        #expect(spy.commands.contains("3\n"))
        // Still in soft window (~1s)
        vm.sessionStartDate = Date().addingTimeInterval(-1)
        spy.reset()
        // Simulate ready reassert / reconnect mid soft
        vm.ble.isReady = false
        vm.ble.isReady = true
        // Absolute lead 0 then channel + soft strength (3 or 4), not full 5 only
        #expect(!spy.commands.isEmpty, "mid-soft ready must reprogram, cmds=\(spy.commands)")
        #expect(
            spy.commands.contains("0\n") || spy.commands.contains("D\n"),
            "absolute lead-off or channel, cmds=\(spy.commands)"
        )
        let nums = spy.commands.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "must send strength, cmds=\(spy.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "must continue soft ladder, cmds=\(spy.commands)")
        #expect(nums.contains(where: { $0 < 5 }),
                "must not only full target, cmds=\(spy.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(spy.commands)")
    }

    @Test("Ease first soft snapshot seeds kill restore ladder")
    @MainActor func easeFirstSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.ease.first.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-2)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(360, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.painRelief.rawValue, forKey: "session.mode")
        d.set(EasePattern.burst.rawValue, forKey: "session.easePattern")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 0
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.easePattern == .burst)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "ease first soft cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("honorLiveActivitySessionEnd does not stop early")
    @MainActor func honorLAEndDoesNotStopEarly() {
        let (vm, _) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        #expect(vm.isRunning)
        vm.honorLiveActivitySessionEnd()
        // Still near full session — must stay running
        #expect(vm.isRunning)
        #expect(vm.remainingSeconds > 0)
    }

    @Test("honorLiveActivitySessionEnd completes when wall past")
    @MainActor func honorLAEndCompletesWhenPast() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 30))
        spy.reset()
        vm.honorLiveActivitySessionEnd()
        #expect(!vm.isRunning)
        #expect(vm.remainingSeconds == 0)
    }

    @Test("honorLiveActivitySessionEnd paused uses inject clock")
    @MainActor func honorLAEndPausedUsesInjectClock() {
        let (vm, _) = makeVM()
        let t0 = Date(timeIntervalSince1970: 1_900_000_000)
        vm.now = { t0 }
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        let planned = vm.timerMinutes * 60
        vm.sessionStartDate = t0
        vm.pause()
        #expect(vm.isPaused)
        // Still early under inject — must not complete
        vm.now = { t0.addingTimeInterval(30) }
        vm.honorLiveActivitySessionEnd()
        #expect(vm.isPaused)
        // Far past planned end under inject clock → complete even while paused
        vm.sessionStartDate = t0.addingTimeInterval(-Double(planned + 3_600))
        vm.now = { t0.addingTimeInterval(3_600) }
        vm.honorLiveActivitySessionEnd()
        #expect(!vm.isPaused && !vm.isRunning)
    }

    @Test("Custom setStrength mid soft never undercuts raised value")
    @MainActor func customSetStrengthMidSoftNoUndercut() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .custom, strength: 5)
        vm.pause()
        spy.reset()
        vm.resume()
        #expect(spy.commands.contains("3\n"))
        spy.reset()
        vm.setStrength(7)
        #expect(spy.commands.contains("7\n"))
        // Advance soft ladder ticks — must not send below 7
        vm.sessionStartDate = Date().addingTimeInterval(-4)
        vm.handleBackgroundTransition()
        vm.ble.onNotification?()
        for cmd in spy.commands {
            if let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)),
               (1...9).contains(n) {
                #expect(n >= 7, "Must not undercut user raise, cmds=\(spy.commands)")
            }
        }
    }

    @Test("Custom paused restore soft-starts on resume")
    @MainActor func customPausedRestoreSoft() {
        let suiteName = "test.restore.customsoft.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-120)
        let pauseStart = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(pauseStart.timeIntervalSince1970, forKey: "session.pauseStartDate")
        d.set(true, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isPaused)
        #expect(vm.selectedMode == .custom)
        mock.reset()
        vm.resume()
        #expect(vm.isRunning)
        #expect(mock.commands.contains("3\n"),
                "Kill mid custom pause must soft-resume, cmds=\(mock.commands)")
    }

    @Test("Paused restore preserves soft-after-pause for Stress")
    @MainActor func pausedRestoreSoftAfterPause() {
        let suiteName = "test.restore.softpause.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-120)
        let pauseStart = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(pauseStart.timeIntervalSince1970, forKey: "session.pauseStartDate")
        d.set(true, forKey: "session.isPaused")
        d.set("stressRelief", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isPaused)
        mock.reset()
        vm.resume()
        #expect(vm.isRunning)
        #expect(mock.commands.contains("3\n"),
                "Kill mid-pause must still soft-resume, cmds=\(mock.commands)")
    }

    @Test("Pause then resume Stress soft-starts not full blast")
    @MainActor func pauseResumeStressSoft() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .stressRelief, strength: 5)
        for _ in 0..<6 {
            vm.sessionStartDate = Date().addingTimeInterval(-10)
            vm.handleBackgroundTransition()
            vm.ble.onNotification?()
            vm.handleForegroundTransition()
        }
        spy.reset()
        vm.pause()
        spy.reset()
        vm.resume()
        #expect(vm.isRunning)
        #expect(spy.commands.contains("0\n"), "resume uses absolute lead-0, cmds=\(spy.commands)")
        #expect(spy.commands.contains("3\n"), "Stress pause resume soft-starts, cmds=\(spy.commands)")
    }

    @Test("Pause then resume Calm soft-starts not full blast")
    @MainActor func pauseResumeCalmSoft() {
        let (vm, spy) = makeVM()
        simulateRunning(vm, mode: .calm, strength: 5)
        // Drive wall into stim-on (~exhale t=12 of 17s cycle)
        for _ in 0..<4 {
            vm.sessionStartDate = Date().addingTimeInterval(-12)
            vm.handleBackgroundTransition()
            vm.ble.onNotification?()
            vm.handleForegroundTransition()
        }
        spy.reset()
        vm.pause()
        spy.reset()
        // Resume still in stim phase
        vm.sessionStartDate = Date().addingTimeInterval(-12)
        vm.resume()
        #expect(vm.isRunning)
        let nums = spy.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "Calm resume should send strength, cmds=\(spy.commands)")
        #expect(
            nums.contains(SoftStart.initialStrength(target: 5)),
            "Calm soft after pause, cmds=\(spy.commands)"
        )
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike after Calm pause, cmds=\(spy.commands)")
    }

    @Test("Calm soft snapshot seeds kill restore ladder at stim phase")
    @MainActor func calmSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.calm.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        // Mid stim-on phase (calm cycle pos 12) with open soft window
        let start = Date().addingTimeInterval(-12)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(300, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set(StimulationMode.calm.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 12
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .calm)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "Calm soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Legacy meditation soft snapshot kill restore uses meditate pace ladder")
    @MainActor func meditationSoftSnapshotKillRestoreLadder() throws {
        let suite = "test.meditation.soft.kill.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let start = Date().addingTimeInterval(-12)
        d.set(start.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        // Legacy raw still persists; Still catalog normalizes → calm + meditate pace
        d.set(StimulationMode.meditation.rawValue, forKey: "session.mode")
        d.set(5, forKey: "session.strength")
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: SoftStart.initialStrength(target: 5),
            beginElapsed: 12
        )
        d.set(try JSONEncoder().encode(snap), forKey: "session.softSnapshot")
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.isRunning)
        #expect(vm.selectedMode == .calm)
        #expect(vm.breathePace == .meditate)
        let nums = mock.commands.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "Meditation soft restore cmds=\(mock.commands)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder, cmds=\(mock.commands)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike, cmds=\(mock.commands)")
    }

    @Test("Mindful segments persist across process restore")
    @MainActor func mindfulSegmentsPersistRestore() {
        let suiteName = "test.mindful.persist.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let t0 = Date().addingTimeInterval(-200)
        let t1 = t0.addingTimeInterval(90)
        // Closed segment + open segment mid-run
        let segs: [[Double]] = [[t0.timeIntervalSince1970, t1.timeIntervalSince1970]]
        if let data = try? JSONEncoder().encode(segs) {
            d.set(data, forKey: "session.mindfulSegments")
        }
        let openStart = t1.addingTimeInterval(30)
        d.set(openStart.timeIntervalSince1970, forKey: "session.mindfulSegmentStart")
        d.set(t0.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("calm", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)

        #expect(vm.isRunning)
        // Closed segment restored (internal; verify via stop mindful path by prefs)
        #expect(d.data(forKey: "session.mindfulSegments") != nil)
        #expect(d.object(forKey: "session.mindfulSegmentStart") != nil)
    }

    @Test("Ready restore Focus rest uses absolute reconnect not soft start")
    @MainActor func restoreReadyFocusRestAbsolute() {
        let suiteName = "test.restore.ready.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        // Focus rest phase: elapsed ~45s (on 0-29, rest 30-59)
        let startDate = Date().addingTimeInterval(-45)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("focus", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        // Mock already ready before init (ready sink fires before restore)
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)

        #expect(vm.isRunning)
        #expect(vm.remainingSeconds >= 550)
        #expect(vm.remainingSeconds <= 560)
        // Absolute rest program — deactivate, not soft ease-in 3/4
        #expect(mock.commands.contains("0\n"), "Rest phase must absolute off, cmds=\(mock.commands)")
        #expect(!mock.commands.contains("3\n"), "Must not soft-start mid-session")
        #expect(!vm.stimulationActive)
        #expect(vm.activeChannel == .off)
    }

    @Test("Offline restore then ready reconnects on-phase Focus")
    @MainActor func restoreOfflineThenReadyOnPhase() {
        let suiteName = "test.restore.offon.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-10)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("focus", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)

        #expect(vm.isRunning)
        #expect(!vm.stimulationActive)
        mock.reset()

        mock.becomeReady()
        // isReady sink should resumeSessionOnDevice
        #expect(mock.commands.contains("A\n") || mock.commands.contains("5\n"),
                "On-phase reconnect, cmds=\(mock.commands)")
        #expect(vm.stimulationActive || mock.commands.contains("A\n"))
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
        // Must still turn device off when BLE returns (kill mid-session safety)
        #expect(vm.pendingDeactivate)
    }

    @Test("Expired restore with ready link enqueues hardware off")
    @MainActor func expiredRestoreReadySendsOff() {
        let suiteName = "test.restore.expired.off.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-700)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let la = RecordingLiveActivity()
        let vm = SessionViewModel(defaults: d, ble: mock, liveActivity: la)

        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate)
        #expect(
            mock.commands.contains(BLEConstants.deactivateCommand)
                || mock.commands.contains("0\n"),
            "expire must requestDeviceOff when ready, cmds=\(mock.commands)"
        )
        #expect(la.endCount >= 1)
        #expect(la.lastEndReason == .completed)
    }

    @Test("Expired restore logs completed history and banner")
    @MainActor func expiredRestoreCompletesHistory() {
        let suiteName = "test.restore.expired.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-700)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("calm", forKey: "session.mode")
        d.set(6, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(vm.pendingDeactivate)
        #expect(!vm.isRunning)
        #expect(vm.completionBanner?.contains("Breathe") == true)
        #expect(vm.recentSessions.count == 1)
        #expect(vm.recentSessions.first?.completed == true)
        #expect(vm.recentSessions.first?.durationSeconds == 600)
        #expect(vm.recentSessions.first?.strength == 6)
        #expect(vm.recentSessions.first?.modeRaw == "calm")
    }



    @Test("No persisted data means fresh VM")
    @MainActor func noPersistenceStartsFresh() {
        let (vm, _) = makeVM()

        #expect(!vm.isRunning)
        #expect(!vm.isPaused)
        #expect(vm.remainingSeconds == 0)
        // Still shell: default Stress, not Custom
        #expect(vm.selectedMode == .stressRelief)
        #expect(vm.selectedFeeling == .stressed)
    }

    @Test("Custom restore clears feeling when key absent")
    @MainActor func customRestoreClearsDefaultFeeling() {
        let suiteName = "test.restore.custom.feeling.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        // no session.feeling key
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.selectedMode == .custom)
        #expect(vm.selectedFeeling == nil)
        #expect(vm.sessionTitle == "Custom")
    }

    @Test("Legacy meditation mode normalizes to Breathe + meditate pace")
    @MainActor func legacyMeditationNormalizes() {
        let suiteName = "test.restore.med.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("meditation", forKey: "session.mode")
        d.set(4, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.selectedMode == .calm)
        #expect(vm.breathePace == .meditate)
        // Disk re-written with primary mode (not legacy raw)
        #expect(d.string(forKey: "session.mode") == "calm")
    }

    @Test("Legacy headache normalizes to Ease burst and persists")
    @MainActor func legacyHeadacheNormalizes() {
        let suiteName = "test.restore.head.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-30)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("headache", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.selectedMode == .painRelief)
        #expect(vm.easePattern == .burst)
        #expect(d.string(forKey: "session.mode") == "painRelief")
        #expect(vm.sessionTitle == "Ease")
    }

    @Test("Legacy learn normalizes to Focus")
    @MainActor func legacyLearnNormalizes() {
        let suiteName = "test.restore.learn.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-20)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("learn", forKey: "session.mode")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.selectedMode == .focus)
        #expect(d.string(forKey: "session.mode") == "focus")
    }

    @Test("Feeling/mode mismatch on restore clears feeling")
    @MainActor func feelingModeMismatchClearsFeeling() {
        let suiteName = "test.restore.mismatch.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-20)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("focus", forKey: "session.mode")
        // Anxious maps to calm/Breathe — disagrees with focus
        d.set("anxious", forKey: "session.feeling")
        d.set(5, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.selectedMode == .focus)
        #expect(vm.selectedFeeling == nil)
        #expect(vm.sessionTitle == "Focus")
    }

    @Test("Normalize persists breathePace for legacy meditation")
    @MainActor func legacyMeditationPersistsPace() {
        let suiteName = "test.restore.medpace.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        let startDate = Date().addingTimeInterval(-20)
        d.set(startDate.timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(0.0, forKey: "session.accumulatedPauseTime")
        d.set(false, forKey: "session.isPaused")
        d.set("meditation", forKey: "session.mode")
        d.set(4, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)
        #expect(vm.breathePace == .meditate)
        #expect(d.string(forKey: "session.breathePace") == "meditate"
            || d.string(forKey: "session.mode") == "calm")
    }

    @Test("Anxious feeling pins calm pace (not leftover meditate)")
    @MainActor func anxiousPinsCalmPace() {
        let (vm, _) = makeVM()
        vm.selectFeeling(.scattered)
        #expect(vm.breathePace == .meditate)
        vm.selectFeeling(.anxious)
        #expect(vm.breathePace == .calm)
        #expect(vm.selectedMode == .calm)
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

    @Test("Strength uses mode default when persisted as 0 / corrupt")
    @MainActor func strengthDefaultsWhenPersistedZero() {
        let suiteName = "test.restore.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suiteName)!
        d.set(Date().addingTimeInterval(-10).timeIntervalSince1970, forKey: "session.startDate")
        d.set(600, forKey: "session.totalDuration")
        d.set(false, forKey: "session.isPaused")
        d.set("custom", forKey: "session.mode")
        d.set(0, forKey: "session.strength")

        let (vm, _) = makeVM(defaults: d)

        #expect(vm.strength == StimulationMode.custom.defaultStrength)
        #expect((1...9).contains(vm.strength))
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

// MARK: - Ambient music (optional local pad)

@Suite("SessionViewModel — Ambient music")
struct AmbientMusicSessionTests {
    @Test("Start with ambient off does not play")
    @MainActor func startAmbientOffNoPlay() {
        let audio = NullAmbientAudio()
        let (vm, _) = makeVM(ambientAudio: audio)
        #expect(!vm.ambientMusicEnabled)
        simulateRunning(vm, mode: .stressRelief)
        #expect(!audio.isPlaying)
    }

    @Test("Start with ambient on plays while running foreground")
    @MainActor func startAmbientOnPlays() {
        let audio = NullAmbientAudio()
        let (vm, _) = makeVM(ambientAudio: audio)
        vm.setAmbientMusicEnabled(true)
        simulateRunning(vm, mode: .calm)
        #expect(audio.isPlaying)
        #expect(vm.ambientMusicEnabled)
    }

    @Test("Pause stops ambient; resume restarts")
    @MainActor func pauseStopsAmbientResumeRestarts() {
        let audio = NullAmbientAudio()
        let (vm, _) = makeVM(ambientAudio: audio)
        vm.setAmbientMusicEnabled(true)
        simulateRunning(vm, mode: .sleep)
        #expect(audio.isPlaying)
        vm.pause()
        #expect(!audio.isPlaying)
        // Ready for resume
        if let mock = vm.ble as? MockDeviceTransport {
            mock.isReady = true
            mock.isConnected = true
        }
        vm.resume()
        #expect(audio.isPlaying)
    }

    @Test("Background stops ambient without stopping session")
    @MainActor func backgroundStopsAmbientKeepsSession() {
        let audio = NullAmbientAudio()
        let (vm, _) = makeVM(ambientAudio: audio)
        vm.setAmbientMusicEnabled(true)
        simulateRunning(vm, mode: .focus)
        #expect(audio.isPlaying)
        vm.handleBackgroundTransition()
        #expect(vm.isRunning)
        #expect(!audio.isPlaying)
        vm.handleForegroundTransition()
        #expect(vm.isRunning)
        #expect(audio.isPlaying)
    }

    @Test("Stop fades ambient off")
    @MainActor func stopEndsAmbient() {
        let audio = NullAmbientAudio()
        let (vm, _) = makeVM(ambientAudio: audio)
        vm.setAmbientMusicEnabled(true)
        simulateRunning(vm, mode: .stressRelief)
        vm.stop()
        #expect(!audio.isPlaying)
        #expect(audio.stopCount >= 1)
    }
}

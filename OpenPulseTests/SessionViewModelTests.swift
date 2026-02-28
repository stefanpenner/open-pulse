import Testing
@testable import OpenPulse

// MARK: - Helpers

/// Captures BLE commands sent via the view model's BluetoothManager.
@MainActor
private func makeVM() -> (SessionViewModel, CommandSpy) {
    let vm = SessionViewModel()
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

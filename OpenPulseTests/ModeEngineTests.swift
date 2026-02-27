import Testing
@testable import OpenPulse

// MARK: - BLEConstants Tests

@Suite("BLEConstants")
struct BLEConstantsTests {
    @Test("Battery percentage at full voltage returns 100")
    func batteryFull() {
        #expect(BLEConstants.batteryPercentage(fromVoltage: 3.95) == 100)
        #expect(BLEConstants.batteryPercentage(fromVoltage: 4.2) == 100)
    }

    @Test("Battery percentage at empty voltage returns 0")
    func batteryEmpty() {
        #expect(BLEConstants.batteryPercentage(fromVoltage: 2.5) == 0)
        #expect(BLEConstants.batteryPercentage(fromVoltage: 2.0) == 0)
    }

    @Test("Battery percentage mid-range")
    func batteryMidRange() {
        // Midpoint: (3.95 + 2.5) / 2 = 3.225 → ~50%
        let pct = BLEConstants.batteryPercentage(fromVoltage: 3.225)
        #expect(pct == 50)
    }

    @Test("Strength command format")
    func strengthCommand() {
        #expect(BLEConstants.strengthCommand(5) == "5\n")
        #expect(BLEConstants.strengthCommand(1) == "1\n")
        #expect(BLEConstants.strengthCommand(9) == "9\n")
    }
}

// MARK: - StressRelief Engine Tests

@Suite("StressReliefEngine")
struct StressReliefEngineTests {
    @Test("Start sends bilateral activate and strength")
    func start() {
        var engine = StressReliefEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 360)
        #expect(cmds == ["D\n", "5\n"])
    }

    @Test("Tick always returns stimulation active with no commands")
    func tickAlwaysActive() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        for elapsed in [0, 60, 180, 359] {
            let result = engine.tick(elapsed: elapsed, totalDuration: 360, baseStrength: 5)
            #expect(result.isStimulationActive)
            #expect(result.commands.isEmpty)
            #expect(result.effectiveStrength == nil)
        }
    }

    @Test("Reconnect sends bilateral activate and strength")
    func reconnect() {
        let engine = StressReliefEngine()
        let cmds = engine.reconnectCommands(elapsed: 100, totalDuration: 360, baseStrength: 7)
        #expect(cmds == ["D\n", "7\n"])
    }
}

// MARK: - Sleep Engine Tests

@Suite("SleepEngine")
struct SleepEngineTests {
    @Test("Start activates bilateral")
    func start() {
        var engine = SleepEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 600)
        #expect(cmds == ["D\n", "5\n"])
    }

    @Test("Channel rotation across 5 phases")
    func channelRotation() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // Phase length = 600/5 = 120s each
        // Phase 0 (0-119): D, Phase 1 (120-239): A, Phase 2 (240-359): D,
        // Phase 3 (360-479): C, Phase 4 (480-599): D

        // Tick at t=119 — still phase 0, no channel switch
        let r0 = engine.tick(elapsed: 119, totalDuration: 600, baseStrength: 5)
        #expect(!r0.commands.contains("A\n"))

        // Tick at t=120 — enters phase 1 (left)
        let r1 = engine.tick(elapsed: 120, totalDuration: 600, baseStrength: 5)
        #expect(r1.commands.contains("A\n"))

        // Tick at t=240 — enters phase 2 (bilateral)
        let r2 = engine.tick(elapsed: 240, totalDuration: 600, baseStrength: 5)
        #expect(r2.commands.contains("D\n"))

        // Tick at t=360 — enters phase 3 (right)
        let r3 = engine.tick(elapsed: 360, totalDuration: 600, baseStrength: 5)
        #expect(r3.commands.contains("C\n"))

        // Tick at t=480 — enters phase 4 (bilateral)
        let r4 = engine.tick(elapsed: 480, totalDuration: 600, baseStrength: 5)
        #expect(r4.commands.contains("D\n"))
    }

    @Test("Fade reduces strength in last 20%")
    func fadeInLastPhase() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // Fade starts at t=480 (80% of 600)
        // First half of fade (480-539): strength 4
        // Second half (540-599): strength 3

        // Tick through to phase 4 to set lastPhaseIndex
        for t in 1...479 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }

        // At t=480, should see fade to 4
        let r480 = engine.tick(elapsed: 480, totalDuration: 600, baseStrength: 5)
        #expect(r480.effectiveStrength == 4)

        // At t=540, should see fade to 3
        let r540 = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 5)
        #expect(r540.effectiveStrength == 3)
    }

    @Test("Fade does not go below 1")
    func fadeFloor() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 1, totalDuration: 600)

        // Tick to fade zone
        for t in 1...539 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 1)
        }

        let r = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 1)
        // max(1, 1-2) = 1
        if let eff = r.effectiveStrength {
            #expect(eff >= 1)
        }
    }

    @Test("Reconnect returns correct channel for phase")
    func reconnect() {
        let engine = SleepEngine()
        // Phase 1 (t=120, duration=600) → left channel
        let cmds = engine.reconnectCommands(elapsed: 150, totalDuration: 600, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("5\n"))
    }
}

// MARK: - Focus Engine Tests

@Suite("FocusEngine")
struct FocusEngineTests {
    @Test("Start sends left channel and strength")
    func start() {
        var engine = FocusEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 360)
        #expect(cmds == ["A\n", "5\n"])
    }

    @Test("30s on / 30s off duty cycling")
    func dutyCycle() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        // t=0-29: on phase
        let r10 = engine.tick(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(r10.isStimulationActive)

        // Tick to t=29 to advance state
        for t in 11...29 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5)
        }

        // t=30: off phase starts
        let r30 = engine.tick(elapsed: 30, totalDuration: 360, baseStrength: 5)
        #expect(!r30.isStimulationActive)
        #expect(r30.commands.contains("0\n"))

        // Tick to t=59
        for t in 31...59 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5)
        }

        // t=60: on phase again
        let r60 = engine.tick(elapsed: 60, totalDuration: 360, baseStrength: 5)
        #expect(r60.isStimulationActive)
        #expect(r60.commands.contains("A\n"))
    }

    @Test("Midpoint bump increases strength by 1")
    func midpointBump() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        // Midpoint = 180

        // Tick to just before midpoint
        for t in 1...179 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5)
        }

        // At t=180 (on phase, since 180%60=0 < 30), bump should occur
        let r = engine.tick(elapsed: 180, totalDuration: 360, baseStrength: 5)
        #expect(r.commands.contains("6\n"))
    }

    @Test("Midpoint bump capped at 9")
    func midpointBumpCapped() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 9, totalDuration: 360)

        for t in 1...179 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 9)
        }

        let r = engine.tick(elapsed: 180, totalDuration: 360, baseStrength: 9)
        // min(9, 9+1) = 9, so no effective change — command should still be "9\n"
        #expect(r.commands.contains("9\n"))
    }

    @Test("Reconnect during off phase sends deactivate")
    func reconnectOffPhase() {
        let engine = FocusEngine()
        // t=35: off phase (35%60=35 >= 30)
        let cmds = engine.reconnectCommands(elapsed: 35, totalDuration: 360, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Reconnect during on phase sends left channel + strength")
    func reconnectOnPhase() {
        let engine = FocusEngine()
        // t=10: on phase (10%60=10 < 30)
        let cmds = engine.reconnectCommands(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("5\n"))
    }

    @Test("Reconnect after midpoint uses bumped strength")
    func reconnectAfterMidpoint() {
        let engine = FocusEngine()
        // t=190: on phase after midpoint (190%60=10 < 30, elapsed >= 180)
        let cmds = engine.reconnectCommands(elapsed: 190, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("6\n"))
    }
}

// MARK: - PainRelief Engine Tests

@Suite("PainReliefEngine")
struct PainReliefEngineTests {
    @Test("Start sends bilateral activate and strength")
    func start() {
        var engine = PainReliefEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 480)
        #expect(cmds == ["D\n", "5\n"])
    }

    @Test("Always stimulation active")
    func alwaysActive() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 480)

        for elapsed in [0, 7, 15, 22, 30, 60, 120] {
            let result = engine.tick(elapsed: elapsed, totalDuration: 480, baseStrength: 5)
            #expect(result.isStimulationActive)
        }
    }

    @Test("Sine wave produces ±1 oscillation")
    func sineOscillation() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 480)

        // Collect all effective strengths over one 30s period
        var strengths = Set<Int>()
        for t in 0...30 {
            let r = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 5)
            let s = r.effectiveStrength ?? 5
            strengths.insert(s)
        }

        // Should see values of 4, 5, and 6 (base ±1)
        #expect(strengths.contains(4) || strengths.contains(6))
    }

    @Test("Strength clamped at minimum 1")
    func strengthFloor() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 1, totalDuration: 480)

        for t in 0...30 {
            let r = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 1)
            let s = r.effectiveStrength ?? 1
            #expect(s >= 1)
        }
    }

    @Test("Strength clamped at maximum 9")
    func strengthCeiling() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 9, totalDuration: 480)

        for t in 0...30 {
            let r = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 9)
            let s = r.effectiveStrength ?? 9
            #expect(s <= 9)
        }
    }

    @Test("Reconnect sends bilateral with oscillated strength")
    func reconnect() {
        let engine = PainReliefEngine()
        let cmds = engine.reconnectCommands(elapsed: 100, totalDuration: 480, baseStrength: 5)
        #expect(cmds.first == "D\n")
        #expect(cmds.count == 2)
    }
}

// MARK: - Calm Engine Tests

@Suite("CalmEngine")
struct CalmEngineTests {
    @Test("Start returns no commands (begins with inhale)")
    func start() {
        var engine = CalmEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 300)
        #expect(cmds.isEmpty)
    }

    @Test("Inhale phase is first 4 seconds of 10s cycle")
    func inhalePhase() {
        var engine = CalmEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        for t in 0...3 {
            let r = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
            #expect(!r.isStimulationActive)
            if case .inhale = r.breathingPhase {
                // expected
            } else {
                Issue.record("Expected inhale at t=\(t)")
            }
        }
    }

    @Test("Exhale phase activates stimulation at t=4")
    func exhaleActivation() {
        var engine = CalmEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // Tick through inhale
        for t in 0...3 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // t=4: transition to exhale
        let r = engine.tick(elapsed: 4, totalDuration: 300, baseStrength: 5)
        #expect(r.isStimulationActive)
        #expect(r.commands.contains("D\n"))
        #expect(r.commands.contains("5\n"))
    }

    @Test("Inhale deactivates stimulation at t=10")
    func inhaleDeactivation() {
        var engine = CalmEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // Run through first full cycle
        for t in 0...9 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // t=10: back to inhale (10%10=0 < 4)
        let r = engine.tick(elapsed: 10, totalDuration: 300, baseStrength: 5)
        #expect(!r.isStimulationActive)
        #expect(r.commands.contains("0\n"))
    }

    @Test("Breathing phase progress increases within each phase")
    func breathingProgress() {
        var engine = CalmEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // Inhale progress: t=0 → 0/4=0.0, t=1 → 1/4=0.25, t=2 → 0.5, t=3 → 0.75
        let r0 = engine.tick(elapsed: 0, totalDuration: 300, baseStrength: 5)
        let r2 = engine.tick(elapsed: 2, totalDuration: 300, baseStrength: 5)

        if case .inhale(let p0) = r0.breathingPhase,
           case .inhale(let p2) = r2.breathingPhase {
            #expect(p2 > p0)
        } else {
            Issue.record("Expected inhale phases")
        }
    }

    @Test("Reconnect during exhale sends activate")
    func reconnectExhale() {
        let engine = CalmEngine()
        // t=5: exhale (5%10=5 >= 4)
        let cmds = engine.reconnectCommands(elapsed: 5, totalDuration: 300, baseStrength: 5)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("5\n"))
    }

    @Test("Reconnect during inhale sends deactivate")
    func reconnectInhale() {
        let engine = CalmEngine()
        // t=1: inhale (1%10=1 < 4)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 300, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Full cycle repeats correctly")
    func fullCycleRepeat() {
        var engine = CalmEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // Run 3 full cycles (30 seconds)
        var activations = 0
        var deactivations = 0

        for t in 0...29 {
            let r = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
            if r.commands.contains("D\n") { activations += 1 }
            if r.commands.contains("0\n") { deactivations += 1 }
        }

        // 3 cycles: each has 1 activation (at t=4,14,24) and 1 deactivation (at t=10,20)
        // First cycle: no deactivation at t=0 (start is inhale), activation at t=4
        // So: 3 activations, 2 deactivations in first 30s
        #expect(activations == 3)
        #expect(deactivations == 2)
    }
}

// MARK: - StimulationMode Tests

@Suite("StimulationMode")
struct StimulationModeTests {
    @Test("All modes have names")
    func allModesHaveNames() {
        for mode in StimulationMode.allCases {
            #expect(!mode.name.isEmpty)
        }
    }

    @Test("Custom mode has no engine")
    func customNoEngine() {
        #expect(StimulationMode.custom.makeEngine() == nil)
    }

    @Test("Non-custom modes have engines")
    func nonCustomHaveEngines() {
        for mode in StimulationMode.allCases where mode != .custom {
            #expect(mode.makeEngine() != nil)
        }
    }

    @Test("Default durations are positive")
    func positiveDurations() {
        for mode in StimulationMode.allCases {
            #expect(mode.defaultDurationMinutes > 0)
        }
    }

    @Test("Default strengths are in valid range")
    func validStrengths() {
        for mode in StimulationMode.allCases {
            #expect(mode.defaultStrength >= 1 && mode.defaultStrength <= 9)
        }
    }

    @Test("Research links exist for non-custom modes")
    func researchLinks() {
        for mode in StimulationMode.allCases where mode != .custom {
            #expect(!mode.researchLinks.isEmpty)
        }
    }

    @Test("Custom mode has no research links")
    func customNoResearchLinks() {
        #expect(StimulationMode.custom.researchLinks.isEmpty)
    }
}

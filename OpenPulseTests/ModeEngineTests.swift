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

    @Test("Active channel is always bilateral")
    func activeChannelBilateral() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        let result = engine.tick(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(result.activeChannel == .bilateral)
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

    @Test("Active channel maps to phase correctly")
    func activeChannelPerPhase() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // Phase 0: bilateral
        let r0 = engine.tick(elapsed: 10, totalDuration: 600, baseStrength: 5)
        #expect(r0.activeChannel == .bilateral)

        // Phase 1: left
        let r1 = engine.tick(elapsed: 120, totalDuration: 600, baseStrength: 5)
        #expect(r1.activeChannel == .left)

        // Phase 2: bilateral
        let r2 = engine.tick(elapsed: 240, totalDuration: 600, baseStrength: 5)
        #expect(r2.activeChannel == .bilateral)

        // Phase 3: right
        let r3 = engine.tick(elapsed: 360, totalDuration: 600, baseStrength: 5)
        #expect(r3.activeChannel == .right)

        // Phase 4: bilateral
        let r4 = engine.tick(elapsed: 480, totalDuration: 600, baseStrength: 5)
        #expect(r4.activeChannel == .bilateral)
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

    @Test("Constant intensity throughout session")
    func constantIntensity() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        // Tick past midpoint
        for t in 1...179 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5)
        }

        // At t=180 (on phase), strength remains at base
        let r = engine.tick(elapsed: 180, totalDuration: 360, baseStrength: 5)
        #expect(r.isStimulationActive)
        #expect(!r.commands.contains("6\n"))
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

    @Test("Reconnect after midpoint uses base strength")
    func reconnectAfterMidpoint() {
        let engine = FocusEngine()
        // t=190: on phase after midpoint (190%60=10 < 30)
        let cmds = engine.reconnectCommands(elapsed: 190, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("5\n"))
    }

    @Test("Active channel is left when on, off when resting")
    func activeChannelLeftOrOff() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        let rOn = engine.tick(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(rOn.activeChannel == .left)

        // Tick to t=29
        for t in 11...29 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5)
        }

        let rOff = engine.tick(elapsed: 30, totalDuration: 360, baseStrength: 5)
        #expect(rOff.activeChannel == .off)
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

    @Test("Active channel is always bilateral")
    func activeChannelBilateral() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 480)

        let result = engine.tick(elapsed: 10, totalDuration: 480, baseStrength: 5)
        #expect(result.activeChannel == .bilateral)
    }
}

// MARK: - Calm Engine Tests

@Suite("CalmEngine")
struct CalmEngineTests {
    // 17s cycle: 5s inhale + 5s hold + 7s exhale (no rest)
    // Ramp lead = 2s: BLE activate fires at t=3 (during late inhale)

    @Test("Start returns no commands (begins with inhale)")
    func start() {
        var engine = CalmEngine.make()
        let cmds = engine.start(baseStrength: 5, totalDuration: 300)
        #expect(cmds.isEmpty)
    }

    @Test("Early inhale is not stimulating")
    func earlyInhaleOff() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // t=0,1,2: early inhale, before ramp lead — no stimulation
        for t in 0...2 {
            let r = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
            #expect(!r.isStimulationActive, "Should not stimulate at t=\(t)")
            if case .inhale = r.breathingPhase {
                // expected
            } else {
                Issue.record("Expected inhale at t=\(t)")
            }
        }
    }

    @Test("Ramp lead activates BLE during late inhale at t=3")
    func rampLeadActivation() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // Tick through early inhale
        for t in 0...2 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // t=3: ramp lead fires (inhaleDuration 5 - rampLeadTime 2 = 3)
        let r3 = engine.tick(elapsed: 3, totalDuration: 300, baseStrength: 5)
        #expect(r3.isStimulationActive)
        #expect(r3.commands.contains("D\n"))
        #expect(r3.commands.contains("5\n"))
        // UI still shows inhale phase
        if case .inhale = r3.breathingPhase {
            // expected — BLE fires early but UI stays in inhale
        } else {
            Issue.record("Expected inhale phase at t=3")
        }
    }

    @Test("Hold phase shows hold in UI")
    func holdPhase() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        for t in 0...4 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // t=5: hold phase (5s hold) — device already ramping, no new commands
        let r5 = engine.tick(elapsed: 5, totalDuration: 300, baseStrength: 5)
        #expect(r5.isStimulationActive)
        #expect(r5.commands.isEmpty, "No new commands — already activated at t=3")
        if case .hold(let p) = r5.breathingPhase {
            #expect(p == 0.0)
        } else {
            Issue.record("Expected hold at t=5")
        }

        // Hold continues through t=9
        for t in 6...8 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }
        let r9 = engine.tick(elapsed: 9, totalDuration: 300, baseStrength: 5)
        #expect(r9.isStimulationActive)
        if case .hold = r9.breathingPhase {
            // expected — still holding
        } else {
            Issue.record("Expected hold at t=9")
        }
    }

    @Test("Exhale continues stimulation")
    func exhaleContinues() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        for t in 0...9 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // t=10: exhale starts (5 inhale + 5 hold = 10)
        let r = engine.tick(elapsed: 10, totalDuration: 300, baseStrength: 5)
        #expect(r.isStimulationActive)
        #expect(r.commands.isEmpty)
    }

    @Test("Deactivates at cycle boundary t=17, new inhale starts")
    func cycleReset() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        for t in 0...16 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // t=17: new cycle (17%17=0) — back to early inhale, deactivate
        let r = engine.tick(elapsed: 17, totalDuration: 300, baseStrength: 5)
        #expect(!r.isStimulationActive)
        #expect(r.commands.contains("0\n"))
        if case .inhale(let p) = r.breathingPhase {
            #expect(p == 0.0)
        } else {
            Issue.record("Expected inhale at t=17")
        }
    }

    @Test("Breathing phase progress increases within each phase")
    func breathingProgress() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        let r0 = engine.tick(elapsed: 0, totalDuration: 300, baseStrength: 5)
        let r2 = engine.tick(elapsed: 2, totalDuration: 300, baseStrength: 5)

        if case .inhale(let p0) = r0.breathingPhase,
           case .inhale(let p2) = r2.breathingPhase {
            #expect(p2 > p0)
        } else {
            Issue.record("Expected inhale phases")
        }
    }

    @Test("Reconnect during stimulation sends activate")
    func reconnectStimPhase() {
        let engine = CalmEngine.make()
        // t=6: hold — stimulating
        let holdCmds = engine.reconnectCommands(elapsed: 6, totalDuration: 300, baseStrength: 5)
        #expect(holdCmds.contains("D\n"))
        #expect(holdCmds.contains("5\n"))

        // t=12: exhale — stimulating (5+5=10 exhale start, 10+7=17 cycle end)
        let exhaleCmds = engine.reconnectCommands(elapsed: 12, totalDuration: 300, baseStrength: 5)
        #expect(exhaleCmds.contains("D\n"))
        #expect(exhaleCmds.contains("5\n"))
    }

    @Test("Reconnect during early inhale sends deactivate")
    func reconnectInhale() {
        let engine = CalmEngine.make()
        // t=1: early inhale (1%17=1 < 3 ramp start)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 300, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Reconnect at cycle boundary sends deactivate")
    func reconnectCycleBoundary() {
        let engine = CalmEngine.make()
        // t=17: cycle reset (17%17=0, early inhale before ramp lead)
        let cmds = engine.reconnectCommands(elapsed: 17, totalDuration: 300, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Active channel is bilateral during stim, off during inhale/rest")
    func activeChannelCalmMode() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        // Early inhale: off
        let rInhale = engine.tick(elapsed: 1, totalDuration: 300, baseStrength: 5)
        #expect(rInhale.activeChannel == .off)

        // Tick to ramp lead
        _ = engine.tick(elapsed: 2, totalDuration: 300, baseStrength: 5)

        // t=3: ramp lead fires — bilateral
        let rRamp = engine.tick(elapsed: 3, totalDuration: 300, baseStrength: 5)
        #expect(rRamp.activeChannel == .bilateral)

        // Tick through to exhale (5 inhale + 5 hold = 10)
        for t in 4...9 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }

        // Exhale: bilateral
        let rExhale = engine.tick(elapsed: 10, totalDuration: 300, baseStrength: 5)
        #expect(rExhale.activeChannel == .bilateral)
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

    @Test("Breathing guide modes identified correctly")
    func breathingGuideModes() {
        #expect(StimulationMode.calm.usesBreathingGuide)
        #expect(StimulationMode.meditation.usesBreathingGuide)
        #expect(!StimulationMode.stressRelief.usesBreathingGuide)
        #expect(!StimulationMode.headache.usesBreathingGuide)
        #expect(!StimulationMode.nausea.usesBreathingGuide)
    }

    @Test("Breathing cycle parameters match expected values")
    func breathingCycleParams() {
        let calm = StimulationMode.calm.breathingCycle
        #expect(calm?.inhaleDuration == 5)
        #expect(calm?.holdDuration == 5)
        #expect(calm?.exhaleDuration == 7)
        #expect(calm?.restDuration == 0)
        #expect(calm?.cycleLength == 17)
        #expect(calm?.rampLeadTime == 2)

        let med = StimulationMode.meditation.breathingCycle
        #expect(med?.inhaleDuration == 5)
        #expect(med?.holdDuration == 4)
        #expect(med?.exhaleDuration == 5)
        #expect(med?.restDuration == 0)
        #expect(med?.cycleLength == 14)
        #expect(med?.rampLeadTime == 2)

        #expect(StimulationMode.headache.breathingCycle == nil)
    }
}

// MARK: - Headache Engine Tests

@Suite("HeadacheEngine")
struct HeadacheEngineTests {
    @Test("Start sends bilateral activate and strength")
    func start() {
        var engine = HeadacheEngine()
        let cmds = engine.start(baseStrength: 7, totalDuration: 360)
        #expect(cmds == ["D\n", "7\n"])
    }

    @Test("2-min on / 30s off burst cycling")
    func burstCycle() {
        var engine = HeadacheEngine()
        _ = engine.start(baseStrength: 7, totalDuration: 360)

        // t=0-119: on (burst)
        let r10 = engine.tick(elapsed: 10, totalDuration: 360, baseStrength: 7)
        #expect(r10.isStimulationActive)
        #expect(r10.activeChannel == .bilateral)

        // Tick to t=119
        for t in 11...119 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 7)
        }

        // t=120: pause starts
        let r120 = engine.tick(elapsed: 120, totalDuration: 360, baseStrength: 7)
        #expect(!r120.isStimulationActive)
        #expect(r120.commands.contains("0\n"))
        #expect(r120.activeChannel == .off)

        // Tick to t=149
        for t in 121...149 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 7)
        }

        // t=150: back on
        let r150 = engine.tick(elapsed: 150, totalDuration: 360, baseStrength: 7)
        #expect(r150.isStimulationActive)
        #expect(r150.commands.contains("D\n"))
    }

    @Test("Reconnect during burst sends activate")
    func reconnectBurst() {
        let engine = HeadacheEngine()
        let cmds = engine.reconnectCommands(elapsed: 60, totalDuration: 360, baseStrength: 7)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("7\n"))
    }

    @Test("Reconnect during pause sends deactivate")
    func reconnectPause() {
        let engine = HeadacheEngine()
        // t=130: pause (130%150=130 >= 120)
        let cmds = engine.reconnectCommands(elapsed: 130, totalDuration: 360, baseStrength: 7)
        #expect(cmds == ["0\n"])
    }
}

// MARK: - Nausea Engine Tests

@Suite("NauseaEngine")
struct NauseaEngineTests {
    @Test("Start sends bilateral activate and strength")
    func start() {
        var engine = NauseaEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 300)
        #expect(cmds == ["D\n", "5\n"])
    }

    @Test("Tick always returns stimulation active with no commands")
    func tickAlwaysActive() {
        var engine = NauseaEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 300)

        for elapsed in [0, 60, 150, 299] {
            let result = engine.tick(elapsed: elapsed, totalDuration: 300, baseStrength: 5)
            #expect(result.isStimulationActive)
            #expect(result.commands.isEmpty)
            #expect(result.activeChannel == .bilateral)
        }
    }

    @Test("Reconnect sends bilateral activate and strength")
    func reconnect() {
        let engine = NauseaEngine()
        let cmds = engine.reconnectCommands(elapsed: 100, totalDuration: 300, baseStrength: 5)
        #expect(cmds == ["D\n", "5\n"])
    }
}

// MARK: - Meditation Engine Tests

@Suite("MeditationEngine")
struct MeditationEngineTests {
    // 14s cycle: 5s inhale + 4s hold + 5s exhale (no rest)
    // Ramp lead = 2s: BLE activate fires at t=3 (during late inhale)

    @Test("Start returns no commands (begins with inhale)")
    func start() {
        var engine = MeditationEngine.make()
        let cmds = engine.start(baseStrength: 4, totalDuration: 600)
        #expect(cmds.isEmpty)
    }

    @Test("Early inhale not stimulating, ramp lead at t=3")
    func rampLeadTiming() {
        var engine = MeditationEngine.make()
        _ = engine.start(baseStrength: 4, totalDuration: 600)

        // t=0-2: early inhale, no stimulation
        for t in 0...2 {
            let r = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 4)
            #expect(!r.isStimulationActive, "No stim at t=\(t)")
        }

        // t=3: ramp lead fires (5 - 2 = 3)
        let r3 = engine.tick(elapsed: 3, totalDuration: 600, baseStrength: 4)
        #expect(r3.isStimulationActive)
        #expect(r3.commands.contains("D\n"))
    }

    @Test("Hold phase shows hold in UI at t=5")
    func holdPhase() {
        var engine = MeditationEngine.make()
        _ = engine.start(baseStrength: 4, totalDuration: 600)

        for t in 0...4 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 4)
        }

        let r5 = engine.tick(elapsed: 5, totalDuration: 600, baseStrength: 4)
        #expect(r5.isStimulationActive)
        if case .hold(let p) = r5.breathingPhase {
            #expect(p == 0.0)
        } else {
            Issue.record("Expected hold at t=5")
        }

        // Hold continues through t=8 (4s hold)
        for t in 6...7 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 4)
        }
        let r8 = engine.tick(elapsed: 8, totalDuration: 600, baseStrength: 4)
        #expect(r8.isStimulationActive)
        if case .hold = r8.breathingPhase {
            // expected — still holding
        } else {
            Issue.record("Expected hold at t=8")
        }
    }

    @Test("Exhale phase at t=9, deactivates at cycle boundary t=14")
    func exhaleAndCycleReset() {
        var engine = MeditationEngine.make()
        _ = engine.start(baseStrength: 4, totalDuration: 600)

        for t in 0...8 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 4)
        }

        // t=9: exhale (5+4=9)
        let r9 = engine.tick(elapsed: 9, totalDuration: 600, baseStrength: 4)
        #expect(r9.isStimulationActive)
        if case .exhale = r9.breathingPhase {
            // expected
        } else {
            Issue.record("Expected exhale at t=9")
        }

        for t in 10...13 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 4)
        }

        // t=14: new cycle (14%14=0) — back to early inhale, deactivate
        let r14 = engine.tick(elapsed: 14, totalDuration: 600, baseStrength: 4)
        #expect(!r14.isStimulationActive)
        #expect(r14.commands.contains("0\n"))
        if case .inhale(let p) = r14.breathingPhase {
            #expect(p == 0.0)
        } else {
            Issue.record("Expected inhale at t=14")
        }
    }

    @Test("14s cycle length verified")
    func cycleLength() {
        let cycle = BreathingCycle.meditation
        #expect(cycle.cycleLength == 14)
        #expect(cycle.inhaleDuration == 5)
        #expect(cycle.holdDuration == 4)
        #expect(cycle.exhaleDuration == 5)
        #expect(cycle.restDuration == 0)
        #expect(cycle.rampLeadTime == 2)
    }

    @Test("Reconnect during exhale sends activate")
    func reconnectExhale() {
        let engine = MeditationEngine.make()
        // t=10: exhale (10%14=10, >= 3 ramp start, < 14 stim end)
        let cmds = engine.reconnectCommands(elapsed: 10, totalDuration: 600, baseStrength: 4)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("4\n"))
    }

    @Test("Reconnect during early inhale sends deactivate")
    func reconnectInhale() {
        let engine = MeditationEngine.make()
        // t=1: early inhale (1%14=1 < 3 ramp start)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 600, baseStrength: 4)
        #expect(cmds == ["0\n"])
    }
}

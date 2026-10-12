import Foundation
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

    @Test("Strength command clamps out-of-range values")
    func strengthCommandClamps() {
        #expect(BLEConstants.strengthCommand(0) == "1\n")
        #expect(BLEConstants.strengthCommand(-3) == "1\n")
        #expect(BLEConstants.strengthCommand(15) == "9\n")
    }
}

// MARK: - StressRelief Engine Tests

@Suite("StressReliefEngine")
struct StressReliefEngineTests {
    @Test("Start soft-starts two below target strength")
    func start() {
        var engine = StressReliefEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 360)
        #expect(cmds == ["D\n", "3\n"])
    }

    @Test("Soft-start steps up to target then holds continuous")
    func softStartThenContinuous() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        let r0 = engine.tick(elapsed: 0, totalDuration: 360, baseStrength: 5)
        #expect(r0.isStimulationActive)
        #expect(r0.commands.isEmpty)
        #expect(r0.effectiveStrength == 3)
        #expect(r0.statusText.contains("Easing"))

        let r2 = engine.tick(elapsed: 2, totalDuration: 360, baseStrength: 5)
        #expect(r2.commands == ["4\n"])
        #expect(r2.effectiveStrength == 4)

        let r4 = engine.tick(elapsed: 4, totalDuration: 360, baseStrength: 5)
        #expect(r4.commands == ["5\n"])

        for elapsed in [6, 60, 180, 359] {
            let result = engine.tick(elapsed: elapsed, totalDuration: 360, baseStrength: 5)
            #expect(result.isStimulationActive)
            #expect(result.commands.isEmpty)
            #expect(result.effectiveStrength == nil)
            #expect(result.statusText.contains("Continuous"))
        }
    }

    @Test("Low strength start has no soft-start")
    func lowStrengthNoSoftStart() {
        var engine = StressReliefEngine()
        let cmds = engine.start(baseStrength: 2, totalDuration: 360)
        #expect(cmds == ["D\n", "2\n"])
        let r = engine.tick(elapsed: 2, totalDuration: 360, baseStrength: 2)
        #expect(r.commands.isEmpty)
    }

    @Test("Late elapsed catches up — no undercut after soft window")
    func lateElapsedNoUndercut() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        // Simulate restore mid-session: first tick at elapsed=100
        let r = engine.tick(elapsed: 100, totalDuration: 360, baseStrength: 5)
        // May send one catch-up to 5, never below target
        for cmd in r.commands {
            #expect(cmd != "3\n")
            #expect(cmd != "4\n")
        }
        #expect(r.statusText.contains("Continuous") || r.commands.contains("5\n"))
        let r2 = engine.tick(elapsed: 102, totalDuration: 360, baseStrength: 5)
        #expect(r2.commands.isEmpty)
        #expect(r2.effectiveStrength == nil)
    }

    @Test("Reconnect during soft window continues ladder (no full spike)")
    func reconnectDuringSoftNoUndercut() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        // t=2: soft catch-up is 4 (initial 3 + 1 step) — not full 5
        let reconnect = engine.reconnectCommands(elapsed: 2, totalDuration: 360, baseStrength: 5)
        #expect(reconnect == ["D\n", "4\n"], "mid-soft reconnect ladder, cmds=\(reconnect)")
        let r = engine.tick(elapsed: 2, totalDuration: 360, baseStrength: 5)
        for cmd in r.commands {
            if let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)),
               (1...9).contains(n) {
                #expect(n >= 4, "must not undercut reconnect step, cmds=\(r.commands)")
            }
        }
    }

    @Test("User raise mid soft-start never undercuts raised value")
    func userRaiseMidSoftNoUndercut() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        engine.noteUserStrength(7, previousBase: nil)
        // Soft should stop; ticks must not send below 7
        for t in 0...10 {
            let r = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 7)
            for cmd in r.commands {
                #expect(cmd != "3\n")
                #expect(cmd != "4\n")
                #expect(cmd != "5\n")
                #expect(cmd != "6\n")
            }
        }
    }

    @Test("User lower mid soft-start stops ease (no thrash steps)")
    func userLowerMidSoftStopsEase() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 7, totalDuration: 360)
        // Soft at initial 5 for target 7
        _ = engine.tick(elapsed: 1, totalDuration: 360, baseStrength: 7)
        engine.noteUserStrength(4, previousBase: nil)
        // Soft disabled — must not climb 5→6→7 or thrash below 4
        for t in 2...12 {
            let r = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 4)
            #expect(!r.statusText.contains("Easing"), "t=\(t) status=\(r.statusText)")
            for cmd in r.commands {
                if let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)),
                   (1...9).contains(n) {
                    #expect(n == 4, "lowered floor only, cmds=\(r.commands)")
                }
            }
        }
    }

    @Test("Target drop mid soft never undercuts lastSent")
    func targetDropMidSoftNoUndercut() {
        var engine = StressReliefEngine()
        // target 7 → initial 5
        let start = engine.start(baseStrength: 7, totalDuration: 360)
        #expect(start.contains("5\n"))
        // Soft steps toward 7, then target drops to 3 without noteUserStrength
        _ = engine.tick(elapsed: 2, totalDuration: 360, baseStrength: 7)
        let r = engine.tick(elapsed: 4, totalDuration: 360, baseStrength: 3)
        for cmd in r.commands {
            #expect(cmd != "3\n")
            #expect(cmd != "4\n")
            // Must not send below what soft already reached
            if let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)) {
                #expect(n >= 5)
            }
        }
    }

    @Test("Reconnect sends bilateral activate and strength")
    func reconnect() {
        var engine = StressReliefEngine()
        let cmds = engine.reconnectCommands(elapsed: 100, totalDuration: 360, baseStrength: 7)
        #expect(cmds == ["D\n", "7\n"])
    }

    @Test("After pause, reconnect soft-starts for comfort")
    func pauseThenReconnectSoft() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        for t in 1...10 { _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5) }
        engine.notePaused()
        let cmds = engine.reconnectCommands(elapsed: 60, totalDuration: 360, baseStrength: 5)
        #expect(cmds == ["D\n", "3\n"], "Pause resume soft-starts, not full blast")
        // Settled mid-session reconnect without pause stays full
        var engine2 = StressReliefEngine()
        _ = engine2.start(baseStrength: 5, totalDuration: 360)
        for t in 1...10 { _ = engine2.tick(elapsed: t, totalDuration: 360, baseStrength: 5) }
        let full = engine2.reconnectCommands(elapsed: 60, totalDuration: 360, baseStrength: 5)
        #expect(full == ["D\n", "5\n"])
    }

    @Test("Mid soft-start BLE reconnect continues ladder not full spike")
    func midSoftReconnectContinuesLadder() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        // t=1 still at initial 3 (steps every 2s)
        _ = engine.tick(elapsed: 1, totalDuration: 360, baseStrength: 5)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("3\n"), "mid-soft reconnect stays on ladder, cmds=\(cmds)")
        #expect(!cmds.contains("5\n"), "must not spike to full mid soft, cmds=\(cmds)")
        // After soft complete, reconnect is full
        for t in 2...10 { _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5) }
        let settled = engine.reconnectCommands(elapsed: 20, totalDuration: 360, baseStrength: 5)
        #expect(settled == ["D\n", "5\n"])
    }

    @Test("Fresh engine without soft state reconnects full (no wall-elapsed rehydrate undercut)")
    func processKillMidSoftNoUndercutRehydrate() {
        // Soft state is in-memory; process kill → full reassert (safe vs undercutting user raise)
        var engine = StressReliefEngine()
        let cmds = engine.reconnectCommands(elapsed: 2, totalDuration: 360, baseStrength: 5)
        #expect(cmds == ["D\n", "5\n"])
        // User raise then reconnect must never rehydrate below raised
        var raised = StressReliefEngine()
        _ = raised.start(baseStrength: 5, totalDuration: 360)
        raised.noteUserStrength(7, previousBase: 5)
        let rcmds = raised.reconnectCommands(elapsed: 2, totalDuration: 360, baseStrength: 7)
        #expect(rcmds.contains("7\n"), "user raise must stick, cmds=\(rcmds)")
        #expect(!rcmds.contains("3\n") && !rcmds.contains("4\n") && !rcmds.contains("5\n") && !rcmds.contains("6\n"))
    }

    @Test("Soft snapshot restores mid soft ladder after kill")
    func softSnapshotRestoresLadder() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        _ = engine.tick(elapsed: 1, totalDuration: 360, baseStrength: 5)
        let snap = engine.softSnapshot()
        #expect(snap != nil)
        #expect(snap?.enabled == true)
        #expect(snap?.userTakenOver == false)
        #expect((snap?.lastSent ?? 0) >= 3)

        var restored = StressReliefEngine()
        restored.applySoftSnapshot(snap)
        let cmds = restored.reconnectCommands(elapsed: 2, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("D\n"))
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "soft ladder cmds=\(cmds)")
        #expect(nums.contains(where: { $0 <= 4 }), "restored soft ladder, cmds=\(cmds)")
        #expect(nums.allSatisfy { $0 < 5 }, "must not full-spike, cmds=\(cmds)")
    }

    @Test("Soft snapshot with user takeover reconnects at raised floor")
    func softSnapshotUserTakeover() {
        var engine = StressReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        engine.noteUserStrength(7, previousBase: 5)
        let snap = engine.softSnapshot()
        #expect(snap?.userTakenOver == true)
        #expect(snap?.lastSent == 7)

        var restored = StressReliefEngine()
        restored.applySoftSnapshot(snap)
        let cmds = restored.reconnectCommands(elapsed: 2, totalDuration: 360, baseStrength: 7)
        #expect(cmds.contains("7\n"), "takeover floor, cmds=\(cmds)")
        #expect(!cmds.contains("3\n"))
    }

    @Test("Sleep soft snapshot restores mid-soft ladder")
    func sleepSoftSnapshotRestores() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        let snap = engine.softSnapshot()
        #expect(snap != nil)
        #expect(snap?.enabled == true)
        #expect(snap?.lastSent == SoftStart.initialStrength(target: 5))

        var restored = SleepEngine()
        restored.applySoftSnapshot(snap)
        let cmds = restored.reconnectCommands(elapsed: 1, totalDuration: 600, baseStrength: 5)
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "sleep soft reconnect cmds=\(cmds)")
        #expect(nums.contains(where: { $0 <= 4 }), "soft ladder not full, cmds=\(cmds)")
        #expect(nums.allSatisfy { $0 < 5 }, "must not full-spike, cmds=\(cmds)")
    }

    @Test("Focus duty re-on soft snapshot restores local ladder")
    func focusDutySoftSnapshotRestores() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // First on 0–29 (soft settles), rest 30–59, re-on at 60 begins local soft
        for t in 1...60 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let snap = engine.softSnapshot()
        #expect(snap != nil, "duty re-on must open soft window")
        #expect(snap?.enabled == true)
        #expect(snap?.beginElapsed == 60)
        #expect(snap?.lastSent == SoftStart.initialStrength(target: 5))

        var restored = FocusEngine()
        restored.applySoftSnapshot(snap)
        // Mid duty soft at t=61 — ladder, not full spike
        let cmds = restored.reconnectCommands(elapsed: 61, totalDuration: 600, baseStrength: 5)
        #expect(cmds.contains("A\n"), "on-phase reconnect, cmds=\(cmds)")
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "duty soft cmds=\(cmds)")
        #expect(nums.contains(where: { $0 <= 4 }), "duty soft ladder, cmds=\(cmds)")
        #expect(nums.allSatisfy { $0 < 5 }, "must not full-spike duty soft, cmds=\(cmds)")
    }

    @Test("SoftStartSnapshot encodes and decodes for process kill")
    func softSnapshotCodableRoundTrip() throws {
        let snap = SoftStartSnapshot(
            enabled: true,
            userTakenOver: false,
            lastSent: 4,
            beginElapsed: 60
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SoftStartSnapshot.self, from: data)
        #expect(decoded == snap)
    }

    @Test("Pain engine exports soft snapshot while easing")
    func painSoftSnapshotWhileEasing() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        let snap = engine.softSnapshot()
        #expect(snap != nil)
        #expect(snap?.enabled == true)
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
    @Test("Start soft-starts two below target")
    func start() {
        var engine = SleepEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 600)
        #expect(cmds == ["D\n", "3\n"])
    }

    @Test("Soft-start eases then channel rotation continues")
    func softStartThenRotation() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        let r2 = engine.tick(elapsed: 2, totalDuration: 600, baseStrength: 5)
        #expect(r2.commands.contains("4\n") || r2.statusText.contains("Easing"))
        let r4 = engine.tick(elapsed: 4, totalDuration: 600, baseStrength: 5)
        // Soft completes by t=4 for target 5 — final step must land at full target
        #expect(r4.commands.contains("5\n") || !r4.isEasing,
                "soft should reach target or finish easing, cmds=\(r4.commands) status=\(r4.statusText)")
        // Late elapsed: no re-easing undercut
        let r100 = engine.tick(elapsed: 100, totalDuration: 600, baseStrength: 5)
        #expect(!r100.commands.contains("3\n"))
        #expect(!r100.commands.contains("4\n"))
        #expect(!r100.isEasing, "late sleep not easing")
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

    @Test("Extending total mid-session does not rewind channel phase")
    func extendDoesNotRewindPhase() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // Drive to phase 2 (elapsed 240, phaseLen 120 → phase 2 bilateral)
        for t in 1...240 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let mid = engine.tick(elapsed: 240, totalDuration: 600, baseStrength: 5)
        #expect(mid.activeChannel == .bilateral || mid.statusText.contains("Bilateral"))

        // User +60s → total 660; old formula phaseLen=132 → phase 1 (left) — must NOT rewind
        let after = engine.tick(elapsed: 240, totalDuration: 660, baseStrength: 5)
        #expect(!after.commands.contains("A\n"),
                "Extend must not rewind to left channel, cmds=\(after.commands) status=\(after.statusText)")
        #expect(after.activeChannel == .bilateral || after.statusText.contains("Bilateral"))
    }

    @Test("Extending total mid-fade does not re-raise strength")
    func extendMidFadeNoReraise() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let deep = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 5)
        #expect(deep.effectiveStrength == 3 || deep.effectiveStrength == nil)
        // +60s moves fade window later — must not send 4 or 5
        let after = engine.tick(elapsed: 540, totalDuration: 660, baseStrength: 5)
        #expect(!after.commands.contains("4\n"), "cmds=\(after.commands)")
        #expect(!after.commands.contains("5\n"), "cmds=\(after.commands)")
        if let eff = after.effectiveStrength {
            #expect(eff <= 3)
        }
    }

    @Test("Pause mid-fade soft-starts toward fade level not full base")
    func pauseMidFadeSoftCapsAtFade() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // Drive into deep fade (t=540 → fade 3)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        engine.notePaused()
        let cmds = engine.reconnectCommands(elapsed: 540, totalDuration: 600, baseStrength: 5)
        // Soft initial for target 3 is 1; never re-enter at 5
        #expect(!cmds.contains("5\n"), "Must not soft toward full base mid-fade, cmds=\(cmds)")
        #expect(!cmds.contains("4\n"), "Must not exceed fade 3, cmds=\(cmds)")
        // Strength command is ≤ 3
        let strengths = cmds.compactMap { cmd -> Int? in
            let t = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(t)
        }.filter { (1...9).contains($0) }
        #expect(!strengths.isEmpty, "must send strength, cmds=\(cmds)")
        #expect(strengths.allSatisfy { $0 <= 3 }, "cmds=\(cmds)")
    }

    @Test("Reconnect after extend mid-fade does not re-raise strength")
    func reconnectAfterExtendMidFadeNoReraise() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        // +60s moves raw fade later (would be 5) — reconnect must stay at faded 3
        let cmds = engine.reconnectCommands(elapsed: 540, totalDuration: 660, baseStrength: 5)
        #expect(!cmds.contains("5\n"), "Reconnect must not re-raise after extend, cmds=\(cmds)")
        #expect(!cmds.contains("4\n"), "Reconnect must not re-raise to shallow fade, cmds=\(cmds)")
        let strengths = cmds.compactMap { cmd -> Int? in
            Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!strengths.isEmpty, "must send strength, cmds=\(cmds)")
        #expect(strengths.allSatisfy { $0 <= 3 }, "cmds=\(cmds)")
    }

    @Test("User raise mid-fade is not undercut by next tick floor")
    func noteUserStrengthMidFadeNoUndercut() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        // User raises to 7 mid-fade — BLE already at 7 via setStrength
        engine.noteUserStrength(7, previousBase: nil)
        let after = engine.tick(elapsed: 541, totalDuration: 600, baseStrength: 7)
        #expect(!after.commands.contains("3\n"), "Must not undercut, cmds=\(after.commands)")
        #expect(!after.commands.contains("4\n"), "cmds=\(after.commands)")
        #expect(!after.commands.contains("5\n"), "Must not drop to raw fade after raise, cmds=\(after.commands)")
        // Hold user floor; nil effective means at base 7
        if let eff = after.effectiveStrength {
            #expect(eff >= 7, "effective=\(eff)")
        }
        let reconnect = engine.reconnectCommands(elapsed: 541, totalDuration: 600, baseStrength: 7)
        let strengths = reconnect.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(strengths.allSatisfy { $0 >= 7 }, "Reconnect must hold user floor, cmds=\(reconnect)")
    }

    @Test("Early setStrength does not freeze later auto-fade")
    func earlyRaiseStillFades() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...20 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        // Nudge intensity early (not yet faded)
        engine.noteUserStrength(6, previousBase: nil)
        for t in 21...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 6)
        }
        let deep = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 6)
        // Deep fade for base 6 → 4; must not stay locked at 6
        #expect(deep.effectiveStrength == 4 || deep.commands.contains("4\n")
                || (deep.effectiveStrength ?? 9) <= 4,
                "Early raise must not freeze fade, eff=\(String(describing: deep.effectiveStrength)) cmds=\(deep.commands)")
    }

    @Test("Soft resume after pause mid-fade does not re-raise above floor")
    func softResumeMidFadeNoReraise() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        engine.notePaused()
        // Extend then soft resume — must not climb toward raw 5
        _ = engine.reconnectCommands(elapsed: 540, totalDuration: 660, baseStrength: 5)
        for t in 541...550 {
            let r = engine.tick(elapsed: t, totalDuration: 660, baseStrength: 5)
            #expect(!r.commands.contains("5\n"), "t=\(t) cmds=\(r.commands)")
            #expect(!r.commands.contains("4\n"), "t=\(t) cmds=\(r.commands)")
            if let eff = r.effectiveStrength {
                #expect(eff <= 3, "t=\(t) eff=\(eff)")
            }
        }
    }

    @Test("Restored phase schedule survives total change")
    func restoreAnchorsKeepsPhaseLength() {
        var engine = SleepEngine()
        // Seed as if original session was 600s (phaseLen 120), mid-fade
        engine.restoreAnchors(
            phaseLengthSeconds: 120,
            lastComfortStrength: 3,
            sessionStrength: 5,
            elapsed: 540,
            totalDuration: 660,
            pinnedUserFloor: nil
        )
        // Fresh engine would use total/5=132 → phase 1 at t=240; anchored stays phase 2
        let r = engine.tick(elapsed: 240, totalDuration: 660, baseStrength: 5)
        #expect(!r.commands.contains("A\n"), "Anchored phase must not rewind to left")
        // Comfort floor from seed: mid-fade raw may be higher after extend
        let deep = engine.tick(elapsed: 540, totalDuration: 660, baseStrength: 5)
        #expect(!deep.commands.contains("5\n"), "Seeded fade floor must hold, cmds=\(deep.commands)")
        if let eff = deep.effectiveStrength {
            #expect(eff <= 3)
        }
    }

    @Test("Restore at full base pre-fade still auto-fades later")
    func restoreAtBaseStillFades() {
        var engine = SleepEngine()
        engine.restoreAnchors(
            phaseLengthSeconds: 120,
            lastComfortStrength: 5,
            sessionStrength: 5,
            elapsed: 100,
            totalDuration: 600,
            pinnedUserFloor: nil
        )
        _ = engine.reconnectCommands(elapsed: 100, totalDuration: 600, baseStrength: 5)
        for t in 101...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let deep = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 5)
        #expect(
            deep.effectiveStrength == 3
                || deep.commands.contains("3\n")
                || (deep.effectiveStrength ?? 9) <= 3,
            "Full-base restore must not freeze fade, eff=\(String(describing: deep.effectiveStrength)) cmds=\(deep.commands)"
        )
    }

    @Test("Restore mid soft-start does not freeze below base")
    func restoreMidSoftDoesNotFreeze() {
        var engine = SleepEngine()
        // Soft step would be 3 — settle-only no longer persists that; empty comfort
        engine.restoreAnchors(
            phaseLengthSeconds: 120,
            lastComfortStrength: nil,
            sessionStrength: 5,
            elapsed: 2,
            totalDuration: 600,
            pinnedUserFloor: nil
        )
        let cmds = engine.reconnectCommands(elapsed: 2, totalDuration: 600, baseStrength: 5)
        #expect(cmds.contains("5\n"), "cmds=\(cmds)")
        for t in 2...20 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let mid = engine.tick(elapsed: 20, totalDuration: 600, baseStrength: 5)
        #expect(mid.effectiveStrength == nil || mid.effectiveStrength == 5,
                "Must reach full base after soft restore, eff=\(String(describing: mid.effectiveStrength))")
    }

    @Test("Restore after fade+extend keeps floor (not live fade window)")
    func restoreAfterExtendKeepsFadeFloor() {
        var engine = SleepEngine()
        // Settled fade 3, then total extended so elapsed is no longer in last 20%
        engine.restoreAnchors(
            phaseLengthSeconds: 120,
            lastComfortStrength: 3,
            sessionStrength: 5,
            elapsed: 540,
            totalDuration: 900,
            pinnedUserFloor: nil
        )
        let cmds = engine.reconnectCommands(elapsed: 540, totalDuration: 900, baseStrength: 5)
        let strengths = cmds.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(strengths.allSatisfy { $0 <= 3 }, "Extend-out-of-window restore must hold floor, cmds=\(cmds)")
    }

    @Test("Restore mid-fade user raise holds pin")
    func restoreUserRaiseMidFadeHolds() {
        var engine = SleepEngine()
        engine.restoreAnchors(
            phaseLengthSeconds: 120,
            lastComfortStrength: 7,
            sessionStrength: 7,
            elapsed: 540,
            totalDuration: 600,
            pinnedUserFloor: 7
        )
        let cmds = engine.reconnectCommands(elapsed: 540, totalDuration: 600, baseStrength: 7)
        let strengths = cmds.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(strengths.allSatisfy { $0 >= 7 }, "User pin must hold, cmds=\(cmds)")
    }

    @Test("Reconnect returns correct channel for phase")
    func reconnect() {
        var engine = SleepEngine()
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
    @Test("Start soft-starts two below target on left channel")
    func start() {
        var engine = FocusEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 360)
        #expect(cmds == ["A\n", "3\n"])
    }

    @Test("Soft-start first on-window including final step")
    func softStartFirstOn() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        let r2 = engine.tick(elapsed: 2, totalDuration: 360, baseStrength: 5)
        #expect(r2.commands.contains("4\n"))
        let r4 = engine.tick(elapsed: 4, totalDuration: 360, baseStrength: 5)
        #expect(r4.commands.contains("5\n"))
        let r10 = engine.tick(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(r10.isStimulationActive)
        #expect(r10.effectiveStrength == nil)
    }

    @Test("30s on / 30s off duty cycling — re-on soft-starts for comfort")
    func dutyCycle() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        // t=0-29: on phase (finish soft-start)
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

        // t=60: on again — soft re-entry (not full 5) for comfort
        let r60 = engine.tick(elapsed: 60, totalDuration: 360, baseStrength: 5)
        #expect(r60.isStimulationActive)
        #expect(r60.commands.contains("A\n"))
        #expect(r60.commands.contains("3\n"), "Duty re-on soft-starts at initial")
        #expect(!r60.commands.contains("5\n"), "Must not jump to full target on re-on")
        #expect(r60.statusText.contains("Easing"))

        // Soft steps during second on-window
        let r62 = engine.tick(elapsed: 62, totalDuration: 360, baseStrength: 5)
        #expect(r62.commands.contains("4\n") || r62.effectiveStrength == 4)
        let r64 = engine.tick(elapsed: 64, totalDuration: 360, baseStrength: 5)
        #expect(r64.commands.contains("5\n") || r64.effectiveStrength == nil)
    }

    @Test("Constant intensity after soft re-entry completes")
    func constantIntensity() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)

        // Through rest into third on-window, then past soft re-entry steps
        for t in 1...184 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5)
        }

        // t=185: mid on-window after soft complete — no under/overshoot steps
        let r = engine.tick(elapsed: 185, totalDuration: 360, baseStrength: 5)
        #expect(r.isStimulationActive)
        #expect(!r.commands.contains("6\n"))
        #expect(!r.commands.contains("3\n"))
        #expect(!r.commands.contains("4\n"))
    }

    @Test("Settled mid-session reconnect on-phase is full (no soft re-ease)")
    func reconnectDuringSoftNoUndercut() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        for t in 1...10 { _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5) }
        let reconnect = engine.reconnectCommands(elapsed: 10, totalDuration: 360, baseStrength: 5)
        // Soft complete by t=10 — full target
        #expect(reconnect.contains("A\n"))
        #expect(reconnect.contains("5\n"))
        #expect(!reconnect.contains("6\n"))
    }

    @Test("Focus mid soft-start reconnect continues ladder")
    func focusMidSoftReconnectContinuesLadder() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        _ = engine.tick(elapsed: 1, totalDuration: 360, baseStrength: 5)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("3\n"), "mid-soft Focus reconnect stays on ladder, cmds=\(cmds)")
        #expect(!cmds.contains("5\n"))
    }

    @Test("Reconnect during off phase sends deactivate")
    func reconnectOffPhase() {
        var engine = FocusEngine()
        // t=35: off phase (35%60=35 >= 30)
        let cmds = engine.reconnectCommands(elapsed: 35, totalDuration: 360, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Reconnect during on phase is full without pause")
    func reconnectOnPhase() {
        var engine = FocusEngine()
        // t=10: on phase (10%60=10 < 30)
        let cmds = engine.reconnectCommands(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("5\n"), "Full reassert without pause")
    }

    @Test("After pause, reconnect on-phase soft-starts for comfort")
    func pauseThenReconnectSoft() {
        var engine = FocusEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        for t in 1...10 { _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 5) }
        engine.notePaused()
        let cmds = engine.reconnectCommands(elapsed: 10, totalDuration: 360, baseStrength: 5)
        #expect(cmds.contains("A\n"))
        #expect(cmds.contains("3\n"), "Pause resume soft-starts")
        #expect(!cmds.contains("5\n"))
    }

    @Test("Reconnect after midpoint is full without pause")
    func reconnectAfterMidpoint() {
        var engine = FocusEngine()
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
    @Test("Start soft-starts two below target")
    func start() {
        var engine = PainReliefEngine()
        let cmds = engine.start(baseStrength: 5, totalDuration: 480)
        #expect(cmds == ["D\n", "3\n"])
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

    @Test("Sine wave produces ±1 oscillation after soft-start")
    func sineOscillation() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 480)
        // Finish soft-start (t=0..4)
        for t in 0...5 {
            _ = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 5)
        }

        // Collect all effective strengths over one 30s period after ease-in
        var strengths = Set<Int>()
        for t in 6...36 {
            let r = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 5)
            let s = r.effectiveStrength ?? 5
            strengths.insert(s)
        }

        // Should see values of 4, 5, and 6 (base ±1)
        #expect(strengths.contains(4) || strengths.contains(6))
    }

    @Test("Soft-start freezes sine until complete — no same-tick jump to base±1")
    func softStartThenSine() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 480)
        let r0 = engine.tick(elapsed: 0, totalDuration: 480, baseStrength: 5)
        #expect(r0.statusText.contains("Easing"))
        let r2 = engine.tick(elapsed: 2, totalDuration: 480, baseStrength: 5)
        #expect(r2.commands.contains("4\n") || r2.effectiveStrength == 4)
        let r4 = engine.tick(elapsed: 4, totalDuration: 480, baseStrength: 5)
        #expect(r4.commands.contains("5\n"), "Final soft step reaches target")
        #expect(!r4.commands.contains("6\n"), "Must not also enqueue sine jump same tick")
        #expect(!r4.commands.contains("4\n"))
        // Next ticks should apply wave once offset leaves 0 (lastOffset seeded to 0)
        var sawWave = false
        for t in 5...20 {
            let r = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 5)
            if r.commands.contains("6\n") || r.commands.contains("4\n") {
                sawWave = true
                break
            }
        }
        #expect(sawWave, "Sine must apply after handoff when lastOffset seeded to 0")
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
        var engine = PainReliefEngine()
        let cmds = engine.reconnectCommands(elapsed: 100, totalDuration: 480, baseStrength: 5)
        #expect(cmds.first == "D\n")
        #expect(cmds.count == 2)
    }

    @Test("setStrength mid-wave reasserts even when sine offset unchanged")
    func setStrengthReassertsWaveLevel() {
        var engine = PainReliefEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 480)
        // Past soft into wave
        for t in 0...20 {
            _ = engine.tick(elapsed: t, totalDuration: 480, baseStrength: 5)
        }
        // Hold at same phase — tick may emit nothing when offset stable
        _ = engine.tick(elapsed: 21, totalDuration: 480, baseStrength: 5)
        // User raises base; next tick must reassert even if sine offset same
        engine.noteUserStrength(7, previousBase: nil)
        let r = engine.tick(elapsed: 21, totalDuration: 480, baseStrength: 7)
        let strengths = r.commands.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(!strengths.isEmpty || r.effectiveStrength != nil,
                "Must reassert wave after setStrength, cmds=\(r.commands) eff=\(String(describing: r.effectiveStrength))")
        if let s = strengths.first {
            #expect(s >= 6 && s <= 8, "base 7 ±1 wave, got \(s)")
        } else if let eff = r.effectiveStrength {
            #expect(eff >= 6 && eff <= 8)
        }
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

    @Test("Start sends absolute off (inhale begins, prior stim cleared)")
    func start() {
        var engine = CalmEngine.make()
        let cmds = engine.start(baseStrength: 5, totalDuration: 300)
        #expect(cmds == ["0\n"])
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
        var engine = CalmEngine.make()
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
        var engine = CalmEngine.make()
        // t=1: early inhale (1%17=1 < 3 ramp start)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 300, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Reconnect at cycle boundary sends deactivate")
    func reconnectCycleBoundary() {
        var engine = CalmEngine.make()
        // t=17: cycle reset (17%17=0, early inhale before ramp lead)
        let cmds = engine.reconnectCommands(elapsed: 17, totalDuration: 300, baseStrength: 5)
        #expect(cmds == ["0\n"])
    }

    @Test("Reconnect mid-exhale syncs wasStimulating — no double activate")
    func reconnectSyncsWasStimulating() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)
        // Tick through early inhale (off)
        _ = engine.tick(elapsed: 1, totalDuration: 300, baseStrength: 5)
        // Reconnect mid-exhale (stimulating)
        _ = engine.reconnectCommands(elapsed: 12, totalDuration: 300, baseStrength: 5)
        let r = engine.tick(elapsed: 12, totalDuration: 300, baseStrength: 5)
        #expect(r.isStimulationActive)
        #expect(!r.commands.contains("D\n"))
        #expect(!r.commands.contains("5\n"))
    }

    @Test("Short stall across early-inhale off absolute-reasserts off")
    func shortStallSkipsInhaleOffStillSendsAbsolute() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)
        // Establish mid-cycle stim, then jump over early inhale off into next window
        for t in 1...14 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }
        let mid = engine.tick(elapsed: 14, totalDuration: 300, baseStrength: 5)
        #expect(mid.isStimulationActive, "t=14 should be stim-on for calm cycle")
        let r = engine.tick(elapsed: 18, totalDuration: 300, baseStrength: 5)
        // Early inhale after cycle wrap must be off — absolute path includes 0
        #expect(!r.isStimulationActive || r.commands.contains("0\n"),
                "Must not stay on through skipped early inhale, cmds=\(r.commands) status=\(r.statusText)")
        if !r.isStimulationActive {
            #expect(r.commands.contains("0\n") || r.activeChannel == .off)
        }
    }

    @Test("Stall over early inhale that lands in stim still sends off first")
    func stallOverInhaleOffLandsInStimSendsOffFirst() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)
        for t in 1...15 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }
        // t=15 is stim. t=20 is stim. t=17…19 are early-inhale off.
        let r = engine.tick(elapsed: 20, totalDuration: 300, baseStrength: 5)
        #expect(r.isStimulationActive)
        let off = r.commands.firstIndex(of: "0\n")
        let on = r.commands.firstIndex(of: "D\n")
        #expect(off != nil, "skipped inhale off must deactivate, cmds=\(r.commands)")
        #expect(on != nil, "landing in stim must reassert on, cmds=\(r.commands)")
        if let off, let on {
            #expect(off < on, "off before on, cmds=\(r.commands)")
        }
    }

    @Test("Headache soft snapshot restores mid-soft ladder")
    func headacheSoftSnapshotRestores() {
        var engine = HeadacheEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 360)
        let snap = engine.softSnapshot()
        #expect(snap != nil)
        #expect(snap?.enabled == true)
        var restored = HeadacheEngine()
        restored.applySoftSnapshot(snap)
        let cmds = restored.reconnectCommands(elapsed: 1, totalDuration: 360, baseStrength: 5)
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "reconnect should send strength, cmds=\(cmds)")
        #expect(nums.contains(where: { $0 < 5 }), "soft ladder not full spike, cmds=\(cmds)")
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

    @Test("Display names avoid outcome-claim wording")
    func wellnessDisplayNames() {
        for mode in StimulationMode.allCases {
            #expect(!mode.name.localizedCaseInsensitiveContains("Relief"),
                    "\(mode.rawValue) name=\(mode.name)")
            #expect(!mode.summary.localizedCaseInsensitiveContains("stimulation"),
                    "\(mode.rawValue) summary uses stimulation")
            #expect(!mode.evidenceLevel.localizedCaseInsensitiveContains("clinically"),
                    "\(mode.rawValue) evidenceLevel")
            #expect(!mode.evidenceLevel.localizedCaseInsensitiveContains("treats"),
                    "\(mode.rawValue) evidenceLevel")
        }
        #expect(StimulationMode.stressRelief.name == "Stress")
        #expect(StimulationMode.painRelief.name == "Ease")
        #expect(StimulationMode.calm.name == "Breathe")
        // Legacy surface names still wellness-safe
        #expect(StimulationMode.headache.name == "Ease burst")
        #expect(StimulationMode.nausea.name == "Stress")
        #expect(StimulationMode.stressRelief.evidenceLevel.contains("Pattern"))
    }

    @Test("BLE restore identifier is stable and namespaced")
    func bleRestoreIdentifier() {
        #expect(BLEConstants.centralRestoreIdentifier.contains("OpenPulse"))
        #expect(BLEConstants.centralRestoreIdentifier.hasPrefix("io.github.stefanpenner"))
    }

    @Test("Edge modes flag background honesty")
    func edgeHonestyFlags() {
        #expect(StimulationMode.focus.needsBackgroundEdgeHonesty)
        #expect(StimulationMode.calm.needsBackgroundEdgeHonesty)
        #expect(StimulationMode.sleep.needsBackgroundEdgeHonesty)
        #expect(StimulationMode.painRelief.needsBackgroundEdgeHonesty)
        #expect(!StimulationMode.stressRelief.needsBackgroundEdgeHonesty)
        #expect(!StimulationMode.custom.needsBackgroundEdgeHonesty)
    }

    @Test("Lowering mid-fade pins user floor")
    func lowerMidFadePinsFloor() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        // Deep fade ~3; user lowers to 2
        engine.noteUserStrength(2, previousBase: nil)
        #expect(engine.pinnedUserStrengthFloor() == 2)
        let after = engine.tick(elapsed: 541, totalDuration: 600, baseStrength: 2)
        if let eff = after.effectiveStrength {
            #expect(eff >= 2)
        }
        let reconnect = engine.reconnectCommands(elapsed: 541, totalDuration: 600, baseStrength: 2)
        let strengths = reconnect.compactMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        #expect(strengths.allSatisfy { $0 >= 2 }, "cmds=\(reconnect)")
    }

    @Test("Matching current comfort mid-fade does not pin (protocol may deepen)")
    func sameComfortDoesNotPin() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        // Shallow fade ~4
        for t in 1...480 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let shallow = engine.tick(elapsed: 480, totalDuration: 600, baseStrength: 5)
        let comfort = shallow.effectiveStrength ?? 4
        // Engine-only match without lowering base — deepen still allowed
        engine.noteUserStrength(comfort, previousBase: nil)
        #expect(engine.pinnedUserStrengthFloor() == 0, "Match comfort must not freeze deeper fade")
        for t in 481...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let deep = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 5)
        #expect(
            deep.effectiveStrength == 3
                || deep.commands.contains("3\n")
                || (deep.effectiveStrength ?? 9) <= 3,
            "Protocol must deepen after unpinned match, deep=\(String(describing: deep.effectiveStrength))"
        )
    }

    @Test("Lowering base to match comfort holds (no same-tick undercut)")
    func lowerBaseToMatchComfortHolds() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...480 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let shallow = engine.tick(elapsed: 480, totalDuration: 600, baseStrength: 5)
        let comfort = shallow.effectiveStrength ?? 4
        // VM setStrength path: previousBase 5 → new base = comfort
        engine.noteUserStrength(comfort, previousBase: 5)
        #expect(engine.pinnedUserStrengthFloor() == comfort)
        let after = engine.tick(elapsed: 480, totalDuration: 600, baseStrength: comfort)
        if let eff = after.effectiveStrength {
            #expect(eff >= comfort, "Must not undercut matched comfort same tick, eff=\(eff)")
        }
        #expect(!after.commands.contains("\(comfort - 1)\n") || comfort <= 1)
    }

    @Test("Partial base lower mid-fade does not re-raise felt comfort")
    func partialBaseLowerDoesNotReraiseFelt() {
        var engine = SleepEngine()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...540 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        let deep = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 5)
        let felt = deep.effectiveStrength ?? 3
        // User slides base 5→4 while felt is 3 — must not jump BLE to 4
        engine.noteUserStrength(4, previousBase: 5)
        #expect(engine.pinnedUserStrengthFloor() == felt)
        let after = engine.tick(elapsed: 540, totalDuration: 600, baseStrength: 4)
        if let eff = after.effectiveStrength {
            #expect(eff <= felt + 0, "Must not re-raise felt, felt=\(felt) eff=\(eff)")
            #expect(eff <= 3)
        }
        #expect(!after.commands.contains("4\n"), "cmds=\(after.commands)")
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
        #expect(!StimulationMode.learn.usesBreathingGuide)
    }

    @Test("Learn mode uses Focus engine duty cycle with soft-start")
    func learnUsesFocusEngine() {
        #expect(StimulationMode.learn.makeEngine() != nil)
        #expect(StimulationMode.learn.defaultDurationMinutes == 10)
        var engine = StimulationMode.learn.makeEngine()!
        let cmds = engine.start(baseStrength: 5, totalDuration: 600)
        #expect(cmds == ["A\n", "3\n"])
    }

    @Test("Sleep duration presets include longer rest windows")
    func sleepDurationPresets() {
        #expect(StimulationMode.sleep.durationPresets == [10, 20, 30])
        #expect(StimulationMode.meditation.durationPresets.contains(15))
        #expect(StimulationMode.stressRelief.durationPresets == [4, 6, 10])
        #expect(StimulationMode.calm.durationPresets.contains(4))
    }

    @Test("Duration wheel: Sleep is 5-minute steps")
    func durationWheelSleepSteps() {
        let vals = SessionDurationOptions.wheelMinutes(for: .sleep)
        #expect(vals.first == 5)
        #expect(vals.contains(10))
        #expect(vals.contains(30))
        #expect(vals.contains(60))
        #expect(vals.allSatisfy { $0 % 5 == 0 })
        #expect(!vals.contains(7))
    }

    @Test("Duration wheel: short range 1-min then 5-min steps")
    func durationWheelHybridSteps() {
        let vals = SessionDurationOptions.wheelMinutes(for: .stressRelief)
        #expect(vals.contains(1))
        #expect(vals.contains(7))
        #expect(vals.contains(15))
        #expect(vals.contains(20))
        #expect(!vals.contains(17), "past 15 only 5-min steps")
        #expect(vals.last == BLEConstants.maxSessionMinutes)
    }

    @Test("Duration wheel snaps off-grid minutes")
    func durationWheelSnap() {
        #expect(SessionDurationOptions.snap(7, for: .sleep) == 5
            || SessionDurationOptions.snap(7, for: .sleep) == 10)
        #expect(SessionDurationOptions.snap(6, for: .stressRelief) == 6)
        #expect(SessionDurationOptions.snap(17, for: .stressRelief) == 15
            || SessionDurationOptions.snap(17, for: .stressRelief) == 20)
        #expect(SessionDurationOptions.isPreset(6, for: .stressRelief))
        #expect(!SessionDurationOptions.isPreset(7, for: .stressRelief))
    }

    @Test("Comfort copy is wellness soft-start language")
    func softStartComfortCopy() {
        let copy = SessionDurationOptions.softStartComfortHint
        #expect(copy.localizedCaseInsensitiveContains("comfortable")
            || copy.localizedCaseInsensitiveContains("low"))
        #expect(copy.localizedCaseInsensitiveContains("eases"))
        #expect(!copy.localizedCaseInsensitiveContains("treat"))
        #expect(!copy.localizedCaseInsensitiveContains("clinical"))
    }

    @Test("Active intensity a11y is honest about easing")
    func activeIntensityAccessibilityEasing() {
        #expect(
            SessionDurationOptions.activeIntensityAccessibility(effective: 0, target: 5)
                == "Intensity off"
        )
        #expect(
            SessionDurationOptions.activeIntensityAccessibility(effective: 3, target: 5)
                .localizedCaseInsensitiveContains("easing")
        )
        #expect(
            SessionDurationOptions.activeIntensityAccessibility(effective: 5, target: 5)
                == "Active intensity 5"
        )
        #expect(
            !SessionDurationOptions.activeIntensityAccessibility(effective: 3, target: 5)
                .localizedCaseInsensitiveContains("treat")
        )
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
    @Test("Start soft-starts two below target")
    func start() {
        var engine = HeadacheEngine()
        let cmds = engine.start(baseStrength: 7, totalDuration: 360)
        #expect(cmds == ["D\n", "5\n"])
    }

    @Test("Soft-start steps through to full target including final step")
    func softStartFinalStep() {
        var engine = HeadacheEngine()
        _ = engine.start(baseStrength: 7, totalDuration: 360)
        let r2 = engine.tick(elapsed: 2, totalDuration: 360, baseStrength: 7)
        #expect(r2.commands.contains("6\n"))
        let r4 = engine.tick(elapsed: 4, totalDuration: 360, baseStrength: 7)
        #expect(r4.commands.contains("7\n"), "Final soft step must reach target")
        let r10 = engine.tick(elapsed: 10, totalDuration: 360, baseStrength: 7)
        #expect(r10.isStimulationActive)
        #expect(r10.effectiveStrength == nil)
    }

    @Test("Mid-session reconnect during burst is full (no soft re-ease)")
    func reconnectDuringSoftNoUndercut() {
        var engine = HeadacheEngine()
        _ = engine.start(baseStrength: 7, totalDuration: 360)
        for t in 1...10 { _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 7) }
        let reconnect = engine.reconnectCommands(elapsed: 10, totalDuration: 360, baseStrength: 7)
        #expect(reconnect.contains("D\n"))
        #expect(reconnect.contains("7\n"), "Full reassert without pause")
        #expect(!reconnect.contains("8\n"))
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

        // t=150: back on — soft re-entry (not full 7)
        let r150 = engine.tick(elapsed: 150, totalDuration: 360, baseStrength: 7)
        #expect(r150.isStimulationActive)
        #expect(r150.commands.contains("D\n"))
        #expect(r150.commands.contains("5\n"), "Burst re-on soft-starts at initial")
        #expect(!r150.commands.contains("7\n"))
        #expect(r150.statusText.contains("Easing"))
    }

    @Test("Reconnect during burst is full without pause")
    func reconnectBurst() {
        var engine = HeadacheEngine()
        let cmds = engine.reconnectCommands(elapsed: 60, totalDuration: 360, baseStrength: 7)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("7\n"), "Full reassert without pause")
    }

    @Test("After pause, reconnect during burst soft-starts for comfort")
    func pauseThenReconnectSoft() {
        var engine = HeadacheEngine()
        _ = engine.start(baseStrength: 7, totalDuration: 360)
        for t in 1...10 { _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 7) }
        engine.notePaused()
        let cmds = engine.reconnectCommands(elapsed: 60, totalDuration: 360, baseStrength: 7)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("5\n"), "Soft initial (target 7 → 5)")
        #expect(!cmds.contains("7\n"))
    }

    @Test("After pause, Calm reconnect soft-starts for comfort")
    func calmPauseThenReconnectSoft() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)
        // Drive into stim-on (exhale ~t=12)
        for t in 1...12 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }
        engine.notePaused()
        // Reconnect mid stim phase after pause — soft ladder, not full 5
        let cmds = engine.reconnectCommands(elapsed: 12, totalDuration: 300, baseStrength: 5)
        #expect(cmds.contains("D\n"))
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "cmds=\(cmds)")
        #expect(nums.contains(SoftStart.initialStrength(target: 5)), "soft initial, cmds=\(cmds)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike after pause, cmds=\(cmds)")
    }

    @Test("Calm mid-session reconnect without pause is full reassert")
    func calmReconnectWithoutPauseFull() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)
        for t in 1...12 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }
        // No notePaused — mid-session BLE drop stays full phase reassert
        let cmds = engine.reconnectCommands(elapsed: 12, totalDuration: 300, baseStrength: 5)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("5\n"), "full reassert without pause, cmds=\(cmds)")
    }

    @Test("Calm soft snapshot restores mid-soft ladder after pause window")
    func calmSoftSnapshotRestoresLadder() {
        var engine = CalmEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 300)
        for t in 1...12 {
            _ = engine.tick(elapsed: t, totalDuration: 300, baseStrength: 5)
        }
        engine.notePaused()
        // Open soft on reconnect, export, rehydrate
        _ = engine.reconnectCommands(elapsed: 12, totalDuration: 300, baseStrength: 5)
        let snap = engine.softSnapshot()
        #expect(snap != nil)
        #expect(snap?.enabled == true)
        var restored = CalmEngine.make()
        restored.applySoftSnapshot(snap)
        let cmds = restored.reconnectCommands(elapsed: 12, totalDuration: 300, baseStrength: 5)
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "Calm soft reconnect cmds=\(cmds)")
        #expect(nums.contains(where: { $0 < 5 }), "soft ladder not full spike, cmds=\(cmds)")
        #expect(nums.allSatisfy { $0 < 5 }, "cmds=\(cmds)")
    }

    @Test("After pause, Meditation reconnect soft-starts for comfort")
    func meditationPauseThenReconnectSoft() {
        var engine = MeditationEngine.make()
        _ = engine.start(baseStrength: 5, totalDuration: 600)
        for t in 1...12 {
            _ = engine.tick(elapsed: t, totalDuration: 600, baseStrength: 5)
        }
        engine.notePaused()
        let cmds = engine.reconnectCommands(elapsed: 12, totalDuration: 600, baseStrength: 5)
        #expect(cmds.contains("D\n"))
        let nums = cmds.compactMap {
            Int($0.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { (1...9).contains($0) }
        #expect(!nums.isEmpty, "cmds=\(cmds)")
        #expect(nums.contains(SoftStart.initialStrength(target: 5)), "soft initial, cmds=\(cmds)")
        #expect(nums.allSatisfy { $0 < 5 }, "no full spike after pause, cmds=\(cmds)")
    }

    @Test("Reconnect during pause sends deactivate")
    func reconnectPause() {
        var engine = HeadacheEngine()
        // t=130: pause (130%150=130 >= 120)
        let cmds = engine.reconnectCommands(elapsed: 130, totalDuration: 360, baseStrength: 7)
        #expect(cmds == ["0\n"])
    }

    @Test("Reconnect syncs wasOn — next tick does not re-fire on edge")
    func reconnectSyncsWasOn() {
        var engine = HeadacheEngine()
        _ = engine.start(baseStrength: 7, totalDuration: 360)
        // Drive into pause so wasOn becomes false
        for t in 0...130 {
            _ = engine.tick(elapsed: t, totalDuration: 360, baseStrength: 7)
        }
        // Reconnect mid-burst
        _ = engine.reconnectCommands(elapsed: 60, totalDuration: 360, baseStrength: 7)
        let r = engine.tick(elapsed: 60, totalDuration: 360, baseStrength: 7)
        #expect(r.isStimulationActive)
        // wasOn synced — no second activate/strength edge
        #expect(!r.commands.contains("D\n"))
        #expect(!r.commands.contains("7\n"))
    }
}

// MARK: - Meditation Engine Tests

@Suite("MeditationEngine")
struct MeditationEngineTests {
    // 14s cycle: 5s inhale + 4s hold + 5s exhale (no rest)
    // Ramp lead = 2s: BLE activate fires at t=3 (during late inhale)

    @Test("Start sends absolute off (inhale begins, prior stim cleared)")
    func start() {
        var engine = MeditationEngine.make()
        let cmds = engine.start(baseStrength: 4, totalDuration: 600)
        #expect(cmds == ["0\n"])
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
        var engine = MeditationEngine.make()
        // t=10: exhale (10%14=10, >= 3 ramp start, < 14 stim end)
        let cmds = engine.reconnectCommands(elapsed: 10, totalDuration: 600, baseStrength: 4)
        #expect(cmds.contains("D\n"))
        #expect(cmds.contains("4\n"))
    }

    @Test("Reconnect during early inhale sends deactivate")
    func reconnectInhale() {
        var engine = MeditationEngine.make()
        // t=1: early inhale (1%14=1 < 3 ramp start)
        let cmds = engine.reconnectCommands(elapsed: 1, totalDuration: 600, baseStrength: 4)
        #expect(cmds == ["0\n"])
    }
}

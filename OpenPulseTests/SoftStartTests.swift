import Foundation
import UserNotifications
import Testing
@testable import OpenPulse

@Suite("StrengthPresentation")
struct StrengthPresentationTests {
    @Test("Clamp and nudge stay in 1…9")
    func clampAndNudge() {
        #expect(StrengthPresentation.clamp(0) == 1)
        #expect(StrengthPresentation.clamp(99) == 9)
        #expect(StrengthPresentation.nudge(5, by: 1) == 6)
        #expect(StrengthPresentation.nudge(9, by: 1) == 9)
        #expect(StrengthPresentation.nudge(1, by: -1) == 1)
        #expect(StrengthPresentation.canIncrease(8))
        #expect(!StrengthPresentation.canIncrease(9))
        #expect(StrengthPresentation.canDecrease(2))
        #expect(!StrengthPresentation.canDecrease(1))
    }

    @Test("Island intensity nudge only during live session")
    func showsLiveActivityNudge() {
        #expect(StrengthPresentation.showsLiveActivityNudge(isPaused: false, remainingSeconds: 60))
        #expect(StrengthPresentation.showsLiveActivityNudge(isPaused: true, remainingSeconds: 0))
        #expect(!StrengthPresentation.showsLiveActivityNudge(isPaused: false, remainingSeconds: 0))
    }
}

@Suite("StrengthWritePolicy")
struct StrengthWritePolicyTests {
    @Test("Tick with strength omits absolute base (no base-then-wave spike)")
    func tickOwnsStrength() {
        let tick = ["D\n", "6\n"]
        let cmds = StrengthWritePolicy.bleCommands(userBase: 7, tickCommands: tick)
        #expect(cmds == tick)
        #expect(!cmds.contains("7\n"))
    }

    @Test("Tick without strength appends absolute base after channel")
    func baseWhenTickSilent() {
        let tick = ["D\n"]
        let cmds = StrengthWritePolicy.bleCommands(userBase: 7, tickCommands: tick)
        #expect(cmds == ["D\n", "7\n"])
    }

    @Test("Empty tick is absolute base only")
    func emptyTickBaseOnly() {
        #expect(StrengthWritePolicy.bleCommands(userBase: 5, tickCommands: []) == ["5\n"])
    }

    @Test("Deactivate 0 is not strength — base still written after off")
    func deactivateIsNotStrength() {
        let tick = ["0\n"]
        let cmds = StrengthWritePolicy.bleCommands(userBase: 7, tickCommands: tick)
        #expect(cmds == ["0\n", "7\n"])
        #expect(StrengthWritePolicy.containsStrengthCommand(["0\n"]) == false)
        #expect(StrengthWritePolicy.containsStrengthCommand(["A\n"]) == false)
        #expect(StrengthWritePolicy.containsStrengthCommand(["5\n"]) == true)
    }

    @Test("Channel-only tick gets base after channel")
    func channelOnlyBaseAfter() {
        let cmds = StrengthWritePolicy.bleCommands(userBase: 6, tickCommands: ["A\n"])
        #expect(cmds == ["A\n", "6\n"])
    }
}

@Suite("SoftStart")
struct SoftStartTests {
    @Test("Initial is target when strength is low")
    func lowTargetNoStep() {
        #expect(SoftStart.initialStrength(target: 1) == 1)
        #expect(SoftStart.initialStrength(target: 2) == 2)
        #expect(!SoftStart.isNeeded(target: 2))
    }

    @Test("Initial is two below target when strength ≥ 3")
    func highTargetSteps() {
        #expect(SoftStart.initialStrength(target: 5) == 3)
        #expect(SoftStart.initialStrength(target: 9) == 7)
        #expect(SoftStart.isNeeded(target: 5))
    }

    @Test("Elapsed-aware catch-up reaches target without re-easing")
    func elapsedCatchUp() {
        // target 5: 3 @ t0, 4 @ t2, 5 @ t4+
        #expect(SoftStart.strength(atElapsed: 0, target: 5) == 3)
        #expect(SoftStart.strength(atElapsed: 2, target: 5) == 4)
        #expect(SoftStart.strength(atElapsed: 4, target: 5) == 5)
        #expect(SoftStart.strength(atElapsed: 100, target: 5) == 5)
        #expect(SoftStart.isComplete(elapsed: 4, target: 5))
        #expect(!SoftStart.isComplete(elapsed: 2, target: 5))
    }
}

@Suite("SessionEndNotifier")
struct SessionEndNotifierTests {
    @Test("Body is wellness-framed and includes mode name")
    func bodyCopy() {
        let body = SessionEndNotifier.body(modeName: "Stress")
        #expect(body.contains("Stress"))
        #expect(body.localizedCaseInsensitiveContains("finished")
            || body.localizedCaseInsensitiveContains("complete"))
        #expect(!body.localizedCaseInsensitiveContains("treat"))
        #expect(!body.localizedCaseInsensitiveContains("clinical"))
    }

    @Test("Empty mode name still produces a body")
    func emptyModeBody() {
        let body = SessionEndNotifier.body(modeName: "  ")
        #expect(!body.isEmpty)
        #expect(body.localizedCaseInsensitiveContains("session"))
    }

    @Test("Title is short and non-medical")
    func titleCopy() {
        let t = SessionEndNotifier.title()
        #expect(t == "Session complete")
        #expect(!t.localizedCaseInsensitiveContains("therapy"))
    }

    @Test("Schedule is a no-op when disabled or endsAt is past")
    func scheduleNoOp() {
        SessionEndNotifier.schedule(
            endsAt: Date().addingTimeInterval(-10),
            modeName: "Calm",
            enabled: true
        )
        SessionEndNotifier.schedule(
            endsAt: Date().addingTimeInterval(60),
            modeName: "Calm",
            enabled: false
        )
    }

    @Test("canDeliverAlerts maps authorization statuses")
    func canDeliver() {
        #expect(SessionEndNotifier.canDeliverAlerts(authorizationStatus: .authorized))
        #expect(!SessionEndNotifier.canDeliverAlerts(authorizationStatus: .denied))
        #expect(!SessionEndNotifier.canDeliverAlerts(authorizationStatus: .notDetermined))
    }

    @Test("Denied help text is actionable and non-medical")
    func deniedHelp() {
        let help = SessionEndNotifier.deniedHelpText()
        #expect(!help.isEmpty)
        #expect(!help.localizedCaseInsensitiveContains("treat"))
        #expect(!help.localizedCaseInsensitiveContains("clinical"))
    }
}

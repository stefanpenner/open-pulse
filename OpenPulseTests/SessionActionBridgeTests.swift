import Foundation
import Testing
@testable import OpenPulse

@Suite("SessionActionBridge")
struct SessionActionBridgeTests {
    /// Fresh isolated bridge — no shared process singleton mutation.
    @MainActor
    private func freshBridge() -> SessionActionBridge {
        SessionActionBridge()
    }

    @Test("Intensity nudge during session clamps 1…9")
    @MainActor func intensityNudgeDuringSession() {
        let bridge = freshBridge()
        let suite = "test.bridge.nudge.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        vm.start()
        #expect(vm.isRunning)
        bridge.bind(vm)
        bridge.requestNudgeStrength(by: 1)
        #expect(vm.strength == 6)
        bridge.requestNudgeStrength(by: -2)
        #expect(vm.strength == 4)
        vm.setStrength(9)
        bridge.requestNudgeStrength(by: 1)
        #expect(vm.strength == 9, "ceiling at device max")
        vm.setStrength(1)
        bridge.requestNudgeStrength(by: -1)
        #expect(vm.strength == 1, "floor at device min")
    }

    @Test("Intensity nudge ignored when idle")
    @MainActor func intensityNudgeIgnoredWhenIdle() {
        let bridge = freshBridge()
        let suite = "test.bridge.nudge.idle.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.strength = 5
        bridge.bind(vm)
        bridge.requestNudgeStrength(by: 1)
        #expect(vm.strength == 5, "idle must not change strength")
        #expect(!vm.isRunning)
    }

    @Test("Bound idle requestPause drops pending (no poison for next session)")
    @MainActor func boundIdleDropsPause() {
        let bridge = freshBridge()
        let suite = "test.bridge.idle.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        let vm = SessionViewModel(defaults: d, ble: mock)
        bridge.bind(vm)
        #expect(!vm.isRunning)
        bridge.requestPause()
        #expect(bridge.pending == nil)
    }

    @Test("Pause request before bind is drained on bind")
    @MainActor func pausePendingDrainsOnBind() {
        let bridge = freshBridge()
        // Isolate: request pause with no session
        bridge.requestPause()
        #expect(bridge.pending == .pause)

        let suite = "test.bridge.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        vm.start()
        #expect(vm.isRunning)

        bridge.bind(vm)
        // Drain should have paused running session
        #expect(vm.isPaused)
        #expect(bridge.pending == nil)
    }

    @Test("Resume pending waits for ready then drains")
    @MainActor func resumePendingWaitsForReady() {
        let bridge = freshBridge()
        let suite = "test.bridge.resume.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        vm.pause()
        #expect(vm.isPaused)

        mock.isReady = false
        bridge.bind(vm)
        bridge.requestResume()
        #expect(vm.isPaused, "Cannot resume without ready")
        #expect(bridge.pending == .resume)

        mock.isReady = true
        bridge.drainPending()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Unbound complete stashes durable pending off on standard prefs")
    @MainActor func unboundCompleteSetsPendingDeactivate() {
        let bridge = freshBridge()
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        bridge.requestComplete()
        #expect(bridge.pending == .complete)
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == true)
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
    }

    @Test("Bound start when ready starts session")
    @MainActor func boundStartWhenReady() {
        let bridge = freshBridge()
        let suite = "test.bridge.start.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        #expect(vm.canStart)
        bridge.requestStart()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Bound start when not ready stashes pending until drain")
    @MainActor func boundStartNotReadyStashes() {
        let bridge = freshBridge()
        let suite = "test.bridge.start.notready.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        #expect(!vm.canStart)
        bridge.requestStart()
        #expect(!vm.isRunning)
        #expect(bridge.pending == .start)
        // Ready alone must not auto-start without drain
        mock.becomeReady()
        #expect(!vm.isRunning, "ready edge alone must not auto-start")
        bridge.drainPending()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Ready alone never auto-starts without user pending")
    @MainActor func readyAloneNoAutoStart() {
        let bridge = freshBridge()
        let suite = "test.bridge.noautostart.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        bridge.bind(vm)
        mock.becomeReady()
        bridge.drainPending()
        #expect(!vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Start pending drains on bind when ready")
    @MainActor func startPendingDrainsOnBind() {
        let bridge = freshBridge()
        bridge.requestStart()
        #expect(bridge.pending == .start)

        let suite = "test.bridge.start.drain.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Bound stop ends session and arms pending off")
    @MainActor func boundStopEndsSession() {
        let bridge = freshBridge()
        let suite = "test.bridge.stop.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(vm.isRunning)
        mock.reset()
        bridge.bind(vm)
        bridge.requestStop()
        #expect(!vm.isRunning)
        #expect(bridge.pending == nil)
        #expect(vm.pendingDeactivate)
        #expect(
            mock.commands.contains(BLEConstants.deactivateCommand)
                || mock.commands.contains("0\n"),
            "stop must request device off, cmds=\(mock.commands)"
        )
    }

    @Test("Unbound stop sets durable pending off")
    @MainActor func unboundStopSetsPendingDeactivate() {
        let bridge = freshBridge()
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        bridge.requestStop()
        #expect(bridge.pending == .stop)
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == true)
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
    }

    @Test("LA complete hook inject fires bridge complete")
    @MainActor func laCompleteHookInject() {
        let bridge = freshBridge()
        let suite = "test.la.complete.hook.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 30))
        bridge.bind(vm)
        let previous = SessionLiveActivityController.onSessionShouldComplete
        SessionLiveActivityController.onSessionShouldComplete = {
            bridge.requestComplete()
        }
        defer { SessionLiveActivityController.onSessionShouldComplete = previous }
        let confirmed = SessionLiveActivityController.requestSessionComplete()
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate)
        #expect(confirmed == true)
    }

    @Test("Bound complete when wall past stops session")
    @MainActor func boundCompleteWhenWallPast() {
        let bridge = freshBridge()
        let suite = "test.bridge.complete.past.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        mock.reset()
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 30))
        bridge.bind(vm)
        bridge.requestComplete()
        #expect(!vm.isRunning)
        #expect(bridge.pending == nil)
        // Same HW safety as stop(.completed)
        #expect(vm.pendingDeactivate, "wall complete must arm durable off")
        #expect(
            mock.commands.contains(BLEConstants.deactivateCommand)
                || mock.commands.contains("0\n"),
            "ready wall complete must enqueue off, cmds=\(mock.commands)"
        )
    }

    @Test("Bound complete honors wall clock without early stop")
    @MainActor func boundCompleteDoesNotStopEarly() {
        let bridge = freshBridge()
        let suite = "test.bridge.complete.early.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        bridge.bind(vm)
        bridge.requestComplete()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Stale start pending expires — late ready does not surprise-start")
    @MainActor func staleStartPendingDoesNotAutoStartOnLateReady() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        bridge.now = { t0 }
        let suite = "test.bridge.start.ttl.stale.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        bridge.requestStart()
        #expect(bridge.pending == .start)
        #expect(!vm.isRunning)
        // Past Start TTL (user walked away; device connects later)
        bridge.now = { t0.addingTimeInterval(SessionActionBridge.startPendingTTL + 1) }
        mock.becomeReady()
        bridge.drainPending()
        #expect(!vm.isRunning, "expired Start must not stim on late connect")
        #expect(bridge.pending == nil)
    }

    @Test("Fresh start pending still drains within TTL")
    @MainActor func freshStartPendingWithinTTL() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_700_000_100)
        bridge.now = { t0 }
        let suite = "test.bridge.start.ttl.fresh.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        bridge.requestStart()
        #expect(bridge.pending == .start)
        // Still within window
        bridge.now = { t0.addingTimeInterval(SessionActionBridge.startPendingTTL / 2) }
        mock.becomeReady()
        bridge.drainPending()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Unbound stale start expires on late bind")
    @MainActor func unboundStaleStartExpiresOnBind() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_700_000_200)
        bridge.now = { t0 }
        bridge.requestStart()
        #expect(bridge.pending == .start)
        bridge.now = { t0.addingTimeInterval(SessionActionBridge.startPendingTTL + 5) }

        let suite = "test.bridge.start.ttl.unbound.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        #expect(!vm.isRunning, "stale unbound Start must not start on bind")
        #expect(bridge.pending == nil)
    }

    @Test("Bound start with empty battery does not stash pending")
    @MainActor func boundStartEmptyBatteryDrops() {
        let bridge = freshBridge()
        let suite = "test.bridge.start.empty.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        mock.batteryPercentage = 0
        mock.isCharging = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        #expect(!vm.canStart)
        bridge.requestStart()
        #expect(!vm.isRunning)
        #expect(bridge.pending == nil, "empty pack must not defer start until charge")
    }

    @Test("Stale resume pending expires — late ready does not surprise-resume")
    @MainActor func staleResumePendingDoesNotAutoResumeOnLateReady() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_700_000_300)
        bridge.now = { t0 }
        let suite = "test.bridge.resume.ttl.stale.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        vm.pause()
        #expect(vm.isPaused)
        mock.isReady = false
        bridge.bind(vm)
        bridge.requestResume()
        #expect(bridge.pending == .resume)
        #expect(vm.isPaused)
        bridge.now = { t0.addingTimeInterval(SessionActionBridge.intentPendingTTL + 1) }
        mock.becomeReady()
        bridge.drainPending()
        #expect(vm.isPaused, "expired Resume must not stim on late connect")
        #expect(!vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Fresh resume pending still drains within TTL")
    @MainActor func freshResumePendingWithinTTL() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_700_000_400)
        bridge.now = { t0 }
        let suite = "test.bridge.resume.ttl.fresh.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        vm.pause()
        mock.isReady = false
        bridge.bind(vm)
        bridge.requestResume()
        #expect(bridge.pending == .resume)
        bridge.now = { t0.addingTimeInterval(SessionActionBridge.intentPendingTTL / 2) }
        mock.becomeReady()
        bridge.drainPending()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("requestComplete returns false when wall not past")
    @MainActor func completeReturnsFalseWhenStillRunning() {
        let bridge = freshBridge()
        let suite = "test.bridge.complete.bool.early.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        bridge.bind(vm)
        let ended = bridge.requestComplete()
        #expect(vm.isRunning)
        #expect(ended == false, "wall not past — LA must keep running")
    }

    @Test("requestComplete returns true when wall past")
    @MainActor func completeReturnsTrueWhenWallPast() {
        let bridge = freshBridge()
        let suite = "test.bridge.complete.bool.past.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        vm.sessionStartDate = Date().addingTimeInterval(-Double(vm.timerMinutes * 60 + 30))
        bridge.bind(vm)
        let ended = bridge.requestComplete()
        #expect(!vm.isRunning)
        #expect(ended == true)
    }

    @Test("Unbound requestComplete returns true (end LA) when no session")
    @MainActor func unboundCompleteReturnsTrue() {
        let bridge = freshBridge()
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        // Ensure no durable session keys
        UserDefaults.standard.removeObject(forKey: "session.startDate")
        UserDefaults.standard.removeObject(forKey: "session.totalDuration")
        let ended = bridge.requestComplete()
        #expect(ended == true)
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == true)
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
    }

    @Test("Unbound requestComplete keeps LA when persisted session still has time")
    @MainActor func unboundCompleteFalseWhenSessionRemaining() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_800_100_000)
        bridge.now = { t0.addingTimeInterval(30) }
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        UserDefaults.standard.set(t0.timeIntervalSince1970, forKey: "session.startDate")
        UserDefaults.standard.set(600, forKey: "session.totalDuration")
        UserDefaults.standard.set(0.0, forKey: "session.accumulatedPauseTime")
        UserDefaults.standard.removeObject(forKey: "session.pauseStartDate")
        let ended = bridge.requestComplete()
        #expect(ended == false, "must not claim Session complete mid-session")
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == false)
        UserDefaults.standard.removeObject(forKey: "session.startDate")
        UserDefaults.standard.removeObject(forKey: "session.totalDuration")
    }

    @Test("Unbound requestComplete completes when persisted wall past")
    @MainActor func unboundCompleteTrueWhenWallPast() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_800_200_000)
        bridge.now = { t0.addingTimeInterval(700) }
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        UserDefaults.standard.set(t0.timeIntervalSince1970, forKey: "session.startDate")
        UserDefaults.standard.set(600, forKey: "session.totalDuration")
        UserDefaults.standard.set(0.0, forKey: "session.accumulatedPauseTime")
        UserDefaults.standard.set(false, forKey: "session.isPaused")
        let ended = bridge.requestComplete()
        #expect(ended == true)
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == true)
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        UserDefaults.standard.removeObject(forKey: "session.startDate")
        UserDefaults.standard.removeObject(forKey: "session.totalDuration")
        UserDefaults.standard.removeObject(forKey: "session.isPaused")
    }

    @Test("Unbound requestComplete keeps LA when paused without pauseStart stamp")
    @MainActor func unboundCompleteFalseWhenPausedUnstamped() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_800_300_000)
        bridge.now = { t0.addingTimeInterval(700) }
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        UserDefaults.standard.set(t0.timeIntervalSince1970, forKey: "session.startDate")
        UserDefaults.standard.set(600, forKey: "session.totalDuration")
        UserDefaults.standard.set(0.0, forKey: "session.accumulatedPauseTime")
        UserDefaults.standard.set(true, forKey: "session.isPaused")
        UserDefaults.standard.removeObject(forKey: "session.pauseStartDate")
        UserDefaults.standard.removeObject(forKey: "session.offlineSince")
        let ended = bridge.requestComplete()
        #expect(ended == false, "paused without stamp must not claim complete")
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == false)
        UserDefaults.standard.removeObject(forKey: "session.startDate")
        UserDefaults.standard.removeObject(forKey: "session.totalDuration")
        UserDefaults.standard.removeObject(forKey: "session.isPaused")
    }

    @Test("Unbound requestComplete keeps LA when offline past auto-pause freeze")
    @MainActor func unboundCompleteFalseWhenOfflineFreezeRemaining() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_800_400_000)
        // Drop at +100s; freeze at +190s; now at +800s — only ~190s active of 600
        let drop = t0.addingTimeInterval(100)
        bridge.now = { t0.addingTimeInterval(800) }
        AppPreferences.setPendingDeactivate(false, defaults: .standard)
        UserDefaults.standard.set(t0.timeIntervalSince1970, forKey: "session.startDate")
        UserDefaults.standard.set(600, forKey: "session.totalDuration")
        UserDefaults.standard.set(0.0, forKey: "session.accumulatedPauseTime")
        UserDefaults.standard.set(false, forKey: "session.isPaused")
        UserDefaults.standard.set(drop.timeIntervalSince1970, forKey: "session.offlineSince")
        UserDefaults.standard.removeObject(forKey: "session.pauseStartDate")
        let ended = bridge.requestComplete()
        #expect(ended == false, "offline freeze must not count drop as full session")
        #expect(AppPreferences.pendingDeactivate(defaults: .standard) == false)
        UserDefaults.standard.removeObject(forKey: "session.startDate")
        UserDefaults.standard.removeObject(forKey: "session.totalDuration")
        UserDefaults.standard.removeObject(forKey: "session.offlineSince")
        UserDefaults.standard.removeObject(forKey: "session.isPaused")
    }

    @Test("Island Stop while paused offline ends session")
    @MainActor func stopWhilePausedOfflineEndsSession() {
        let bridge = freshBridge()
        let suite = "test.bridge.stop.paused.offline.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        vm.pause()
        #expect(vm.isPaused)
        mock.isReady = false
        mock.isConnected = false
        mock.reset()
        bridge.bind(vm)
        // Same path as StopOpenPulseSessionIntent on Island
        bridge.requestStop()
        #expect(!vm.isRunning)
        #expect(!vm.isPaused)
        #expect(vm.pendingDeactivate, "stop must arm durable HW off")
        #expect(bridge.pending == nil)
    }

    @Test("Island Stop while running offline ends session")
    @MainActor func stopWhileRunningOfflineEndsSession() {
        let bridge = freshBridge()
        let suite = "test.bridge.stop.running.offline.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.start()
        #expect(vm.isRunning)
        mock.isReady = false
        mock.isConnected = false
        mock.reset()
        bridge.bind(vm)
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false,
                isRunning: true,
                pendingDeviceOff: false,
                isLinkReady: false
            ) == .stop
        )
        bridge.requestStop()
        #expect(!vm.isRunning)
        #expect(vm.pendingDeactivate)
        #expect(bridge.pending == nil)
    }

    @Test("Not-ready empty pack must not stash Start pending")
    @MainActor func notReadyEmptyDoesNotArmStart() {
        let bridge = freshBridge()
        let suite = "test.bridge.start.notready.empty.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = false
        mock.isReady = false
        mock.batteryPercentage = 0
        mock.isCharging = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        bridge.requestStart()
        #expect(bridge.pending == nil, "empty pack must not defer Start")
        mock.batteryPercentage = 50
        mock.becomeReady()
        bridge.drainPending()
        #expect(!vm.isRunning, "no stashed Start after charge+ready")
    }

    @Test("Stale charging flag cleared — empty pack still blocks after disconnect")
    @MainActor func staleChargingDoesNotBypassEmptyGate() {
        let suite = "test.bridge.stale.charge.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        mock.batteryPercentage = 0
        mock.isCharging = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(vm.canStart, "live charging empty may start")
        // Simulate disconnect cleanup contract (keep % , clear charge truth)
        mock.isConnected = false
        mock.isReady = false
        mock.isCharging = nil
        mock.becomeReady()
        #expect(mock.batteryPercentage == 0)
        #expect(mock.isCharging == nil)
        #expect(!vm.canStart, "stale charge must not allow empty start")
        #expect(vm.startBlockedReason == BatteryPresentation.startBlockedEmptyCopy)
    }

    @Test("Start pending kept through battery-read grace then drains on canStart")
    @MainActor func startPendingSurvivesBatteryReadGrace() {
        let bridge = freshBridge()
        let t0 = Date(timeIntervalSince1970: 1_800_000_500)
        bridge.now = { t0 }
        let suite = "test.bridge.start.grace.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        mock.batteryPercentage = nil
        mock.isCharging = false
        let vm = SessionViewModel(defaults: d, ble: mock)
        vm.now = { t0 }
        // Re-seed ready clock with inject
        mock.isReady = false
        mock.becomeReady(confirmBattery: false)
        vm.selectMode(.stressRelief)
        vm.strength = 5
        bridge.bind(vm)
        #expect(!vm.canStart, "within battery grace")
        bridge.requestStart()
        #expect(bridge.pending == .start, "must keep pending through grace")
        #expect(!vm.isRunning)
        // Battery arrives → canStart; drain like ContentView onChange
        mock.batteryPercentage = 70
        mock.batterySampleConfirmed = true
        #expect(vm.canStart)
        bridge.drainPending()
        #expect(vm.isRunning)
        #expect(bridge.pending == nil)
    }

    @Test("Bound idle Stop re-arms durable hardware off")
    @MainActor func boundIdleStopRearmsHardwareOff() {
        let bridge = freshBridge()
        let suite = "test.bridge.stop.idle.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let mock = MockDeviceTransport()
        mock.isConnected = true
        mock.isReady = true
        let vm = SessionViewModel(defaults: d, ble: mock)
        #expect(!vm.isRunning)
        #expect(!vm.isPaused)
        mock.reset()
        bridge.bind(vm)
        bridge.requestStop()
        #expect(vm.pendingDeactivate, "idle Stop must re-arm HW off")
        #expect(
            mock.commands.contains(BLEConstants.deactivateCommand)
                || mock.commands.contains("0\n"),
            "idle Stop must enqueue off when ready, cmds=\(mock.commands)"
        )
        #expect(bridge.pending == nil)
    }
}

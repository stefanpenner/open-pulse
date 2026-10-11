import Foundation
import Testing
@testable import OpenPulse

@Suite("ConnectionPresentation")
struct ConnectionPresentationTests {
    @Test("Four link states for accessibility")
    func fourStates() {
        #expect(ConnectionPresentation.accessibilityLabel(
            isBluetoothOff: true, isConnected: false, isReady: false
        ) == "Bluetooth Off")
        #expect(ConnectionPresentation.accessibilityLabel(
            isBluetoothOff: false, isConnected: true, isReady: true
        ) == "Connected")
        #expect(ConnectionPresentation.accessibilityLabel(
            isBluetoothOff: false, isConnected: true, isReady: false
        ) == "Connecting")
        #expect(ConnectionPresentation.accessibilityLabel(
            isBluetoothOff: false, isConnected: false, isReady: false
        ) == "Searching for device")
    }

    @Test("Chip text uses ellipsis for in-progress states")
    func chipText() {
        #expect(ConnectionPresentation.chipText(
            isBluetoothOff: false, isConnected: true, isReady: false
        ) == "Connecting…")
        #expect(ConnectionPresentation.chipText(
            isBluetoothOff: false, isConnected: false, isReady: false
        ) == "Searching…")
    }

    @Test("Empty-state titles cover four link states")
    func emptyTitles() {
        #expect(ConnectionPresentation.emptyTitle(
            isBluetoothOff: true, isConnected: false, isReady: false
        ) == "Bluetooth is off")
        #expect(ConnectionPresentation.emptyTitle(
            isBluetoothOff: false, isConnected: true, isReady: true
        ) == "Connected")
        #expect(ConnectionPresentation.emptyTitle(
            isBluetoothOff: false, isConnected: true, isReady: false
        ) == "Finishing connection")
        #expect(ConnectionPresentation.emptyTitle(
            isBluetoothOff: false, isConnected: false, isReady: false
        ) == "Looking for your Pulsetto")
    }

    @Test("Empty-state details guide the user")
    func emptyDetails() {
        #expect(ConnectionPresentation.emptyDetail(
            isBluetoothOff: true, isConnected: false, isReady: false
        ).contains("Bluetooth"))
        #expect(ConnectionPresentation.emptyDetail(
            isBluetoothOff: false, isConnected: true, isReady: false
        ).contains("setting up"))
        #expect(ConnectionPresentation.emptyDetail(
            isBluetoothOff: false, isConnected: false, isReady: false
        ).contains("nearby"))
    }
}

@Suite("LiveActivityPresentation")
struct LiveActivityPresentationTests {
    @Test("Progress is zero at start and one when done")
    func progressEnds() {
        #expect(LiveActivityPresentation.progress(remainingSeconds: 600, totalSeconds: 600) == 0)
        #expect(LiveActivityPresentation.progress(remainingSeconds: 0, totalSeconds: 600) == 1)
    }

    @Test("Progress updates when total extends mid-session")
    func progressAfterExtend() {
        // Was 5 of 10 min (0.5); user added 1 min → 5 of 11
        let p = LiveActivityPresentation.progress(remainingSeconds: 5 * 60, totalSeconds: 11 * 60)
        #expect(abs(p - (1.0 - 300.0 / 660.0)) < 0.0001)
    }

    @Test("Progress clamps invalid totals")
    func progressClamp() {
        #expect(LiveActivityPresentation.progress(remainingSeconds: 10, totalSeconds: 0) == 0)
        #expect(LiveActivityPresentation.progress(remainingSeconds: -5, totalSeconds: 100) == 1)
    }

    @Test("Paused with pending off surfaces stopping device")
    func pausedPendingOff() {
        let s = LiveActivityPresentation.statusLine(
            isPaused: true,
            isRunning: false,
            pendingDeviceOff: true,
            modeStatus: "Paused",
            modeName: "Calm",
            isLinkReady: true
        )
        #expect(s.contains("stopping"))
    }

    @Test("Paused ignores stale stim phase status")
    func pausedDropsStimCopy() {
        let s = LiveActivityPresentation.statusLine(
            isPaused: true,
            isRunning: false,
            pendingDeviceOff: false,
            modeStatus: "Bilateral · Continuous",
            modeName: "Stress",
            isLinkReady: true
        )
        #expect(s == "Paused")
        #expect(!s.contains("Bilateral"))
    }

    @Test("Running offline shows reconnecting")
    func reconnecting() {
        let s = LiveActivityPresentation.statusLine(
            isPaused: false,
            isRunning: true,
            pendingDeviceOff: false,
            modeStatus: "Bilateral",
            modeName: "Focus",
            isLinkReady: false
        )
        #expect(s == "Reconnecting…")
    }

    @Test("Paused offline waits for device (no dishonest Resume)")
    func pausedOfflineWaits() {
        let s = LiveActivityPresentation.statusLine(
            isPaused: true,
            isRunning: false,
            pendingDeviceOff: false,
            modeStatus: "Paused",
            modeName: "Calm",
            isLinkReady: false
        )
        #expect(s == "Paused · waiting for device")
    }

    @Test("Time accessibility is glanceable")
    func timeA11y() {
        #expect(LiveActivityPresentation.timeAccessibility(remainingSeconds: 125) == "2 minutes 5 seconds remaining")
        #expect(LiveActivityPresentation.timeAccessibility(remainingSeconds: 45) == "45 seconds remaining")
        #expect(LiveActivityPresentation.timeAccessibility(remainingSeconds: 0) == "0 seconds remaining")
    }

    @Test("formatTime is zero-padded mm:ss")
    func formatTime() {
        #expect(LiveActivityPresentation.formatTime(125) == "02:05")
        #expect(LiveActivityPresentation.formatTime(0) == "00:00")
        #expect(LiveActivityPresentation.formatTime(-5) == "00:00")
        #expect(LiveActivityPresentation.formatTime(9) == "00:09")
    }

    @Test("LA control action pause/resume/stop honesty")
    func controlAction() {
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false, isRunning: true, pendingDeviceOff: false, isLinkReady: true
            ) == .pause
        )
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: true, isRunning: false, pendingDeviceOff: false, isLinkReady: true
            ) == .resume
        )
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: true, isRunning: false, pendingDeviceOff: false, isLinkReady: false
            ) == .stop,
            "Paused offline — Stop so Island is not a trap"
        )
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: true, isRunning: false, pendingDeviceOff: true, isLinkReady: true
            ) == .stop,
            "Paused while HW stopping — offer Stop, not Resume"
        )
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false, isRunning: true, pendingDeviceOff: true, isLinkReady: true
            ) == .stop,
            "Running with pending off — Stop escape, not no control"
        )
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false, isRunning: true, pendingDeviceOff: false, isLinkReady: false
            ) == .stop,
            "Running offline — Stop escape hatch, not Pause trap"
        )
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false, isRunning: false, pendingDeviceOff: true, isLinkReady: true
            ) == .stop,
            "Completed linger pending off — Stop re-arms HW off"
        )
    }

    @Test("endsAt is now + remaining when running and link ready")
    func endsAtWhenRunning() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let end = LiveActivityPresentation.endsAt(
            remainingSeconds: 125,
            isPaused: false,
            isLinkReady: true,
            now: now
        )
        #expect(end == now.addingTimeInterval(125))
    }

    @Test("endsAt is nil when paused or zero remaining")
    func endsAtPausedOrZero() {
        let now = Date()
        #expect(
            LiveActivityPresentation.endsAt(
                remainingSeconds: 60, isPaused: true, isLinkReady: true, now: now
            ) == nil
        )
        #expect(
            LiveActivityPresentation.endsAt(
                remainingSeconds: 0, isPaused: false, isLinkReady: true, now: now
            ) == nil
        )
        #expect(
            LiveActivityPresentation.endsAt(
                remainingSeconds: -5, isPaused: false, isLinkReady: true, now: now
            ) == nil
        )
    }

    @Test("endsAt is nil when link not ready — freeze Island countdown offline")
    func endsAtNilWhenOffline() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Running with remaining time but BLE down: must not drive timerInterval to 00:00
        #expect(
            LiveActivityPresentation.endsAt(
                remainingSeconds: 400,
                isPaused: false,
                isLinkReady: false,
                now: now
            ) == nil
        )
        // Still frozen when paused + offline (double freeze)
        #expect(
            LiveActivityPresentation.endsAt(
                remainingSeconds: 400,
                isPaused: true,
                isLinkReady: false,
                now: now
            ) == nil
        )
    }

    @Test("Uses live countdown when endsAt set, not paused, link ready")
    func usesLiveCountdown() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let future = now.addingTimeInterval(120)
        let past = now.addingTimeInterval(-5)
        #expect(
            LiveActivityPresentation.usesLiveCountdown(
                endsAt: future, isPaused: false, isLinkReady: true, now: now
            )
        )
        #expect(
            !LiveActivityPresentation.usesLiveCountdown(
                endsAt: future, isPaused: true, isLinkReady: true, now: now
            )
        )
        #expect(
            !LiveActivityPresentation.usesLiveCountdown(
                endsAt: nil, isPaused: false, isLinkReady: true, now: now
            )
        )
        // Offline freezes system countdown even if a stale endsAt leaked in
        #expect(
            !LiveActivityPresentation.usesLiveCountdown(
                endsAt: future, isPaused: false, isLinkReady: false, now: now
            )
        )
        // Past endsAt freezes — static remaining, not system 00:00
        #expect(
            !LiveActivityPresentation.usesLiveCountdown(
                endsAt: past, isPaused: false, isLinkReady: true, now: now
            )
        )
    }

    @Test("Completed session LA status is honest wellness copy")
    func completedStatus() {
        #expect(LiveActivityPresentation.completedStatus(modeName: "Calm") == "Session complete · Calm")
        #expect(LiveActivityPresentation.completedStatus(modeName: "") == "Session complete")
        #expect(
            LiveActivityPresentation.completedStatus(modeName: "Calm", pendingDeviceOff: true)
                == "Session complete · Calm · turning device off"
        )
        #expect(
            LiveActivityPresentation.completedStatus(modeName: "", pendingDeviceOff: true)
                == "Session complete · turning device off"
        )
        // Pending off on complete linger offers Stop (re-arm HW off), not silence
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false,
                isRunning: false,
                pendingDeviceOff: true,
                isLinkReady: true
            ) == .stop
        )
    }

    @Test("No control when session is complete (remaining 0 + not paused)")
    func controlNoneWhenComplete() {
        // Finished: not paused, not running, no pending off
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false,
                isRunning: false,
                pendingDeviceOff: false,
                isLinkReady: true
            ) == .none
        )
        // Widget must pass isRunning false when remaining == 0 even if not paused
        #expect(
            LiveActivityPresentation.controlAction(
                isPaused: false,
                isRunning: false, // !isPaused && remainingSeconds > 0  → false when remaining 0
                pendingDeviceOff: false,
                isLinkReady: true
            ) == .none
        )
    }

    @Test("Compact a11y prefers statusText (reconnect honest)")
    func compactPrefersStatus() {
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "Reconnecting…",
                isPaused: false,
                pendingDeviceOff: false
            ) == "Reconnecting…"
        )
    }

    @Test("Compact a11y falls back matches statusLine priority")
    func compactFallbacks() {
        // Paused + pending must match statusLine ("Paused · stopping device")
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "",
                isPaused: true,
                isRunning: false,
                pendingDeviceOff: true
            ) == "Paused · stopping device"
        )
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "",
                isPaused: false,
                isRunning: false,
                pendingDeviceOff: true
            ) == "Turning device off"
        )
        // Mid-run durable pending — reconnect, not turning off
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "",
                isPaused: false,
                isRunning: true,
                pendingDeviceOff: true,
                isLinkReady: false
            ) == "Reconnecting…"
        )
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "",
                isPaused: true,
                isRunning: false,
                pendingDeviceOff: false
            ) == "Paused"
        )
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "",
                isPaused: true,
                isRunning: false,
                pendingDeviceOff: false,
                isLinkReady: false
            ) == "Paused · waiting for device"
        )
        #expect(
            LiveActivityPresentation.compactAccessibility(
                statusText: "",
                isPaused: false,
                isRunning: true,
                pendingDeviceOff: false
            ) == "Open Pulse session"
        )
    }

    @Test("Lock fallback offline paused matches statusLine")
    func lockFallbackOfflinePaused() {
        #expect(
            LiveActivityPresentation.lockScreenFallback(
                isPaused: true,
                pendingDeviceOff: false,
                isLinkReady: false
            ) == "Paused · waiting for device"
        )
    }

    @Test("Compact icon is honest about link, pause, power-off, rest")
    func compactIconHonesty() {
        // Idle/paused pending-off → power (banner-visible)
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: false, isRunning: false, pendingDeviceOff: true, isLinkReady: true,
                isStimulationActive: false
            ) == "power"
        )
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: true, isRunning: false, pendingDeviceOff: true, isLinkReady: true,
                isStimulationActive: false
            ) == "power"
        )
        // Mid-run durable pending is reconnect — not power
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: false, isRunning: true, pendingDeviceOff: true, isLinkReady: false,
                isStimulationActive: false
            ) == "antenna.radiowaves.left.and.right",
            "mid-run pending must not claim power/off"
        )
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: true, isRunning: false, pendingDeviceOff: false, isLinkReady: true,
                isStimulationActive: false
            ) == "pause.fill"
        )
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: true, isRunning: false, pendingDeviceOff: false, isLinkReady: false,
                isStimulationActive: false
            ) == "antenna.radiowaves.left.and.right",
            "Offline wins over pause"
        )
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: false, isRunning: true, pendingDeviceOff: false, isLinkReady: false,
                isStimulationActive: true
            ) == "antenna.radiowaves.left.and.right"
        )
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: false, isRunning: true, pendingDeviceOff: false, isLinkReady: true,
                isStimulationActive: false
            ) == "moon.zzz"
        )
        #expect(
            LiveActivityPresentation.compactIconName(
                isPaused: false, isRunning: true, pendingDeviceOff: false, isLinkReady: true,
                isStimulationActive: true
            ) == "waveform.path.ecg"
        )
        #expect(
            !LiveActivityPresentation.claimsPendingOffChrome(
                isRunning: true, pendingDeviceOff: true
            ),
            "mid-run pending chrome off"
        )
        #expect(
            LiveActivityPresentation.claimsPendingOffChrome(
                isRunning: false, pendingDeviceOff: true
            )
        )
    }

    @Test("Battery presentation pure helpers")
    func batteryPresentation() {
        #expect(BatteryPresentation.isLow(percent: 5, isCharging: false))
        #expect(!BatteryPresentation.isLow(percent: 5, isCharging: true))
        #expect(BatteryPresentation.isLow(percent: 5, isCharging: nil), "Unknown charge still warns when % low")
        #expect(BatteryPresentation.isEmpty(percent: 0))
        #expect(!BatteryPresentation.isEmpty(percent: 5))
        #expect(
            BatteryPresentation.accessibilityLabel(percent: 20, isCharging: false, isLow: true)
                .contains("low")
        )
        #expect(
            BatteryPresentation.accessibilityLabel(percent: 0, isCharging: false, isLow: true)
                .localizedCaseInsensitiveContains("empty")
        )
        #expect(
            BatteryPresentation.accessibilityLabel(
                percent: 50, isCharging: false, isLow: false, sampleConfirmed: false
            ).localizedCaseInsensitiveContains("last")
        )
        #expect(BatteryPresentation.chipText(percent: 80, sampleConfirmed: true) == "80%")
        #expect(BatteryPresentation.chipText(percent: 80, sampleConfirmed: false) == "80% · last")
        #expect(BatteryPresentation.iconName(percent: 50) == "battery.50percent")
        #expect(BatteryPresentation.iconName(percent: 0) == "battery.0percent")
    }

    @Test("Empty pack blocks start unless charging; unknown only in grace")
    func batteryBlocksStart() {
        #expect(BatteryPresentation.blocksStart(percent: 0, isCharging: false))
        #expect(BatteryPresentation.blocksStart(percent: 0, isCharging: nil))
        #expect(!BatteryPresentation.blocksStart(percent: 0, isCharging: true), "charging empty may recover")
        #expect(!BatteryPresentation.blocksStart(percent: 5, isCharging: false))
        // Unknown with no ready clock — not blocked (not in grace)
        #expect(!BatteryPresentation.blocksStart(percent: nil, isCharging: false))
        // Unknown just after ready — block for first Q
        #expect(
            BatteryPresentation.blocksStart(
                percent: nil, isCharging: false, secondsSinceReady: 0.1
            )
        )
        #expect(
            !BatteryPresentation.blocksStart(
                percent: nil, isCharging: false,
                secondsSinceReady: BatteryPresentation.unknownGraceSeconds + 0.1
            ),
            "after grace allow Start so mute UART cannot brick"
        )
        // Stale cached non-empty unconfirmed — block during grace
        #expect(
            BatteryPresentation.blocksStart(
                percent: 50, isCharging: false, sampleConfirmed: false, secondsSinceReady: 0.1
            ),
            "stale cache must not skip first-Q gate"
        )
        #expect(
            !BatteryPresentation.blocksStart(
                percent: 50, isCharging: false, sampleConfirmed: false,
                secondsSinceReady: BatteryPresentation.unknownGraceSeconds + 0.1
            ),
            "after grace unconfirmed non-empty may start"
        )
        #expect(
            BatteryPresentation.blocksStart(
                percent: 0, isCharging: false, sampleConfirmed: false, secondsSinceReady: 0.1
            ),
            "cached empty still blocks"
        )
        #expect(
            BatteryPresentation.startBlockedReason(
                percent: nil, isCharging: false, secondsSinceReady: 0.1
            ) == BatteryPresentation.startBlockedReadingCopy
        )
        #expect(
            BatteryPresentation.startBlockedReason(
                percent: 0, isCharging: false
            ) == BatteryPresentation.startBlockedEmptyCopy
        )
        #expect(!BatteryPresentation.startBlockedEmptyCopy.isEmpty)
    }

    @Test("Offline auto-pause pure policy")
    func offlineAutoPausePolicy() {
        #expect(
            !SessionLinkSafety.shouldAutoPause(
                isRunning: true, isLinkReady: false, secondsOffline: 30
            ),
            "short blip keeps running"
        )
        #expect(
            SessionLinkSafety.shouldAutoPause(
                isRunning: true, isLinkReady: false,
                secondsOffline: SessionLinkSafety.offlineAutoPauseSeconds
            )
        )
        #expect(
            !SessionLinkSafety.shouldAutoPause(
                isRunning: true, isLinkReady: true, secondsOffline: 200
            ),
            "link ready — no auto-pause"
        )
        #expect(
            !SessionLinkSafety.shouldAutoPause(
                isRunning: false, isLinkReady: false, secondsOffline: 200
            )
        )
        #expect(
            !SessionLinkSafety.shouldAutoPause(
                isRunning: true, isLinkReady: false, secondsOffline: nil
            )
        )
        // Remaining delay for restore / re-schedule
        #expect(
            SessionLinkSafety.remainingAutoPauseDelay(secondsOffline: nil)
                == SessionLinkSafety.offlineAutoPauseSeconds
        )
        #expect(
            abs(
                SessionLinkSafety.remainingAutoPauseDelay(secondsOffline: 30) - 60
            ) < 0.001
        )
        #expect(
            SessionLinkSafety.remainingAutoPauseDelay(
                secondsOffline: SessionLinkSafety.offlineAutoPauseSeconds + 10
            ) == 0,
            "already past threshold — fire immediately"
        )
        let drop = Date(timeIntervalSince1970: 2_000_000_000)
        let freeze = SessionLinkSafety.autoPauseFreezeDate(offlineSince: drop)
        #expect(
            freeze == drop.addingTimeInterval(SessionLinkSafety.offlineAutoPauseSeconds)
        )
        let late = drop.addingTimeInterval(SessionLinkSafety.offlineAutoPauseSeconds + 30)
        #expect(
            SessionLinkSafety.readyAfterDrop(isRunning: true, offlineSince: drop, now: late)
                == .pause(freeze: freeze)
        )
        #expect(
            SessionLinkSafety.readyAfterDrop(
                isRunning: true,
                offlineSince: drop,
                now: drop.addingTimeInterval(30)
            ) == .resume
        )
        #expect(
            SessionLinkSafety.readyAfterDrop(isRunning: false, offlineSince: drop, now: late)
                == .resume
        )
    }

    @Test("LA end policy ends only when session confirms")
    func liveActivityEndPolicy() {
        #expect(
            !LiveActivityEndPolicy.shouldEndAsCompleted(
                activityStillCurrent: true, sessionConfirmedComplete: false
            ),
            "wall not past — keep LA"
        )
        #expect(
            LiveActivityEndPolicy.shouldEndAsCompleted(
                activityStillCurrent: true, sessionConfirmedComplete: true
            )
        )
        #expect(
            !LiveActivityEndPolicy.shouldEndAsCompleted(
                activityStillCurrent: false, sessionConfirmedComplete: true
            ),
            "VM already ended LA"
        )
    }

    @Test("Wall complete policy is pause-honest and inject-clock friendly")
    func wallCompletePolicy() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            LiveActivityEndPolicy.shouldCompleteSession(
                now: start.addingTimeInterval(600),
                start: start,
                totalDurationSeconds: 600
            )
        )
        #expect(
            !LiveActivityEndPolicy.shouldCompleteSession(
                now: start.addingTimeInterval(100),
                start: start,
                totalDurationSeconds: 600
            )
        )
        // 500s run + 200s pause still short of 600 active
        #expect(
            !LiveActivityEndPolicy.shouldCompleteSession(
                now: start.addingTimeInterval(700),
                start: start,
                totalDurationSeconds: 600,
                accumulatedPause: 200
            )
        )
        let pauseAt = start.addingTimeInterval(100)
        #expect(
            !LiveActivityEndPolicy.shouldCompleteSession(
                now: pauseAt.addingTimeInterval(50),
                start: start,
                totalDurationSeconds: 600,
                accumulatedPause: 0,
                pauseStart: pauseAt
            )
        )
    }

    @Test("Unbound complete only when no session or wall past")
    func unboundCompletePolicy() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(
            LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: start, persistedStart: nil, totalDurationSeconds: 0
            ),
            "no durable session → dismiss LA"
        )
        #expect(
            !LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: start.addingTimeInterval(60),
                persistedStart: start,
                totalDurationSeconds: 600
            ),
            "mid-session process death must not claim complete"
        )
        #expect(
            LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: start.addingTimeInterval(700),
                persistedStart: start,
                totalDurationSeconds: 600
            ),
            "wall past → complete"
        )
        // Paused without open-pause stamp: wall would over-count practice
        #expect(
            !LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: start.addingTimeInterval(700),
                persistedStart: start,
                totalDurationSeconds: 600,
                accumulatedPause: 0,
                pauseStart: nil,
                isPaused: true
            ),
            "paused + missing pauseStart must not false-complete"
        )
        // Paused with stamp still wall-honest
        let pauseAt = start.addingTimeInterval(100)
        #expect(
            !LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: pauseAt.addingTimeInterval(50),
                persistedStart: start,
                totalDurationSeconds: 600,
                accumulatedPause: 0,
                pauseStart: pauseAt,
                isPaused: true
            )
        )
        #expect(
            LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: start.addingTimeInterval(800),
                persistedStart: start,
                totalDurationSeconds: 600,
                accumulatedPause: 0,
                pauseStart: start.addingTimeInterval(650),
                isPaused: true
            ),
            "active elapsed already past total before/during pause"
        )
        // Mid-run offline past 90s freeze: offline must not count as practice
        let drop = start.addingTimeInterval(100)
        #expect(
            !LiveActivityEndPolicy.shouldConfirmUnboundComplete(
                now: start.addingTimeInterval(800),
                persistedStart: start,
                totalDurationSeconds: 600,
                accumulatedPause: 0,
                pauseStart: nil,
                isPaused: false,
                offlineSince: drop
            ),
            "offline past auto-pause freeze must keep LA (remaining practice left)"
        )
        // Short offline blip under 90s: no freeze yet — wall may complete if long enough
        #expect(
            LiveActivityEndPolicy.resolveOpenPauseStart(
                now: drop.addingTimeInterval(30),
                pauseStart: nil,
                offlineSince: drop
            ) == nil,
            "blip under threshold does not freeze"
        )
        let freeze = SessionLinkSafety.autoPauseFreezeDate(offlineSince: drop)
        #expect(
            LiveActivityEndPolicy.resolveOpenPauseStart(
                now: freeze.addingTimeInterval(10),
                pauseStart: nil,
                offlineSince: drop
            ) == freeze
        )
    }

    @Test("Empty detail warns when battery low while connecting")
    func emptyDetailBatteryLow() {
        let detail = ConnectionPresentation.emptyDetail(
            isBluetoothOff: false,
            isConnected: false,
            isReady: false,
            batteryPercent: 10,
            isCharging: false
        )
        #expect(detail.localizedCaseInsensitiveContains("battery"))
        let empty = ConnectionPresentation.emptyDetail(
            isBluetoothOff: false,
            isConnected: false,
            isReady: false,
            batteryPercent: 0,
            isCharging: false
        )
        #expect(empty.localizedCaseInsensitiveContains("empty")
            || empty.localizedCaseInsensitiveContains("charge"))
        let stale = ConnectionPresentation.emptyDetail(
            isBluetoothOff: false,
            isConnected: false,
            isReady: false,
            batteryPercent: 40,
            isCharging: false,
            batterySampleConfirmed: false
        )
        #expect(
            stale.localizedCaseInsensitiveContains("last")
                || stale.localizedCaseInsensitiveContains("confirm"),
            "unconfirmed cache must say last known / confirming"
        )
    }

    @Test("Wellness surface style respects Reduce Transparency")
    func wellnessSurfaceStyle() {
        #expect(WellnessSurface.style(reduceTransparency: false) == .glass)
        #expect(WellnessSurface.style(reduceTransparency: true) == .solid)
        // Contract: glass and solid are distinct control-surface tokens
        #expect(WellnessSurfaceStyle.glass != WellnessSurfaceStyle.solid)
    }

    // MARK: - SessionRestorePolicy (kill / cold launch honesty)

    @Test("Restore mid-offline past freeze keeps remaining frozen, not wall-elapsed")
    func restoreOfflineFreezeRemaining() {
        // 600s session; 100s practice then drop; kill 400s after drop (past 90s freeze)
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let drop = start.addingTimeInterval(100)
        let now = drop.addingTimeInterval(400)
        let freeze = SessionLinkSafety.autoPauseFreezeDate(offlineSince: drop)
        let outcome = SessionRestorePolicy.resolve(
            now: now,
            start: start,
            totalDurationSeconds: 600,
            accumulatedPause: 0,
            diskPaused: false,
            diskPauseStart: nil,
            offlineSince: drop
        )
        #expect(outcome.treatAsPaused)
        #expect(!outcome.shouldFinalizeExpired)
        #expect(outcome.openPauseStart == freeze)
        // Active practice ≈ freeze - start (100s + ~90s threshold), not 500s wall
        let activeAtFreeze = Int(freeze.timeIntervalSince(start))
        let expectedRem = 600 - activeAtFreeze
        #expect(outcome.remainingSeconds == expectedRem)
        #expect(outcome.remainingSeconds > 300, "must not burn offline as practice")
    }

    @Test("Restore unstamped pause never false-finalizes")
    func restoreUnstampedPauseNoFinalize() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        // Wall far past total, but disk says paused without pauseStart
        let now = start.addingTimeInterval(900)
        let outcome = SessionRestorePolicy.resolve(
            now: now,
            start: start,
            totalDurationSeconds: 600,
            accumulatedPause: 0,
            diskPaused: true,
            diskPauseStart: nil,
            offlineSince: nil
        )
        #expect(outcome.treatAsPaused)
        #expect(!outcome.shouldFinalizeExpired, "missing pause stamp must not complete")
        #expect(outcome.remainingSeconds >= 1)
        #expect(outcome.openPauseStart == now)
    }

    @Test("Restore short offline blip stays running with wall remaining")
    func restoreShortOfflineBlipRunning() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let drop = start.addingTimeInterval(100)
        let now = drop.addingTimeInterval(30) // under 90s threshold
        let outcome = SessionRestorePolicy.resolve(
            now: now,
            start: start,
            totalDurationSeconds: 600,
            accumulatedPause: 0,
            diskPaused: false,
            diskPauseStart: nil,
            offlineSince: drop
        )
        #expect(!outcome.treatAsPaused)
        #expect(!outcome.shouldFinalizeExpired)
        #expect(outcome.openPauseStart == nil)
        #expect(outcome.remainingSeconds == 600 - 130)
    }

    @Test("Restore running past wall finalizes")
    func restoreRunningPastWallFinalizes() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let now = start.addingTimeInterval(650)
        let outcome = SessionRestorePolicy.resolve(
            now: now,
            start: start,
            totalDurationSeconds: 600,
            accumulatedPause: 0,
            diskPaused: false,
            diskPauseStart: nil,
            offlineSince: nil
        )
        #expect(outcome.shouldFinalizeExpired)
        #expect(outcome.remainingSeconds == 0)
        #expect(!outcome.treatAsPaused)
    }

    @Test("Restore jetsam lastAlive freezes remaining — does not burn dead wall")
    func restoreLastAliveFreeze() {
        // 600s session; alive until 100s; process dead 200s (gap past 90s); no offlineSince
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let lastAlive = start.addingTimeInterval(100)
        let now = lastAlive.addingTimeInterval(200)
        let outcome = SessionRestorePolicy.resolve(
            now: now,
            start: start,
            totalDurationSeconds: 600,
            accumulatedPause: 0,
            diskPaused: false,
            diskPauseStart: nil,
            offlineSince: nil,
            lastAlive: lastAlive
        )
        #expect(outcome.treatAsPaused)
        #expect(!outcome.shouldFinalizeExpired)
        #expect(outcome.openPauseStart == lastAlive)
        #expect(outcome.remainingSeconds == 500, "practice only to lastAlive")
    }

    @Test("Restore short lastAlive gap stays running")
    func restoreShortLastAliveGapRunning() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let lastAlive = start.addingTimeInterval(100)
        let now = lastAlive.addingTimeInterval(30) // under 90s
        let outcome = SessionRestorePolicy.resolve(
            now: now,
            start: start,
            totalDurationSeconds: 600,
            accumulatedPause: 0,
            diskPaused: false,
            diskPauseStart: nil,
            offlineSince: nil,
            lastAlive: lastAlive
        )
        #expect(!outcome.treatAsPaused)
        #expect(outcome.remainingSeconds == 600 - 130)
    }

    @Test("Breath phase presentation short Island labels")
    func breathPhaseLabels() {
        #expect(BreathPhasePresentation.statusText(phase: .inhale(progress: 0.2)) == "Inhale")
        #expect(BreathPhasePresentation.statusText(phase: .hold(progress: 0.5)) == "Hold")
        #expect(BreathPhasePresentation.statusText(phase: .exhale(progress: 0.8)) == "Exhale")
        #expect(BreathPhasePresentation.statusText(phase: .rest(progress: 0.1)) == "Rest")
        #expect(BreathPhasePresentation.statusText(phase: nil) == nil)
    }

    @Test("Pending off flushes on ready when idle")
    func pendingOffPolicyFlush() {
        #expect(PendingOffPolicy.shouldFlushOnReady(
            pendingDeactivate: true, isLinkReady: true, isRunning: false
        ))
        #expect(!PendingOffPolicy.shouldFlushOnReady(
            pendingDeactivate: true, isLinkReady: true, isRunning: true
        ))
        #expect(!PendingOffPolicy.shouldFlushOnReady(
            pendingDeactivate: true, isLinkReady: false, isRunning: false
        ))
        #expect(!PendingOffPolicy.shouldFlushOnReady(
            pendingDeactivate: false, isLinkReady: true, isRunning: false
        ))
    }

    @Test("BLE restore prefers durable off over reprogram when idle")
    func pendingOffPreferOnRestore() {
        #expect(PendingOffPolicy.shouldPreferOffOnRestore(
            pendingDeactivate: true, isRunning: false
        ))
        #expect(!PendingOffPolicy.shouldPreferOffOnRestore(
            pendingDeactivate: true, isRunning: true
        ))
        #expect(!PendingOffPolicy.shouldPreferOffOnRestore(
            pendingDeactivate: false, isRunning: false
        ))
    }

    @Test("Completed session LA copy is wall-honest and wellness-framed")
    func completedStatusHonesty() {
        let done = LiveActivityPresentation.completedStatus(modeName: "Stress", pendingDeviceOff: false)
        #expect(done.contains("complete"))
        #expect(done.contains("Stress"))
        #expect(!done.localizedCaseInsensitiveContains("treat"))
        #expect(!done.localizedCaseInsensitiveContains("heal"))
        let off = LiveActivityPresentation.completedStatus(modeName: "Sleep", pendingDeviceOff: true)
        #expect(off.contains("turning device off"))
        #expect(off.contains("Sleep"))
    }

    @Test("Privacy trust copy is clear and non-medical")
    func privacyTrustCopy() {
        #expect(PrivacyTrustCopy.nothingLeavesPhone.localizedCaseInsensitiveContains("phone"))
        #expect(PrivacyTrustCopy.privateByDesign.localizedCaseInsensitiveContains("no tracking"))
        #expect(!PrivacyTrustCopy.nothingLeavesPhone.localizedCaseInsensitiveContains("heal"))
    }

    @Test("Reminder copy is quiet and non-shaming")
    func reminderCopyQuiet() {
        let body = SessionReminderScheduler.body().lowercased()
        #expect(body.contains("ready") || body.contains("session"))
        #expect(!body.contains("missed"))
        #expect(!body.contains("streak"))
        #expect(SessionReminderScheduler.identifiers(morning: true, evening: true).count == 2)
        #expect(SessionReminderScheduler.identifiers(morning: false, evening: false).isEmpty)
    }
}

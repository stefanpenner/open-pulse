import Foundation
import Testing
@testable import OpenPulse

@Suite("SessionSafety")
struct SessionSafetyTests {
    @Test("Pending off banner hidden while session still running")
    func pendingOffBannerHonesty() {
        #expect(
            !PendingOffPresentation.shouldShowBanner(isRunning: true, pendingDeviceOff: true),
            "mid-run durable off must not claim turning off"
        )
        #expect(
            PendingOffPresentation.shouldShowBanner(isRunning: false, pendingDeviceOff: true),
            "paused/idle incomplete off shows banner"
        )
        #expect(
            !PendingOffPresentation.shouldShowBanner(isRunning: false, pendingDeviceOff: false)
        )
        #expect(
            !PendingOffPresentation.shouldShowBanner(isRunning: true, pendingDeviceOff: false)
        )
    }

    @Test("Off ACK while idle with no program traffic clears pending")
    func clearWhenIdleOffAck() {
        #expect(SessionSafety.shouldClearPendingDeactivate(
            command: "0\n",
            isRunning: false,
            hasPendingProgramWrites: false
        ))
    }

    @Test("Off ACK while program still queued does not clear")
    func noClearWhenProgramPending() {
        #expect(!SessionSafety.shouldClearPendingDeactivate(
            command: "0\n",
            isRunning: false,
            hasPendingProgramWrites: true
        ))
    }

    @Test("Off ACK while session running clears (start/resume lead-0 supersedes sticky off)")
    func clearWhileRunningLeadOff() {
        #expect(SessionSafety.shouldClearPendingDeactivate(
            command: "0\n",
            isRunning: true,
            hasPendingProgramWrites: true
        ), "lead-0 ACK clears durable off even if strength still queued")
        #expect(SessionSafety.shouldClearPendingDeactivate(
            command: "0\n",
            isRunning: true,
            hasPendingProgramWrites: false
        ))
    }

    @Test("Empty pack mid-session should pause when confirmed and not charging")
    func emptyBatteryPausePolicy() {
        #expect(SessionSafety.shouldPauseForEmptyBattery(
            isRunning: true, batteryPercent: 0, isCharging: false, sampleConfirmed: true
        ))
        #expect(!SessionSafety.shouldPauseForEmptyBattery(
            isRunning: true, batteryPercent: 0, isCharging: true, sampleConfirmed: true
        ), "charging empty may recover")
        #expect(!SessionSafety.shouldPauseForEmptyBattery(
            isRunning: true, batteryPercent: 0, isCharging: false, sampleConfirmed: false
        ), "unconfirmed empty is start-gate only")
        #expect(!SessionSafety.shouldPauseForEmptyBattery(
            isRunning: false, batteryPercent: 0, isCharging: false, sampleConfirmed: true
        ))
        #expect(!SessionSafety.shouldPauseForEmptyBattery(
            isRunning: true, batteryPercent: 20, isCharging: false, sampleConfirmed: true
        ))
    }

    @Test("Short foreground return while linked skips absolute reassert")
    func shortForegroundSkipReassert() {
        #expect(
            !SessionSafety.shouldReassertDeviceOnForeground(
                isLinkReady: true,
                secondsInBackground: 3,
                wasMarkedOffline: false,
                reassertAfterSeconds: 15
            ),
            "app switch must not blip stim with lead-0"
        )
        #expect(
            SessionSafety.shouldReassertDeviceOnForeground(
                isLinkReady: true,
                secondsInBackground: 20,
                wasMarkedOffline: false,
                reassertAfterSeconds: 15
            ),
            "long BG reasserts for duty honesty"
        )
        #expect(
            SessionSafety.shouldReassertDeviceOnForeground(
                isLinkReady: true,
                secondsInBackground: 2,
                wasMarkedOffline: true,
                reassertAfterSeconds: 15
            ),
            "offline window needs reassert when link is back"
        )
        #expect(
            !SessionSafety.shouldReassertDeviceOnForeground(
                isLinkReady: false,
                secondsInBackground: 30,
                wasMarkedOffline: true,
                reassertAfterSeconds: 15
            ),
            "no link → ready sink reasserts later"
        )
        #expect(
            SessionSafety.shouldReassertDeviceOnForeground(
                isLinkReady: true,
                secondsInBackground: nil,
                wasMarkedOffline: false,
                reassertAfterSeconds: 15
            ),
            "unknown duration reasserts"
        )
    }

    @Test("isDeactivateCommand is exact off only — not any 0 prefix")
    func deactivateCommandExactOnly() {
        #expect(SessionSafety.isDeactivateCommand("0\n"))
        #expect(SessionSafety.isDeactivateCommand("0"))
        #expect(SessionSafety.isDeactivateCommand(" 0\n "))
        #expect(SessionSafety.isDeactivateCommand(BLEConstants.deactivateCommand))
        // Strength / future traffic must not look like off ACK
        #expect(!SessionSafety.isDeactivateCommand("5\n"))
        #expect(!SessionSafety.isDeactivateCommand("01\n"))
        #expect(!SessionSafety.isDeactivateCommand("0xA\n"))
        #expect(!SessionSafety.isDeactivateCommand("Q\n"))
        #expect(!SessionSafety.isDeactivateCommand(""))
    }

    @Test("Non-off writes never clear pending")
    func strengthDoesNotClear() {
        #expect(!SessionSafety.shouldClearPendingDeactivate(
            command: "5\n",
            isRunning: false,
            hasPendingProgramWrites: false
        ))
    }

    @Test("Status-only queue does not block clear (hasPendingProgramWrites false)")
    func statusDoesNotBlock() {
        #expect(SessionSafety.shouldClearPendingDeactivate(
            command: "0\n",
            isRunning: false,
            hasPendingProgramWrites: false
        ))
    }
}

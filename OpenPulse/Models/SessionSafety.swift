import Foundation

/// UI honesty for durable hardware-off surfaces.
enum PendingOffPresentation {
    /// Banner is for incomplete stop/pause off — not mid-run reconnect (session still active).
    /// Mid-run drop arms durable pending for process death, but UI must not claim "turning off"
    /// while the session is still running and will reprogram on ready.
    static func shouldShowBanner(isRunning: Bool, pendingDeviceOff: Bool) -> Bool {
        pendingDeviceOff && !isRunning
    }
}

/// Pure session/hardware safety decisions (testable without CoreBluetooth).
enum SessionSafety {
    /// Whether a confirmed write should clear sticky durable pending-off.
    /// - Idle/paused: clear only when off ACK and no program traffic still queued.
    /// - Running: start/resume lead-0 may clear sticky off once off is confirmed
    ///   (even if strength/channel still queued) — never clear optimistically before ACK.
    static func shouldClearPendingDeactivate(
        command: String,
        isRunning: Bool,
        hasPendingProgramWrites: Bool
    ) -> Bool {
        guard isDeactivateCommand(command) else { return false }
        if isRunning {
            // Lead-0 of active session program — durable off superseded once off lands
            return true
        }
        // Status queries may still be queued; only program traffic blocks clear.
        return !hasPendingProgramWrites
    }

    /// Returning to the app after a short switch must not force lead-0 off+reprogram.
    /// That blips (or drops) stim while the device was still running in the background.
    /// Reassert only after a long gap, after an offline window, or when duration is unknown.
    /// - Parameter reassertAfterSeconds: match continuous absolute reassert gap (15s default).
    static func shouldReassertDeviceOnForeground(
        isLinkReady: Bool,
        secondsInBackground: TimeInterval?,
        wasMarkedOffline: Bool,
        reassertAfterSeconds: TimeInterval = 15
    ) -> Bool {
        // No link: ready-sink will reassert when UART returns
        guard isLinkReady else { return false }
        if wasMarkedOffline { return true }
        guard let secondsInBackground else {
            // Unknown duration (e.g. missing entry stamp) — prefer honesty reassert
            return true
        }
        return secondsInBackground >= reassertAfterSeconds
    }

    /// Mid-session confirmed empty pack (not charging) → pause for comfort/safety.
    static func shouldPauseForEmptyBattery(
        isRunning: Bool,
        batteryPercent: Int?,
        isCharging: Bool?,
        sampleConfirmed: Bool
    ) -> Bool {
        guard isRunning, sampleConfirmed, isCharging != true else { return false }
        guard let pct = batteryPercent else { return false }
        return BatteryPresentation.isEmpty(percent: pct)
    }

    /// True only for absolute hardware-off (`0` / `0\n`), not every `0…` prefix.
    /// Over-broad `hasPrefix("0")` could treat future `0x…` style traffic as off ACK
    /// and clear durable pending-off while the pack is still on.
    static func isDeactivateCommand(_ command: String) -> Bool {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "0" || command == BLEConstants.deactivateCommand
    }
}

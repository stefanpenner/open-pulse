import Foundation

/// Pure connection status copy (StatusBar / empty state a11y).
enum ConnectionPresentation {
    /// VoiceOver / user-facing link state (matches StatusBar chip).
    static func accessibilityLabel(
        isBluetoothOff: Bool,
        isConnected: Bool,
        isReady: Bool
    ) -> String {
        if isBluetoothOff { return "Bluetooth Off" }
        if isConnected && isReady { return "Connected" }
        if isConnected { return "Connecting" }
        return "Searching for device"
    }

    /// Short chip text (UI).
    static func chipText(
        isBluetoothOff: Bool,
        isConnected: Bool,
        isReady: Bool
    ) -> String {
        if isBluetoothOff { return "Bluetooth Off" }
        if isConnected && isReady { return "Connected" }
        if isConnected { return "Connecting…" }
        return "Searching…"
    }

    /// Full-width empty-state title when device is not ready.
    static func emptyTitle(
        isBluetoothOff: Bool,
        isConnected: Bool,
        isReady: Bool
    ) -> String {
        if isBluetoothOff { return "Bluetooth is off" }
        if isConnected && isReady { return "Connected" }
        if isConnected { return "Finishing connection" }
        return "Looking for your Pulsetto"
    }

    /// Guidance under the empty-state title.
    static func emptyDetail(
        isBluetoothOff: Bool,
        isConnected: Bool,
        isReady: Bool,
        batteryPercent: Int? = nil,
        isCharging: Bool? = nil,
        batterySampleConfirmed: Bool = true
    ) -> String {
        if isBluetoothOff {
            return "Turn on Bluetooth in Control Center, then come back."
        }
        if isConnected && isReady {
            return "Device is ready for a session."
        }
        // Battery honesty while searching/connecting (Still empty state)
        if let pct = batteryPercent {
            let percent = max(0, min(100, pct))
            if BatteryPresentation.isEmpty(percent: pct) {
                return noted(
                    "Battery is empty — charge your Pulsetto before a session.",
                    confirmed: batterySampleConfirmed
                )
            }
            if BatteryPresentation.isLow(percent: pct, isCharging: isCharging) {
                return noted(
                    "Battery low (\(percent)%). Session may end early — charge soon.",
                    confirmed: batterySampleConfirmed
                )
            }
            if !batterySampleConfirmed {
                return "Last battery \(percent)% — confirming after reconnect."
            }
        }
        if isConnected {
            return "Almost there — setting up the device link."
        }
        return "Wear the device and keep it nearby. We’ll connect automatically."
    }

    private static func noted(_ text: String, confirmed: Bool) -> String {
        confirmed ? text : "\(text) (last known)"
    }
}

/// Pure battery chip helpers (testable without UIKit / BLE).
enum BatteryPresentation {
    /// Empty pack (0%) — distinct from low for VO honesty.
    static func isEmpty(percent: Int) -> Bool {
        percent <= 0
    }

    /// Matches `BLEConstants.lowBatteryThresholdPercent` — local so widget target
    /// can compile presentation without CoreBluetooth BLEConstants.
    static let lowBatteryThresholdPercent = 15

    /// Low warn unless we *know* the pack is charging (`true` suppresses; `nil`/false still warn).
    static func isLow(
        percent: Int,
        isCharging: Bool?,
        threshold: Int = lowBatteryThresholdPercent
    ) -> Bool {
        guard isCharging != true else { return false }
        return percent <= threshold
    }

    /// Seconds after link-ready to await first battery reading before allowing Start on nil.
    /// Escape so mute UART never bricks Start forever.
    static let unknownGraceSeconds: TimeInterval = 2.0

    /// Block new sessions when pack is empty and not charging.
    /// - Unconfirmed sample (stale cache after reconnect): treat as unknown during grace.
    /// - Cached empty still blocks even when unconfirmed (honest).
    /// - After grace, unconfirmed non-empty allows Start (mute UART cannot brick).
    static func blocksStart(
        percent: Int?,
        isCharging: Bool?,
        sampleConfirmed: Bool = true,
        secondsSinceReady: TimeInterval? = nil,
        graceSeconds: TimeInterval = unknownGraceSeconds
    ) -> Bool {
        if isCharging == true { return false }
        // Cached / live empty always blocks when not charging
        if let pct = percent, isEmpty(percent: pct) {
            return true
        }
        if sampleConfirmed {
            // Confirmed non-empty or confirmed nil (rare) — only nil needs grace
            if percent != nil { return false }
            guard let elapsed = secondsSinceReady else { return false }
            return elapsed < graceSeconds
        }
        // Unconfirmed: await fresh Q during grace (stale % must not skip gate)
        guard let elapsed = secondsSinceReady else { return false }
        return elapsed < graceSeconds
    }

    /// Start-gate copy when empty pack or mid-read blocks a session.
    static let startBlockedEmptyCopy = "Charge your Pulsetto"
    static let startBlockedReadingCopy = "Checking battery…"

    /// User-facing Start block reason (nil when not blocked by battery).
    static func startBlockedReason(
        percent: Int?,
        isCharging: Bool?,
        sampleConfirmed: Bool = true,
        secondsSinceReady: TimeInterval? = nil,
        graceSeconds: TimeInterval = unknownGraceSeconds
    ) -> String? {
        guard blocksStart(
            percent: percent,
            isCharging: isCharging,
            sampleConfirmed: sampleConfirmed,
            secondsSinceReady: secondsSinceReady,
            graceSeconds: graceSeconds
        ) else { return nil }
        // Empty (cached or live) — charge copy takes priority
        if let pct = percent, isEmpty(percent: pct) {
            return startBlockedEmptyCopy
        }
        // Unconfirmed or nil — still reading
        return startBlockedReadingCopy
    }

    static func accessibilityLabel(
        percent: Int,
        isCharging: Bool?,
        isLow: Bool,
        sampleConfirmed: Bool = true
    ) -> String {
        var parts: [String] = []
        let pct = max(0, min(100, percent))
        if isEmpty(percent: pct) { parts.append("Battery empty") }
        else if isLow { parts.append("Battery low") }
        else { parts.append("Battery") }
        parts.append("\(pct) percent")
        if !sampleConfirmed { parts.append("last known") }
        if isCharging == true { parts.append("charging") }
        return parts.joined(separator: ", ")
    }

    /// Chip text — appends "· last" when sample is unconfirmed after reconnect.
    static func chipText(percent: Int, sampleConfirmed: Bool) -> String {
        let pct = max(0, min(100, percent))
        if sampleConfirmed { return "\(pct)%" }
        return "\(pct)% · last"
    }

    static func iconName(percent: Int) -> String {
        switch max(0, min(100, percent)) {
        case 0..<13: "battery.0percent"
        case 13..<38: "battery.25percent"
        case 38..<63: "battery.50percent"
        case 63..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

/// Mid-session link-drop safety (surprise re-stim prevention).
enum SessionLinkSafety {
    /// After this long offline while running, auto-pause + durable HW off.
    /// Short BLE blips still soft-reconnect without pause.
    static let offlineAutoPauseSeconds: TimeInterval = 90

    /// True when a running session has been offline long enough to pause for comfort/safety.
    static func shouldAutoPause(
        isRunning: Bool,
        isLinkReady: Bool,
        secondsOffline: TimeInterval?
    ) -> Bool {
        guard isRunning, !isLinkReady, let elapsed = secondsOffline else { return false }
        return elapsed >= offlineAutoPauseSeconds
    }

    /// What a ready edge does after a drop.
    /// A long gap pauses at the freeze instant. A short blip resumes.
    enum ReadyAfterDrop: Equatable {
        case resume
        case pause(freeze: Date)
    }

    static func readyAfterDrop(
        isRunning: Bool,
        offlineSince: Date?,
        now: Date
    ) -> ReadyAfterDrop {
        guard isRunning, let offlineSince else { return .resume }
        let seconds = now.timeIntervalSince(offlineSince)
        guard seconds >= offlineAutoPauseSeconds else { return .resume }
        return .pause(freeze: autoPauseFreezeDate(offlineSince: offlineSince))
    }

    /// Remaining sleep until auto-pause (0 if already past threshold).
    /// Use after process restore so we don't wait a full 90s again.
    static func remainingAutoPauseDelay(
        secondsOffline: TimeInterval?,
        limit: TimeInterval = offlineAutoPauseSeconds
    ) -> TimeInterval {
        guard let elapsed = secondsOffline else { return limit }
        return max(0, limit - elapsed)
    }

    /// Wall time when auto-pause freezes the session clock.
    /// Live wake and kill restore both use this instant.
    /// A late timer must not count time after the threshold as practice.
    static func autoPauseFreezeDate(
        offlineSince: Date,
        limit: TimeInterval = offlineAutoPauseSeconds
    ) -> Date {
        offlineSince.addingTimeInterval(limit)
    }
}

/// Pure policy for LA endsAt → session complete ordering (Still honesty).
enum LiveActivityEndPolicy {
    /// After complete hook: end LA only when session confirms complete (or unbound).
    /// Never end-before-confirm (that shows "Session complete" while stim may continue).
    /// - Parameter sessionConfirmedComplete: bridge/VM says session ended (or unbound cold path).
    static func shouldEndAsCompleted(
        activityStillCurrent: Bool,
        sessionConfirmedComplete: Bool
    ) -> Bool {
        activityStillCurrent && sessionConfirmedComplete
    }

    /// Active practice seconds (pause wall-time excluded).
    /// - When `isPaused` and `pauseStart` is missing, open pause is treated as
    ///   starting at `now` only (does not invent earlier pause) — callers that
    ///   need strict unbound honesty should use `shouldConfirmUnboundComplete`.
    static func activeElapsedSeconds(
        now: Date,
        start: Date,
        accumulatedPause: TimeInterval,
        pauseStart: Date?,
        isPaused: Bool = false
    ) -> TimeInterval {
        var pause = max(0, accumulatedPause)
        if let pauseStart {
            pause += max(0, now.timeIntervalSince(pauseStart))
        } else if isPaused {
            // Stamp missing: do not invent past pause; open segment starts at now → +0
            // Combined with shouldConfirmUnboundComplete refuse-when-paused-unstamped.
            pause += 0
        }
        return max(0, now.timeIntervalSince(start) - pause)
    }

    /// True when wall-clock active time meets planned duration (Island endsAt honesty).
    static func shouldCompleteSession(
        now: Date,
        start: Date?,
        totalDurationSeconds: Int,
        accumulatedPause: TimeInterval = 0,
        pauseStart: Date? = nil,
        isPaused: Bool = false
    ) -> Bool {
        guard let start, totalDurationSeconds > 0 else { return false }
        return activeElapsedSeconds(
            now: now,
            start: start,
            accumulatedPause: accumulatedPause,
            pauseStart: pauseStart,
            isPaused: isPaused
        ) >= Double(totalDurationSeconds)
    }

    /// Open-pause start for wall math (matches kill-restore offline freeze).
    /// - Explicit `pauseStart` wins.
    /// - Else if offline past auto-pause limit: freeze at `offlineSince + limit`
    ///   (practice stops accruing after threshold — same as live auto-pause).
    static func resolveOpenPauseStart(
        now: Date,
        pauseStart: Date?,
        offlineSince: Date?,
        offlineAutoPauseLimit: TimeInterval = SessionLinkSafety.offlineAutoPauseSeconds
    ) -> Date? {
        if let pauseStart { return pauseStart }
        guard let offlineSince else { return nil }
        let freeze = SessionLinkSafety.autoPauseFreezeDate(
            offlineSince: offlineSince,
            limit: offlineAutoPauseLimit
        )
        // Only apply freeze once threshold has been reached
        guard now >= freeze else { return nil }
        return freeze
    }

    /// Unbound cold path at LA endsAt: claim complete only if no live session
    /// or the persisted session’s wall clock is already past planned end.
    /// Prevents “Session complete” after process death while remaining > 0.
    ///
    /// Paused + missing `pauseStart` cannot prove wall past honestly (open pause
    /// would be counted as practice) — keep LA until restore rebinds VM.
    ///
    /// Durable `offlineSince` past auto-pause freeze must not count offline as practice.
    static func shouldConfirmUnboundComplete(
        now: Date,
        persistedStart: Date?,
        totalDurationSeconds: Int,
        accumulatedPause: TimeInterval = 0,
        pauseStart: Date? = nil,
        isPaused: Bool = false,
        offlineSince: Date? = nil
    ) -> Bool {
        guard persistedStart != nil, totalDurationSeconds > 0 else {
            // No durable session — safe to dismiss LA
            return true
        }
        // Corrupt/missing open-pause stamp while paused: refuse false complete
        // (unless offline freeze supplies an open-pause start)
        let openPause = resolveOpenPauseStart(
            now: now,
            pauseStart: pauseStart,
            offlineSince: offlineSince
        )
        if isPaused, openPause == nil {
            return false
        }
        return shouldCompleteSession(
            now: now,
            start: persistedStart,
            totalDurationSeconds: totalDurationSeconds,
            accumulatedPause: accumulatedPause,
            pauseStart: openPause,
            isPaused: isPaused || openPause != nil
        )
    }
}

/// Pure kill-restore remaining / finalize decision (wall + offline freeze honesty).
enum SessionRestorePolicy {
    struct Outcome: Equatable, Sendable {
        var remainingSeconds: Int
        /// Open pause stamp to apply (disk, offline freeze, or `now` for unstamped).
        var openPauseStart: Date?
        var shouldFinalizeExpired: Bool
        var treatAsPaused: Bool
    }

    /// Resolve remaining after process death.
    /// - Long offline → auto-paused at freeze date (not drop time).
    /// - Jetsam with no offline stamp → freeze at lastAlive (do not burn dead wall).
    /// - Paused without stamp → never false-complete; keep paused with floor remaining ≥ 1.
    static func resolve(
        now: Date,
        start: Date,
        totalDurationSeconds: Int,
        accumulatedPause: TimeInterval,
        diskPaused: Bool,
        diskPauseStart: Date?,
        offlineSince: Date?,
        lastAlive: Date? = nil
    ) -> Outcome {
        guard totalDurationSeconds > 0 else {
            return Outcome(
                remainingSeconds: 0,
                openPauseStart: nil,
                shouldFinalizeExpired: true,
                treatAsPaused: false
            )
        }

        var treatPaused = diskPaused
        var openPause = diskPauseStart

        // Mid-run offline past threshold → same as live auto-pause freeze
        if !treatPaused, let offlineSince {
            let offlineSeconds = now.timeIntervalSince(offlineSince)
            if SessionLinkSafety.shouldAutoPause(
                isRunning: true,
                isLinkReady: false,
                secondsOffline: offlineSeconds
            ) {
                treatPaused = true
                openPause = SessionLinkSafety.autoPauseFreezeDate(offlineSince: offlineSince)
            }
        }

        // Process death while still "running" with no offlineSince (jetsam / force quit).
        // Do not count wall after last known alive tick as practice.
        if !treatPaused, offlineSince == nil, let lastAlive {
            let gap = now.timeIntervalSince(lastAlive)
            if gap >= SessionLinkSafety.offlineAutoPauseSeconds {
                treatPaused = true
                // Freeze remaining at lastAlive (not lastAlive+90 — no stim after death known)
                openPause = lastAlive
            }
        }

        if treatPaused {
            // Unstamped pause (no disk pauseStart and no offline freeze): refuse finalize
            if openPause == nil {
                let active = LiveActivityEndPolicy.activeElapsedSeconds(
                    now: now,
                    start: start,
                    accumulatedPause: accumulatedPause,
                    pauseStart: nil,
                    isPaused: false
                )
                let rem = max(0, totalDurationSeconds - Int(active))
                return Outcome(
                    remainingSeconds: max(1, rem == 0 ? 1 : rem),
                    openPauseStart: now,
                    shouldFinalizeExpired: false,
                    treatAsPaused: true
                )
            }
            let active = LiveActivityEndPolicy.activeElapsedSeconds(
                now: now,
                start: start,
                accumulatedPause: accumulatedPause,
                pauseStart: openPause,
                isPaused: true
            )
            let rem = max(0, totalDurationSeconds - Int(active))
            if rem <= 0 {
                return Outcome(
                    remainingSeconds: 0,
                    openPauseStart: openPause,
                    shouldFinalizeExpired: true,
                    treatAsPaused: true
                )
            }
            return Outcome(
                remainingSeconds: rem,
                openPauseStart: openPause,
                shouldFinalizeExpired: false,
                treatAsPaused: true
            )
        }

        // Still running (short offline blip possible)
        let active = LiveActivityEndPolicy.activeElapsedSeconds(
            now: now,
            start: start,
            accumulatedPause: accumulatedPause,
            pauseStart: nil,
            isPaused: false
        )
        let rem = max(0, totalDurationSeconds - Int(active))
        if rem <= 0 {
            return Outcome(
                remainingSeconds: 0,
                openPauseStart: nil,
                shouldFinalizeExpired: true,
                treatAsPaused: false
            )
        }
        return Outcome(
            remainingSeconds: rem,
            openPauseStart: nil,
            shouldFinalizeExpired: false,
            treatAsPaused: false
        )
    }
}

/// Pure intensity 1…9 policy (device UART range). One-hand / Island nudge safe.
/// Lives here so app + widget extension share without CoreBluetooth deps.
/// Cold-launch / BG / BLE-restore path: durable HW-off before any session reprogram.
enum PendingOffPolicy {
    /// Flush deactivate when pending and link ready — even with no active session.
    static func shouldFlushOnReady(
        pendingDeactivate: Bool,
        isLinkReady: Bool,
        isRunning: Bool
    ) -> Bool {
        pendingDeactivate && isLinkReady && !isRunning
    }

    /// After process death + BLE restore: prefer safety off over mid-session reprogram
    /// when durable pending-off is set and the session is not actively running.
    static func shouldPreferOffOnRestore(
        pendingDeactivate: Bool,
        isRunning: Bool
    ) -> Bool {
        pendingDeactivate && !isRunning
    }
}

/// Privacy / trust copy (unit-tested — wellness framing, no medical claims).
enum PrivacyTrustCopy {
    /// One-line brand promise on Privacy sheet.
    static let nothingLeavesPhone = "Nothing leaves this phone."

    static let privateByDesign =
        "Private by design — no accounts, no cloud, no tracking."
}

enum StrengthPresentation {
    static let minLevel = 1
    static let maxLevel = 9

    static func clamp(_ value: Int) -> Int {
        max(minLevel, min(maxLevel, value))
    }

    /// Apply delta and clamp (Shortcuts / Island ±).
    static func nudge(_ current: Int, by delta: Int) -> Int {
        clamp(current + delta)
    }

    static func canIncrease(_ current: Int) -> Bool {
        clamp(current) < maxLevel
    }

    static func canDecrease(_ current: Int) -> Bool {
        clamp(current) > minLevel
    }

    /// Island / Lock Screen: offer ± when a session is live (running or paused).
    /// Offline still OK — model updates for next reprogram (no surprise auto-start).
    static func showsLiveActivityNudge(isPaused: Bool, remainingSeconds: Int) -> Bool {
        isPaused || remainingSeconds > 0
    }
}

enum LiveActivityPresentation {
    /// Session progress 0…1 for lock screen / Dynamic Island.
    static func progress(remainingSeconds: Int, totalSeconds: Int) -> Double {
        let total = max(1, totalSeconds)
        let remaining = max(0, remainingSeconds)
        return min(1, max(0, 1.0 - Double(remaining) / Double(total)))
    }

    /// Glanceable status — wellness framing only.
    static func statusLine(
        isPaused: Bool,
        isRunning: Bool,
        pendingDeviceOff: Bool,
        modeStatus: String,
        modeName: String,
        isLinkReady: Bool
    ) -> String {
        // Pending off wins while paused (incomplete HW stop)
        if pendingDeviceOff, isPaused {
            return "Paused · stopping device"
        }
        if pendingDeviceOff, !isRunning {
            return "Turning device off"
        }
        // Always honest about pause — never show stale stim phase copy on Island
        if isPaused {
            // Match app: resume needs ready link
            if !isLinkReady { return "Paused · waiting for device" }
            return "Paused"
        }
        if isRunning, !isLinkReady {
            return "Reconnecting…"
        }
        if modeStatus.isEmpty {
            return modeName.isEmpty ? "In session" : modeName
        }
        return modeStatus
    }

    /// Compact Island SF Symbol — honest about power-off / link / pause / rest.
    /// Power only when pending-off is *user-visible* (paused/idle) — mid-run durable
    /// pending is reconnect, not “turning off” (matches app banner honesty).
    static func compactIconName(
        isPaused: Bool,
        isRunning: Bool,
        pendingDeviceOff: Bool,
        isLinkReady: Bool,
        isStimulationActive: Bool
    ) -> String {
        // Same rule as PendingOffPresentation.shouldShowBanner (widget has no SessionSafety)
        if claimsPendingOffChrome(isRunning: isRunning, pendingDeviceOff: pendingDeviceOff) {
            return "power"
        }
        // Link-down wins over pause so Island matches "Reconnecting…" / waiting copy
        if !isLinkReady { return "antenna.radiowaves.left.and.right" }
        if isPaused { return "pause.fill" }
        if !isStimulationActive { return "moon.zzz" }
        return "waveform.path.ecg"
    }

    /// True when Island accent should claim “turning off” (orange).
    /// Mid-run durable pending must not orange-power (session still active).
    static func claimsPendingOffChrome(
        isRunning: Bool,
        pendingDeviceOff: Bool
    ) -> Bool {
        pendingDeviceOff && !isRunning
    }

    /// Compact / minimal Island VoiceOver — prefer VM statusText; fallbacks match statusLine.
    static func compactAccessibility(
        statusText: String,
        isPaused: Bool,
        isRunning: Bool = false,
        pendingDeviceOff: Bool,
        isLinkReady: Bool = true
    ) -> String {
        if !statusText.isEmpty {
            return statusText
        }
        // Same honesty as statusLine — pass real isRunning so mid-run pending
        // does not fall into "Turning device off".
        let line = statusLine(
            isPaused: isPaused,
            isRunning: isRunning,
            pendingDeviceOff: pendingDeviceOff,
            modeStatus: "",
            modeName: "",
            isLinkReady: isLinkReady
        )
        return line == "In session" ? "Open Pulse session" : line
    }

    /// VoiceOver for remaining time on Island / lock screen.
    static func timeAccessibility(remainingSeconds: Int) -> String {
        let t = max(0, remainingSeconds)
        let m = t / 60
        let s = t % 60
        if m > 0 {
            return "\(m) minutes \(s) seconds remaining"
        }
        return "\(s) seconds remaining"
    }

    /// Zero-padded mm:ss for Island / lock screen.
    static func formatTime(_ total: Int) -> String {
        let t = max(0, total)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    /// Glanceable LA control (pause / resume / stop). Single action per HIG.
    enum ControlAction: Equatable, Sendable {
        case pause
        case resume
        case stop
        case none
    }

    /// Which control to offer.
    /// - Resume only when paused + link ready + HW not mid-off.
    /// - Stop when paused but cannot resume (offline / stopping) — never trap Island.
    /// - Stop when running offline (mid-drop escape) — Pause only when link ready.
    /// - Stop when idle + pending off (completed linger) — re-arm HW off, never trap.
    /// - Pause while running with ready link (no pending off).
    static func controlAction(
        isPaused: Bool,
        isRunning: Bool,
        pendingDeviceOff: Bool,
        isLinkReady: Bool
    ) -> ControlAction {
        if isPaused {
            if isLinkReady && !pendingDeviceOff {
                return .resume
            }
            // Offline or HW still stopping — Stop ends session (Shortcuts parity)
            return .stop
        }
        if isRunning {
            if pendingDeviceOff {
                // Rare mid-run off pending — Stop is safer escape than no control
                return .stop
            }
            // Mid-session link drop: one-tap end, not Pause→Stop trap
            return isLinkReady ? .pause : .stop
        }
        // Idle / completed linger
        if pendingDeviceOff {
            // Session complete while HW still stopping — Stop re-arms off (idle Stop path)
            return .stop
        }
        return .none
    }

    /// Expanded lock-screen status when statusText empty (widget fallback).
    static func lockScreenFallback(
        isPaused: Bool,
        isRunning: Bool = false,
        pendingDeviceOff: Bool,
        isLinkReady: Bool = true
    ) -> String {
        statusLine(
            isPaused: isPaused,
            isRunning: isRunning,
            pendingDeviceOff: pendingDeviceOff,
            modeStatus: "",
            modeName: "",
            isLinkReady: isLinkReady
        )
    }

    /// Session end wall time for system-driven LA countdown (nil when frozen/paused/offline).
    /// Offline freezes the Island timer so system countdown cannot hit 00:00 while
    /// session remaining is still >0 (kill-restore soft pause / reconnect honesty).
    static func endsAt(
        remainingSeconds: Int,
        isPaused: Bool,
        isLinkReady: Bool = true,
        now: Date = Date()
    ) -> Date? {
        guard isLinkReady, !isPaused, remainingSeconds > 0 else { return nil }
        return now.addingTimeInterval(TimeInterval(remainingSeconds))
    }

    /// Whether the widget should use Text(timerInterval:) vs static formatTime.
    /// Offline freezes even if a stale endsAt leaked in.
    /// Past endsAt also freezes — process-dead ContentState must not show 00:00
    /// while remainingSeconds is still >0 (static formatTime is honest).
    static func usesLiveCountdown(
        endsAt: Date?,
        isPaused: Bool,
        isLinkReady: Bool = true,
        now: Date = Date()
    ) -> Bool {
        guard isLinkReady, !isPaused, let endsAt else { return false }
        return endsAt > now
    }

    /// Final glanceable copy when a session finishes (wellness only).
    /// Lock-screen complete copy. When hardware off is still pending, say so (Still honesty).
    static func completedStatus(modeName: String, pendingDeviceOff: Bool = false) -> String {
        let name = modeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = name.isEmpty ? "Session complete" : "Session complete · \(name)"
        if pendingDeviceOff {
            return "\(head) · turning device off"
        }
        return head
    }

    /// How long the completed LA may linger on Lock Screen after end.
    static let completedDismissalSeconds: TimeInterval = 30
}

import Foundation

/// Durable bridge for Live Activity intents → session VM.
/// Intents must not rely on ContentView `onReceive` alone (cold start loses NC).
@MainActor
final class SessionActionBridge {
    /// Production singleton (App Intents / Live Activity share process).
    static let shared = SessionActionBridge()

    /// Max age for deferred Start / Resume (Shortcuts / Island while link down).
    /// Prevents surprise stim when the device connects much later.
    static let intentPendingTTL: TimeInterval = 90

    /// Alias — Start tests and call sites use this name.
    static var startPendingTTL: TimeInterval { intentPendingTTL }

    enum Pending: Equatable {
        case pause
        case resume
        case start
        case stop
        case complete
    }

    private weak var session: SessionViewModel?
    private(set) var pending: Pending?
    /// Wall deadline for deferred `.start` / `.resume` (nil when neither pending).
    private var pendingIntentDeadline: Date?

    /// Clock for TTL tests; production uses wall clock.
    var now: () -> Date = { Date() }

    /// Open for unit tests; production uses `shared`.
    init() {
        // Widget-extension intents post Darwin notifies; deliver into this process.
        installIntentRelayObservers()
    }

    /// Call once when the session UI binds a VM.
    func bind(_ vm: SessionViewModel) {
        session = vm
        drainPending()
    }

    /// Observe Island/widget Darwin intent signals (app process only).
    private func installIntentRelayObservers() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let names = [
            OpenPulseIntentRelay.pause,
            OpenPulseIntentRelay.resume,
            OpenPulseIntentRelay.start,
            OpenPulseIntentRelay.stop,
            OpenPulseIntentRelay.intensityUp,
            OpenPulseIntentRelay.intensityDown,
        ]
        let observer = Unmanaged.passUnretained(self).toOpaque()
        for name in names {
            CFNotificationCenterAddObserver(
                center,
                observer,
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let bridge = Unmanaged<SessionActionBridge>.fromOpaque(observer)
                        .takeUnretainedValue()
                    let raw = name.rawValue as String
                    Task { @MainActor in
                        switch raw {
                        case OpenPulseIntentRelay.pause: bridge.requestPause()
                        case OpenPulseIntentRelay.resume: bridge.requestResume()
                        case OpenPulseIntentRelay.start: bridge.requestStart()
                        case OpenPulseIntentRelay.stop: bridge.requestStop()
                        case OpenPulseIntentRelay.intensityUp: bridge.requestNudgeStrength(by: 1)
                        case OpenPulseIntentRelay.intensityDown: bridge.requestNudgeStrength(by: -1)
                        default: break
                        }
                    }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
    }

    func unbind(_ vm: SessionViewModel) {
        if session === vm {
            session = nil
        }
    }

    func requestPause() {
        if let s = session {
            if s.isRunning {
                s.pause()
            }
            // Bound but not running (complete/idle/paused) — never stash stale pause
            clearPending()
            return
        }
        // Unbound only — cold-start race before ContentView binds
        clearIntentDeadline()
        pending = .pause
    }

    func requestResume() {
        if let s = session, s.isPaused, s.canResume {
            s.resume()
            clearPending()
            return
        }
        if session != nil, let s = session, !s.isPaused {
            // Bound idle/running — drop stale resume
            clearPending()
            return
        }
        // Bound paused (not ready) or unbound — wait for ready drain (bounded TTL)
        armResumePending()
    }

    /// Siri / Shortcuts start — only when idle + link ready (SessionBLE Start guard).
    /// Bound + not ready stashes pending with TTL; ready alone never auto-starts.
    /// Empty pack never stashes (ready or not) — charge then start again.
    func requestStart() {
        guard let s = session else {
            armStartPending()
            return
        }
        switch startGate(s) {
        case .now:
            s.start()
            clearPending()
        case .drop:
            clearPending()
        case .hold:
            armStartPending()
        }
    }

    /// Island / Shortcuts intensity ± (one-hand, on-device only).
    /// Bound session only — no deferred pending (never surprise-stim after disconnect).
    func requestNudgeStrength(by delta: Int) {
        guard let s = session else { return }
        guard s.isRunning || s.isPaused else { return }
        let next = StrengthPresentation.nudge(s.strength, by: delta)
        s.setStrength(next)
    }

    /// Siri / Shortcuts / Island stop — ends session + durable hardware off.
    /// Bound idle re-arms HW off (ACK race / sticky pending dropped).
    func requestStop() {
        if let s = session {
            if s.isRunning || s.isPaused {
                s.stop(reason: .user)
            } else {
                // Idle — still re-assert off so Island Stop never no-ops
                s.requestHardwareOffIfIdle()
            }
            clearPending()
            return
        }
        // Unbound: durable off so HW stops when process restores
        AppPreferences.setPendingDeactivate(true)
        clearIntentDeadline()
        pending = .stop
    }

    /// LA / Island endsAt — wall-honest complete; durable pending-off if unbound.
    /// - Returns `true` when LA should show completed (session ended, or unbound cold path).
    /// - Returns `false` when bound session is still active (wall not past) — keep LA.
    @discardableResult
    func requestComplete() -> Bool {
        if let s = session {
            let wasActive = s.isRunning || s.isPaused
            s.honorLiveActivitySessionEnd()
            clearPending()
            // Ended only if it was active and is now fully idle
            return wasActive && !s.isRunning && !s.isPaused
        }
        // Cold / process-death: only claim complete when no durable session or wall past.
        guard unboundSessionMayComplete() else {
            // Mid-session process death — keep LA; restore will rebind VM
            return false
        }
        AppPreferences.setPendingDeactivate(true)
        clearIntentDeadline()
        pending = .complete
        return true
    }

    func drainPending() {
        guard let s = session, let p = pending else { return }
        switch p {
        case .pause:
            if s.isRunning {
                s.pause()
            }
            // Always clear — never surprise-pause the next session
            clearPending()
        case .resume:
            if isIntentPendingExpired() {
                // Stale Island/Siri resume — never surprise-stim on late connect
                clearPending()
                return
            }
            if s.isPaused, s.canResume {
                s.resume()
                clearPending()
            } else if !s.isPaused {
                clearPending()
            }
            // else keep pending until ready (still within TTL)
        case .start:
            if isIntentPendingExpired() {
                // Stale Shortcuts start — never surprise-stim on late connect
                clearPending()
                return
            }
            switch startGate(s) {
            case .now:
                s.start()
                clearPending()
            case .drop:
                clearPending()
            case .hold:
                break
            }
        case .stop:
            if s.isRunning || s.isPaused {
                s.stop(reason: .user)
            } else {
                s.requestHardwareOffIfIdle()
            }
            clearPending()
        case .complete:
            s.honorLiveActivitySessionEnd()
            clearPending()
        }
    }

    /// Test/helper: clear sticky state between suites.
    func resetForTests() {
        session = nil
        clearPending()
        now = { Date() }
    }

    // MARK: - Intent TTL (Start / Resume)

    /// One Start gate for request and drain.
    /// `.now` fires. `.drop` clears. `.hold` waits inside the TTL.
    private enum StartGate {
        case now
        case drop
        case hold
    }

    private func startGate(_ s: SessionViewModel) -> StartGate {
        if s.canStart { return .now }
        if s.isRunning || s.isPaused { return .drop }
        if s.blocksStartForBattery,
           let pct = s.ble.batteryPercentage,
           BatteryPresentation.isEmpty(percent: pct),
           s.ble.isCharging != true {
            return .drop
        }
        return .hold
    }

    /// Keys match SessionViewModel.PersistKey (session.*).
    private func unboundSessionMayComplete() -> Bool {
        let d = UserDefaults.standard
        return LiveActivityEndPolicy.shouldConfirmUnboundComplete(
            now: now(),
            persistedStart: storedDate(d, key: "session.startDate"),
            totalDurationSeconds: d.integer(forKey: "session.totalDuration"),
            accumulatedPause: d.double(forKey: "session.accumulatedPauseTime"),
            pauseStart: storedDate(d, key: "session.pauseStartDate"),
            isPaused: d.bool(forKey: "session.isPaused"),
            offlineSince: storedDate(d, key: "session.offlineSince")
        )
    }

    private func storedDate(_ defaults: UserDefaults, key: String) -> Date? {
        (defaults.object(forKey: key) as? TimeInterval)
            .map { Date(timeIntervalSince1970: $0) }
    }

    private func armStartPending() {
        pending = .start
        pendingIntentDeadline = now().addingTimeInterval(Self.intentPendingTTL)
    }

    private func armResumePending() {
        pending = .resume
        pendingIntentDeadline = now().addingTimeInterval(Self.intentPendingTTL)
    }

    private func isIntentPendingExpired() -> Bool {
        guard let deadline = pendingIntentDeadline else {
            // No deadline → treat as expired (defensive; arm* always sets one)
            return true
        }
        return now() > deadline
    }

    private func clearIntentDeadline() {
        pendingIntentDeadline = nil
    }

    private func clearPending() {
        pending = nil
        pendingIntentDeadline = nil
    }
}

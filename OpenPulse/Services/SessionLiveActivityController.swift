import Foundation
@preconcurrency import ActivityKit

// MARK: - Testable seam (VM lifecycle unit tests)

/// Live Activity surface. Production uses ActivityKit; tests inject a recording double.
@MainActor
protocol SessionLiveActivityPresenting: AnyObject {
    func start(
        mode: StimulationMode,
        totalSeconds: Int,
        remainingSeconds: Int,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool,
        isPaused: Bool,
        isLinkReady: Bool
    )
    func update(
        remainingSeconds: Int,
        totalSeconds: Int,
        isPaused: Bool,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool,
        isLinkReady: Bool
    )
    func end(
        reason: SessionLiveActivityController.EndReason,
        modeName: String,
        pendingDeviceOff: Bool
    )
    /// HW off confirmed while completed LA may still linger — clear "turning device off".
    func noteHardwareOffConfirmed()
}

/// Lock Screen / Dynamic Island session presence.
@MainActor
final class SessionLiveActivityController: SessionLiveActivityPresenting {
    nonisolated(unsafe) private static var currentActivity: Activity<SessionActivityAttributes>?
    /// Generation token so async end() cannot kill a newer activity.
    private static var generation: UInt64 = 0
    /// Serializes ActivityKit updates so out-of-order awaits cannot clobber pause/reconnect.
    private static var updateChain: Task<Void, Never>?
    private static var endScheduleTask: Task<Void, Never>?
    /// Completed LA still on Lock Screen awaiting off ACK honesty.
    private static var lingeringCompleted:
        (activity: Activity<SessionActivityAttributes>, modeName: String, gen: UInt64)?
    /// Wall-complete hook (tests inject; production defaults to SessionActionBridge).
    /// Return `true` when LA may show completed (session ended / unbound).
    static var onSessionShouldComplete: (() -> Bool)?

    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Fire session complete via inject or shared bridge.
    /// - Returns whether LA should end as completed (wall past or unbound).
    @discardableResult
    static func requestSessionComplete() -> Bool {
        if let onSessionShouldComplete {
            return onSessionShouldComplete()
        }
        return SessionActionBridge.shared.requestComplete()
    }

    enum EndReason: Equatable {
        case user
        case completed
    }

    /// End system-owned Live Activities not tracked in-process (process death orphans).
    /// Call before start / after cold restore so Island does not keep a stale endsAt countdown.
    static func endOrphanActivities(keeping activityID: String? = nil) {
        for activity in Activity<SessionActivityAttributes>.activities {
            if let keeping = activityID, activity.id == keeping { continue }
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private func liveContent(
        remainingSeconds: Int,
        totalSeconds: Int,
        isPaused: Bool,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool,
        isLinkReady: Bool,
        now: Date
    ) -> ActivityContent<SessionActivityAttributes.ContentState> {
        let endsAt = LiveActivityPresentation.endsAt(
            remainingSeconds: remainingSeconds,
            isPaused: isPaused,
            isLinkReady: isLinkReady,
            now: now
        )
        let state = SessionActivityAttributes.ContentState(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            isPaused: isPaused,
            statusText: statusText,
            stimulationActive: stimulationActive,
            pendingDeviceOff: pendingDeviceOff,
            endsAt: endsAt,
            isLinkReady: isLinkReady
        )
        // Stale at session end so system can dim after 00:00 even if process is late.
        // Offline / paused: extend stale far so LA does not dim mid-reconnect.
        let stale: Date
        if isPaused || !isLinkReady {
            stale = now.addingTimeInterval(TimeInterval(max(remainingSeconds + 3600, 3600)))
        } else if let endsAt {
            stale = endsAt
        } else {
            stale = now.addingTimeInterval(TimeInterval(max(remainingSeconds + 30, 60)))
        }
        return ActivityContent(state: state, staleDate: stale)
    }

    func start(
        mode: StimulationMode,
        totalSeconds: Int,
        remainingSeconds: Int,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool = false,
        isPaused: Bool = false,
        isLinkReady: Bool = true
    ) {
        let now = Date()
        guard Self.isSupported else { return }

        Self.generation &+= 1
        let gen = Self.generation
        // New session — do not let prior completed linger receive off-ACK re-end
        Self.lingeringCompleted = nil
        let prior = Self.currentActivity
        Self.currentActivity = nil
        // Process-dead orphans still sit in Activity.activities with live endsAt
        Self.endOrphanActivities(keeping: prior?.id)

        let attributes = SessionActivityAttributes(
            modeRaw: mode.rawValue,
            modeName: mode.name,
            totalSeconds: totalSeconds
        )
        let content = liveContent(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            isPaused: isPaused,
            statusText: statusText.isEmpty ? mode.name : statusText,
            stimulationActive: stimulationActive,
            pendingDeviceOff: pendingDeviceOff,
            isLinkReady: isLinkReady,
            now: now
        )

        if let prior {
            Task {
                await prior.end(nil, dismissalPolicy: .immediate)
            }
        }

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            guard gen == Self.generation else {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
                return
            }
            Self.currentActivity = activity
            // Schedule end complete on first start (not only subsequent updates)
            scheduleEndAtSessionEnd(endsAt: content.state.endsAt, gen: gen)
        } catch {
            Self.currentActivity = nil
        }
    }

    func update(
        remainingSeconds: Int,
        totalSeconds: Int,
        isPaused: Bool,
        statusText: String,
        stimulationActive: Bool,
        pendingDeviceOff: Bool = false,
        isLinkReady: Bool = true
    ) {
        let now = Date()
        guard Self.currentActivity != nil else { return }
        // Monotonic seq so out-of-order async updates cannot clobber pause/reconnect
        Self.generation &+= 1
        let gen = Self.generation
        let content = liveContent(
            remainingSeconds: remainingSeconds,
            totalSeconds: totalSeconds,
            isPaused: isPaused,
            statusText: statusText,
            stimulationActive: stimulationActive,
            pendingDeviceOff: pendingDeviceOff,
            isLinkReady: isLinkReady,
            now: now
        )
        // Chain updates: each waits for prior, then applies only if still latest gen
        let prior = Self.updateChain
        Self.updateChain = Task {
            await prior?.value
            guard gen == Self.generation, let act = Self.currentActivity else { return }
            await act.update(content)
        }
        // Offline freezes endsAt (nil) so scheduleEndAtSessionEnd cancels — no false complete.
        scheduleEndAtSessionEnd(endsAt: content.state.endsAt, gen: gen)
    }

    /// When system countdown hits endsAt, complete session first (VM wall truth), then LA.
    /// Never end-before-confirm — that lied "Session complete" while stim could continue.
    private func scheduleEndAtSessionEnd(endsAt: Date?, gen: UInt64) {
        Self.endScheduleTask?.cancel()
        guard let endsAt else { return }
        let delay = endsAt.timeIntervalSinceNow
        guard delay > 0 else {
            if gen == Self.generation {
                Task { @MainActor in
                    await fireSessionEndAfterConfirm(gen: gen)
                }
            }
            return
        }
        Self.endScheduleTask = Task {
            let ns = UInt64(delay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
            guard !Task.isCancelled, gen == Self.generation else { return }
            await fireSessionEndAfterConfirm(gen: gen)
        }
    }

    /// Confirm with session (wall-honest), then end LA only if session confirms complete.
    @MainActor
    private func fireSessionEndAfterConfirm(gen: UInt64) async {
        guard gen == Self.generation else { return }
        guard let act = Self.currentActivity, !act.content.state.isPaused else { return }
        let modeName = act.attributes.modeName
        // VM stop ends LA when wall past; unbound returns true + durable pending-off
        let confirmed = Self.requestSessionComplete()
        // Only end LA when session (or unbound path) confirms — never on stale remaining alone
        if LiveActivityEndPolicy.shouldEndAsCompleted(
            activityStillCurrent: Self.currentActivity != nil && gen == Self.generation,
            sessionConfirmedComplete: confirmed
        ) {
            // Unbound / no VM end path: durable off is armed — claim pending off
            end(reason: .completed, modeName: modeName, pendingDeviceOff: true)
        }
    }

    /// End Live Activity. Completed sessions linger briefly with honest complete copy.
    /// - Parameter pendingDeviceOff: true only when HW off is still in flight (Still honesty).
    func end(
        reason: EndReason = .user,
        modeName: String = "",
        pendingDeviceOff: Bool = true
    ) {
        let now = Date()
        Self.generation &+= 1
        let gen = Self.generation
        Self.endScheduleTask?.cancel()
        Self.endScheduleTask = nil
        Self.lingeringCompleted = nil
        let activity = Self.currentActivity
        Self.currentActivity = nil
        let prior = Self.updateChain
        Self.updateChain = nil
        // Caller truth only — do not sticky-OR ActivityKit state (paused off-ACK would lie)
        let offPending = pendingDeviceOff
        // Drop any process-orphan siblings so dual Islands cannot linger
        Self.endOrphanActivities(keeping: activity?.id)
        Task {
            await prior?.value
            guard let activity else { return }
            switch reason {
            case .completed:
                let final = SessionActivityAttributes.ContentState(
                    remainingSeconds: 0,
                    totalSeconds: max(1, activity.content.state.totalSeconds),
                    isPaused: false,
                    statusText: LiveActivityPresentation.completedStatus(
                        modeName: modeName,
                        pendingDeviceOff: offPending
                    ),
                    stimulationActive: false,
                    pendingDeviceOff: offPending,
                    endsAt: nil,
                    isLinkReady: activity.content.state.isLinkReady
                )
                let dismissAt = now.addingTimeInterval(
                    LiveActivityPresentation.completedDismissalSeconds
                )
                if offPending {
                    // Keep handle so off ACK can clear "turning device off" during linger
                    Self.lingeringCompleted = (activity, modeName, gen)
                }
                await activity.end(
                    ActivityContent(state: final, staleDate: dismissAt),
                    dismissalPolicy: .after(dismissAt)
                )
                // Drop linger bookkeeping after max dismissal window
                if offPending {
                    try? await Task.sleep(
                        for: .seconds(LiveActivityPresentation.completedDismissalSeconds + 0.5)
                    )
                    if let linger = Self.lingeringCompleted, linger.gen == gen {
                        Self.lingeringCompleted = nil
                    }
                }
            case .user:
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// After durable off ACK while completed LA lingers — re-end with honest copy (no turning off).
    func noteHardwareOffConfirmed() {
        let now = Date()
        guard let linger = Self.lingeringCompleted else { return }
        Self.lingeringCompleted = nil
        let modeName = linger.modeName
        let activity = linger.activity
        Task {
            let final = SessionActivityAttributes.ContentState(
                remainingSeconds: 0,
                totalSeconds: max(1, activity.content.state.totalSeconds),
                isPaused: false,
                statusText: LiveActivityPresentation.completedStatus(
                    modeName: modeName,
                    pendingDeviceOff: false
                ),
                stimulationActive: false,
                pendingDeviceOff: false,
                endsAt: nil,
                isLinkReady: activity.content.state.isLinkReady
            )
            // Short linger after honest complete (Still: no fake "stopping")
            let dismissAt = now.addingTimeInterval(3)
            await activity.end(
                ActivityContent(state: final, staleDate: dismissAt),
                dismissalPolicy: .after(dismissAt)
            )
        }
    }
}

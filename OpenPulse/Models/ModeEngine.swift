import Foundation

enum ActiveChannel: Equatable {
    case bilateral
    case left
    case right
    case off
}

enum BreathingPhase: Equatable {
    case inhale(progress: Double)   // 0…1
    case hold(progress: Double)     // 0…1
    case exhale(progress: Double)   // 0…1
    case rest(progress: Double)     // 0…1 — brief stillness between exhale and next inhale
}

struct ModeTickResult {
    var commands: [String] = []
    var isStimulationActive: Bool = true
    var effectiveStrength: Int? = nil
    var breathingPhase: BreathingPhase? = nil
    var activeChannel: ActiveChannel = .bilateral
    /// Soft-start in progress — do not persist as protocol fade floor.
    var isEasing: Bool = false
    var statusText: String = ""
}

/// Durable soft-start window for process kill (flag + lastSent — never wall-only rehydrate).
struct SoftStartSnapshot: Codable, Equatable, Sendable {
    var enabled: Bool
    var userTakenOver: Bool
    var lastSent: Int
    var beginElapsed: Int
}

protocol ModeEngine {
    /// Called once at session start. Returns initial BLE commands.
    mutating func start(baseStrength: Int, totalDuration: Int) -> [String]

    /// Called every 1s tick. elapsed = seconds since start.
    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult

    /// Called on reconnection to get current activation commands.
    /// Mutating so soft-start can complete (avoids undercutting full reassert).
    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String]

    /// User raised intensity mid-session (optional soft-start sync). Default no-op.
    /// `previousBase` is the session base before the change (Sleep match-comfort hold).
    mutating func noteUserStrength(_ strength: Int, previousBase: Int?)

    /// Session pause — duty engines clear on-edge so resume soft-starts.
    mutating func notePaused()

    /// Seed durable anchors after process restore (Sleep phase length + comfort floor).
    /// `pinnedUserFloor` is set only when the user raised mid-fade (survives kill).
    mutating func restoreAnchors(
        phaseLengthSeconds: Int?,
        lastComfortStrength: Int?,
        sessionStrength: Int?,
        elapsed: Int?,
        totalDuration: Int?,
        pinnedUserFloor: Int?
    )

    /// User mid-fade pin (0 if none) — for durable restore after kill.
    func pinnedUserStrengthFloor() -> Int

    /// Export soft window for process-kill restore (nil if settled / none).
    func softSnapshot() -> SoftStartSnapshot?

    /// Rehydrate soft window after process kill (before reconnectCommands).
    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?)
}

extension ModeEngine {
    mutating func noteUserStrength(_ strength: Int, previousBase: Int?) {}
    mutating func notePaused() {}
    mutating func restoreAnchors(
        phaseLengthSeconds: Int?,
        lastComfortStrength: Int?,
        sessionStrength: Int?,
        elapsed: Int?,
        totalDuration: Int?,
        pinnedUserFloor: Int?
    ) {}
    func pinnedUserStrengthFloor() -> Int { 0 }
    func softSnapshot() -> SoftStartSnapshot? { nil }
    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {}
}

// MARK: - Soft resume after user pause (not mid-session BLE drop)

/// Arm on `notePaused`; consume once on reconnect soft path.
private struct SoftResumeGate {
    private var armed = false

    mutating func reset() { armed = false }
    mutating func arm() { armed = true }
    /// Returns true once if armed, then clears.
    mutating func consume() -> Bool {
        guard armed else { return false }
        armed = false
        return true
    }

    /// Pause soft-starts once. An open ladder catches up from its start (R53). Else `target`.
    mutating func reconnectLevel(soft: inout SoftStartState, elapsed: Int, target: Int) -> Int {
        if consume() {
            return soft.begin(target: target, atElapsed: elapsed)
        }
        if let level = soft.reconnectCatchUp(elapsed: elapsed, target: target) {
            return level
        }
        soft.complete(syncedTo: target)
        return target
    }
}

// MARK: - Soft-start state (continuous bilateral comfort)

/// Tracks app-side step-up toward user target (never overshoots).
/// Local-elapsed from `begin(atElapsed:)` so duty re-on can soft-start again
/// without treating session wall time as already complete.
private struct SoftStartState {
    private var enabled = false
    /// True after user setStrength mid soft — blocks any soft reconnect path.
    private var userTakenOver = false
    private var lastSent = -1
    /// Session elapsed when this soft window began (duty re-entry).
    private var beginElapsed = 0

    mutating func begin(target: Int, atElapsed: Int = 0) -> Int {
        enabled = SoftStart.isNeeded(target: target)
        userTakenOver = false
        beginElapsed = max(0, atElapsed)
        let initial = SoftStart.initialStrength(target: target)
        lastSent = initial
        return initial
    }

    /// Force complete (after reconnect path sent full target). Sync lastSent to avoid undercut.
    mutating func complete(syncedTo strength: Int? = nil) {
        enabled = false
        if let s = strength {
            lastSent = max(1, min(9, s))
        }
    }

    /// External setStrength — stop ease; track lastSent exactly (raise or lower).
    mutating func noteExternalStrength(_ strength: Int) {
        let s = max(1, min(9, strength))
        lastSent = s
        // User took over intensity — do not continue soft steps
        enabled = false
        userTakenOver = true
    }

    var isEnabled: Bool { enabled && !userTakenOver }

    private func localElapsed(_ elapsed: Int) -> Int {
        max(0, elapsed - beginElapsed)
    }

    /// Strength to send this tick if it differs from last sent; nil if nothing to enqueue.
    /// Never undercuts `lastSent` (reconnect / user raise / target drop).
    mutating func stepIfNeeded(elapsed: Int, target: Int) -> Int? {
        guard enabled else { return nil }
        let cappedTarget = max(1, min(9, target))
        let local = localElapsed(elapsed)
        var desired = SoftStart.strength(atElapsed: local, target: cappedTarget)
        if lastSent > 0 {
            desired = max(desired, lastSent)
        }
        if SoftStart.isComplete(elapsed: local, target: cappedTarget) || desired >= cappedTarget {
            enabled = false
            desired = cappedTarget
        }
        // Target drop or race: never emit below what BLE already has
        if lastSent > 0, desired < lastSent {
            enabled = false
            return nil
        }
        guard desired != lastSent else { return nil }
        lastSent = desired
        return desired
    }

    func isEasing(elapsed: Int, target: Int) -> Bool {
        enabled && !SoftStart.isComplete(elapsed: localElapsed(elapsed), target: target)
    }

    func displayLevel(elapsed: Int, target: Int) -> Int? {
        guard isEasing(elapsed: elapsed, target: target) else { return nil }
        let raw = SoftStart.strength(atElapsed: localElapsed(elapsed), target: target)
        return lastSent > 0 ? max(raw, lastSent) : raw
    }

    /// Reconnect while still easing — catch-up ladder strength, keep window open.
    /// Returns full target and completes soft when ease is done.
    /// Never runs after user takeover (raise/lower mid soft).
    mutating func reconnectCatchUp(elapsed: Int, target: Int) -> Int? {
        guard enabled, !userTakenOver else { return nil }
        let capped = max(1, min(9, target))
        let local = localElapsed(elapsed)
        var desired = SoftStart.strength(atElapsed: local, target: capped)
        if lastSent > 0 {
            desired = max(desired, lastSent)
        }
        if SoftStart.isComplete(elapsed: local, target: capped) || desired >= capped {
            enabled = false
            lastSent = capped
            return capped
        }
        lastSent = desired
        return desired
    }

    /// Durable export for process kill (only while soft open or user takeover floor).
    func snapshot() -> SoftStartSnapshot? {
        guard enabled || userTakenOver, lastSent > 0 else { return nil }
        return SoftStartSnapshot(
            enabled: enabled,
            userTakenOver: userTakenOver,
            lastSent: lastSent,
            beginElapsed: beginElapsed
        )
    }

    mutating func apply(_ snap: SoftStartSnapshot) {
        enabled = snap.enabled
        userTakenOver = snap.userTakenOver
        lastSent = max(1, min(9, snap.lastSent))
        beginElapsed = max(0, snap.beginElapsed)
    }
}

// MARK: - Stress Relief Engine
// Bilateral (D), soft-start then constant intensity

struct StressReliefEngine: ModeEngine {
    private var soft = SoftStartState()
    /// After user pause, next reconnect soft-starts (comfort). Mid-session BLE drop stays full.
    private var softResume = SoftResumeGate()

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        softResume.reset()
        let initial = soft.begin(target: baseStrength, atElapsed: 0)
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(initial)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        if let stepped = soft.stepIfNeeded(elapsed: elapsed, target: baseStrength) {
            let easing = soft.isEasing(elapsed: elapsed, target: baseStrength)
                || stepped < max(1, min(9, baseStrength))
            return ModeTickResult(
                commands: [BLEConstants.strengthCommand(stepped)],
                isStimulationActive: true,
                effectiveStrength: stepped < max(1, min(9, baseStrength)) ? stepped : nil,
                activeChannel: .bilateral,
                isEasing: easing,
                statusText: easing ? "Bilateral · Easing in" : "Bilateral · Continuous"
            )
        }
        if soft.isEasing(elapsed: elapsed, target: baseStrength),
           let current = soft.displayLevel(elapsed: elapsed, target: baseStrength) {
            return ModeTickResult(
                isStimulationActive: true,
                effectiveStrength: current,
                activeChannel: .bilateral,
                isEasing: true,
                statusText: "Bilateral · Easing in"
            )
        }
        return ModeTickResult(
            isStimulationActive: true,
            activeChannel: .bilateral,
            statusText: "Bilateral · Continuous"
        )
    }

    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let level = softResume.reconnectLevel(soft: &soft, elapsed: elapsed, target: baseStrength)
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(level)]
    }

    mutating func noteUserStrength(_ strength: Int, previousBase: Int?) {
        _ = previousBase
        soft.noteExternalStrength(strength)
    }

    mutating func notePaused() {
        softResume.arm()
        soft.complete()
    }

    func softSnapshot() -> SoftStartSnapshot? { soft.snapshot() }

    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {
        guard let s = snapshot else { return }
        soft.apply(s)
    }
}

// MARK: - Sleep Engine
// Channel rotation: D→A→D→C→D, each phase = 20% of duration
// Soft-start ease-in; fade last 20% reduces strength by -1 then -2

struct SleepEngine: ModeEngine {
    private var lastPhaseIndex = -1
    private var lastFadeStrength = -1
    /// Protocol fade floor (last 20%) — never re-raise after extend; independent of soft steps.
    private var fadeFloor = 0
    /// User-set intensity floor when raising mid-fade — never undercut that BLE level.
    private var userStrengthFloor = 0
    private var soft = SoftStartState()
    private var softResume = SoftResumeGate()
    /// Fixed phase length from session start so ±time does not rewind channel rotation.
    private var phaseLengthSeconds = 0

    private static let channelSequence = [
        BLEConstants.activateCommand,       // D - bilateral
        BLEConstants.leftChannelCommand,    // A - left
        BLEConstants.activateCommand,       // D - bilateral
        BLEConstants.rightChannelCommand,   // C - right
        BLEConstants.activateCommand,       // D - bilateral
    ]

    private mutating func ensurePhaseSchedule(totalDuration: Int) {
        if phaseLengthSeconds <= 0 {
            phaseLengthSeconds = max(1, totalDuration / 5)
        }
    }

    private func phaseIndex(elapsed: Int, totalDuration: Int) -> Int {
        let len = phaseLengthSeconds > 0
            ? phaseLengthSeconds
            : max(1, totalDuration / 5)
        guard len > 0 else { return 0 }
        return min(elapsed / len, 4)
    }

    private func fadeStrength(elapsed: Int, totalDuration: Int, baseStrength: Int) -> Int {
        // Fade uses live total so extend delays fade / shorten advances fade honestly
        let fadeStart = totalDuration * 4 / 5
        guard elapsed >= fadeStart, totalDuration > fadeStart else { return baseStrength }

        let fadeLen = totalDuration - fadeStart
        let fadeElapsed = elapsed - fadeStart
        let fadeMid = fadeLen / 2

        if fadeElapsed < fadeMid {
            return max(1, baseStrength - 1)
        } else {
            return max(1, baseStrength - 2)
        }
    }

    /// Comfort target: live fade, never re-raise past fadeFloor (extend), never undercut user floor.
    private func comfortFade(
        elapsed: Int,
        totalDuration: Int,
        baseStrength: Int,
        allowSoftClimb: Bool
    ) -> Int {
        let rawFade = fadeStrength(
            elapsed: elapsed,
            totalDuration: totalDuration,
            baseStrength: baseStrength
        )
        let base = max(1, min(9, baseStrength))
        var target = rawFade
        // Protocol floor survives soft climb (soft steps use lastFade; floor is separate)
        if fadeFloor > 0, fadeFloor < base, fadeFloor < rawFade {
            target = fadeFloor
        }
        // User raise mid-fade: never undercut BLE they just set
        if userStrengthFloor > 0 {
            target = max(target, userStrengthFloor)
        }
        // allowSoftClimb reserved for API symmetry with reconnect; floor always applies
        _ = allowSoftClimb
        return target
    }

    /// Track protocol fade floor when settled below base (not soft steps).
    private mutating func noteSettledComfort(_ comfort: Int, base: Int) {
        let b = max(1, min(9, base))
        let c = max(1, min(9, comfort))
        if c < b {
            if fadeFloor <= 0 || c < fadeFloor {
                fadeFloor = c
            }
        }
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        lastPhaseIndex = 0
        softResume.reset()
        userStrengthFloor = 0
        fadeFloor = 0
        phaseLengthSeconds = max(1, totalDuration / 5)
        let initial = soft.begin(target: baseStrength)
        lastFadeStrength = initial
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(initial)]
    }

    private static let channelNames = ["Bilateral", "Left", "Bilateral", "Right", "Bilateral"]

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
        ensurePhaseSchedule(totalDuration: totalDuration)

        let phase = phaseIndex(elapsed: elapsed, totalDuration: totalDuration)
        // Monotonic phase: never rewind channel when totalDuration grows mid-session
        let effectivePhase = max(phase, lastPhaseIndex >= 0 ? lastPhaseIndex : phase)
        if effectivePhase != lastPhaseIndex {
            commands.append(Self.channelSequence[effectivePhase])
            lastPhaseIndex = effectivePhase
        }
        let phaseForStatus = lastPhaseIndex >= 0 ? lastPhaseIndex : phase

        // Comfort target from live fade. After soft completes, never re-raise if ±time
        // moves fadeStart later (extend mid-fade must not send higher strength).
        let comfortTarget = comfortFade(
            elapsed: elapsed,
            totalDuration: totalDuration,
            baseStrength: baseStrength,
            allowSoftClimb: true
        )

        // Soft-start first (includes final step) — toward comfortTarget, not raw base
        if let stepped = soft.stepIfNeeded(elapsed: elapsed, target: comfortTarget) {
            commands.append(BLEConstants.strengthCommand(stepped))
            lastFadeStrength = stepped
        }
        if soft.isEasing(elapsed: elapsed, target: comfortTarget) {
            let current = soft.displayLevel(elapsed: elapsed, target: comfortTarget)
                ?? SoftStart.initialStrength(target: comfortTarget)
            let channelName = Self.channelNames[phaseForStatus]
            let activeChannels: [ActiveChannel] = [.bilateral, .left, .bilateral, .right, .bilateral]
            return ModeTickResult(
                commands: commands,
                isStimulationActive: true,
                effectiveStrength: current < max(1, min(9, comfortTarget)) ? current : nil,
                activeChannel: activeChannels[phaseForStatus],
                isEasing: true,
                statusText: "\(channelName) channel · Easing in"
            )
        }

        // Soft done — sync to comfort (fade or full)
        soft.complete(syncedTo: comfortTarget)

        let fade = comfortTarget
        noteSettledComfort(fade, base: baseStrength)
        if fade != lastFadeStrength {
            commands.append(BLEConstants.strengthCommand(fade))
            lastFadeStrength = fade
        }

        let channelName = Self.channelNames[phaseForStatus]
        let fadeNote = fade < max(1, min(9, baseStrength)) ? " · Fading" : ""
        let status = "\(channelName) channel\(fadeNote)"

        let activeChannels: [ActiveChannel] = [.bilateral, .left, .bilateral, .right, .bilateral]

        return ModeTickResult(
            commands: commands,
            isStimulationActive: true,
            effectiveStrength: fade != max(1, min(9, baseStrength)) ? fade : nil,
            activeChannel: activeChannels[phaseForStatus],
            statusText: status
        )
    }

    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        ensurePhaseSchedule(totalDuration: totalDuration)
        let phase = phaseIndex(elapsed: elapsed, totalDuration: totalDuration)
        // Never rewind phase on reconnect after total change
        let effectivePhase = max(phase, lastPhaseIndex >= 0 ? lastPhaseIndex : phase)
        lastPhaseIndex = effectivePhase
        // Same comfort floor as tick — extend mid-fade must not re-raise on BLE drop
        let fade = comfortFade(
            elapsed: elapsed,
            totalDuration: totalDuration,
            baseStrength: baseStrength,
            allowSoftClimb: false
        )
        noteSettledComfort(fade, base: baseStrength)
        // Cap soft target at comfort fade so late-session pause never re-ramps above floor
        let level = softResume.reconnectLevel(soft: &soft, elapsed: elapsed, target: fade)
        lastFadeStrength = level
        return [Self.channelSequence[effectivePhase], BLEConstants.strengthCommand(level)]
    }

    mutating func notePaused() {
        softResume.arm()
        soft.complete()
    }

    func softSnapshot() -> SoftStartSnapshot? { soft.snapshot() }

    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {
        guard let s = snapshot else { return }
        soft.apply(s)
    }

    mutating func noteUserStrength(_ strength: Int, previousBase: Int?) {
        soft.noteExternalStrength(strength)
        let s = max(1, min(9, strength))
        // Only pin when already in protocol fade — early nudges must still fade later
        if fadeFloor > 0 {
            let prev = previousBase.map { max(1, min(9, $0)) }
            if s == lastFadeStrength {
                // Matching felt comfort while lowering base → hold (no same-tick undercut)
                if let prev, s < prev {
                    userStrengthFloor = s
                    fadeFloor = s
                    lastFadeStrength = s
                }
                // Else pure match without base drop — leave room for deeper protocol fade
                return
            }
            // Partial base lower that would re-raise felt (e.g. base 5→4 while felt 3)
            // Hold current comfort; do not jump BLE up to the new base
            if let prev, s < prev, lastFadeStrength > 0, s > lastFadeStrength {
                userStrengthFloor = lastFadeStrength
                fadeFloor = lastFadeStrength
                return
            }
            lastFadeStrength = s
            userStrengthFloor = s
            fadeFloor = s
        } else {
            lastFadeStrength = s
            userStrengthFloor = 0
        }
    }

    func pinnedUserStrengthFloor() -> Int {
        userStrengthFloor > 0 ? userStrengthFloor : 0
    }

    mutating func restoreAnchors(
        phaseLengthSeconds: Int?,
        lastComfortStrength: Int?,
        sessionStrength: Int?,
        elapsed: Int?,
        totalDuration: Int?,
        pinnedUserFloor: Int?
    ) {
        if let len = phaseLengthSeconds, len > 0 {
            self.phaseLengthSeconds = len
        }
        // Default: no floors — full base restore must still auto-fade later
        fadeFloor = 0
        userStrengthFloor = 0
        // Settle-only persist: c < b means protocol fade (soft steps are not written)
        if let comfort = lastComfortStrength, comfort > 0 {
            let c = max(1, min(9, comfort))
            lastFadeStrength = c
            if let base = sessionStrength {
                let b = max(1, min(9, base))
                if c < b {
                    fadeFloor = c
                }
                // c >= b alone does not pin — soft-complete at base must still fade later
            } else {
                fadeFloor = c
            }
        }
        // Explicit mid-fade user raise (dedicated key) — holds across kill/extend
        if let pin = pinnedUserFloor, pin > 0 {
            let p = max(1, min(9, pin))
            userStrengthFloor = p
            fadeFloor = max(fadeFloor, p)
            lastFadeStrength = max(lastFadeStrength, p)
        }
        _ = elapsed
        _ = totalDuration
    }
}

// MARK: - Focus Engine
// Left channel (A), 30s on / 30s off
// Soft-start every on-window (comfort re-entry after rest — App Store feedback)
// BLE reconnect soft only after user pause (mid-session drop stays full)

struct FocusEngine: ModeEngine {
    private var wasOn = false
    private var soft = SoftStartState()
    private var softResume = SoftResumeGate()

    private func isOnPhase(elapsed: Int) -> Bool {
        (elapsed % 60) < 30
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        wasOn = true
        softResume.reset()
        let initial = soft.begin(target: baseStrength, atElapsed: 0)
        return [BLEConstants.leftChannelCommand, BLEConstants.strengthCommand(initial)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
        let on = isOnPhase(elapsed: elapsed)

        // Off edge first so soft window does not run while resting
        if !on && wasOn {
            commands.append(BLEConstants.deactivateCommand)
            wasOn = on
            soft.complete(syncedTo: baseStrength)
            let cyclePos = elapsed % 60
            let secsLeft = 60 - cyclePos
            return ModeTickResult(
                commands: commands,
                isStimulationActive: false,
                effectiveStrength: 0,
                activeChannel: .off,
                statusText: "Resting · Off (\(secsLeft)s)"
            )
        }

        // On edge after rest — soft re-entry (local elapsed from this edge)
        if on && !wasOn {
            let initial = soft.begin(target: baseStrength, atElapsed: elapsed)
            commands.append(BLEConstants.leftChannelCommand)
            commands.append(BLEConstants.strengthCommand(initial))
            wasOn = on
            let cyclePos = elapsed % 60
            let secsLeft = 30 - cyclePos
            let easing = soft.isEasing(elapsed: elapsed, target: baseStrength)
            return ModeTickResult(
                commands: commands,
                isStimulationActive: true,
                effectiveStrength: easing ? initial : nil,
                activeChannel: .left,
                isEasing: easing,
                statusText: easing
                    ? "Left channel · Easing in (\(max(0, secsLeft))s)"
                    : "Left channel · On (\(max(0, secsLeft))s)"
            )
        }

        // Soft steps during on-window
        if on {
            if let stepped = soft.stepIfNeeded(elapsed: elapsed, target: baseStrength) {
                commands.append(BLEConstants.strengthCommand(stepped))
            }
            if soft.isEasing(elapsed: elapsed, target: baseStrength) {
                let current = soft.displayLevel(elapsed: elapsed, target: baseStrength)
                    ?? SoftStart.initialStrength(target: baseStrength)
                wasOn = on
                let cyclePos = elapsed % 60
                let secsLeft = 30 - cyclePos
                return ModeTickResult(
                    commands: commands,
                    isStimulationActive: true,
                    effectiveStrength: current < max(1, min(9, baseStrength)) ? current : nil,
                    activeChannel: .left,
                    isEasing: true,
                    statusText: "Left channel · Easing in (\(max(0, secsLeft))s)"
                )
            }
            soft.complete(syncedTo: baseStrength)
        }

        wasOn = on

        let cyclePos = elapsed % 60
        let secsLeft = on ? 30 - cyclePos : 60 - cyclePos
        let status = on
            ? "Left channel · On (\(secsLeft)s)"
            : "Resting · Off (\(secsLeft)s)"
        return ModeTickResult(
            commands: commands,
            isStimulationActive: on,
            effectiveStrength: on ? nil : 0,
            activeChannel: on ? .left : .off,
            statusText: status
        )
    }

    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let on = isOnPhase(elapsed: elapsed)
        wasOn = on
        if on {
            let level = softResume.reconnectLevel(soft: &soft, elapsed: elapsed, target: baseStrength)
            return [BLEConstants.leftChannelCommand, BLEConstants.strengthCommand(level)]
        } else {
            softResume.reset()
            soft.complete(syncedTo: baseStrength)
            return [BLEConstants.deactivateCommand]
        }
    }

    mutating func noteUserStrength(_ strength: Int, previousBase: Int?) {
        _ = previousBase
        soft.noteExternalStrength(strength)
    }

    mutating func notePaused() {
        wasOn = false
        softResume.arm()
        soft.complete()
    }

    func softSnapshot() -> SoftStartSnapshot? { soft.snapshot() }

    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {
        guard let s = snapshot else { return }
        soft.apply(s)
    }
}

// MARK: - Pain Relief Engine
// Bilateral (D), soft-start then intensity oscillates ±1 on 30s sine wave

struct PainReliefEngine: ModeEngine {
    private var lastOffset = 0
    private var soft = SoftStartState()

    private func strengthOffset(elapsed: Int) -> Int {
        let angle = 2.0 * Double.pi * Double(elapsed) / 30.0
        return Int(sin(angle).rounded())
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        lastOffset = 0
        let initial = soft.begin(target: baseStrength)
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(initial)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []

        // Soft-start first — freeze sine until ease-in complete (includes final step)
        let wasEasing = soft.isEasing(elapsed: elapsed, target: baseStrength)
            || soft.isEnabled
        if let stepped = soft.stepIfNeeded(elapsed: elapsed, target: baseStrength) {
            commands.append(BLEConstants.strengthCommand(stepped))
        }
        if soft.isEasing(elapsed: elapsed, target: baseStrength) {
            // Local elapsed after pause soft-begin (not session wall SoftStart.strength)
            let current = soft.displayLevel(elapsed: elapsed, target: baseStrength)
                ?? SoftStart.initialStrength(target: baseStrength)
            return ModeTickResult(
                commands: commands,
                isStimulationActive: true,
                effectiveStrength: current,
                activeChannel: .bilateral,
                isEasing: true,
                statusText: "Bilateral · Easing in"
            )
        }
        // Soft just finished this tick — hold at base; apply sine next offset change
        // Seed lastOffset=0 (device is at base after final soft step), not current sine offset
        if wasEasing {
            soft.complete(syncedTo: baseStrength)
            lastOffset = 0
            return ModeTickResult(
                commands: commands,
                isStimulationActive: true,
                activeChannel: .bilateral,
                statusText: "Bilateral · Base wave"
            )
        }
        soft.complete(syncedTo: baseStrength)

        let offset = strengthOffset(elapsed: elapsed)
        if offset != lastOffset {
            let s = max(1, min(9, baseStrength + offset))
            commands.append(BLEConstants.strengthCommand(s))
            lastOffset = offset
        }

        let currentS = max(1, min(9, baseStrength + offset))
        let trend = offset > 0 ? "Rising" : offset < 0 ? "Falling" : "Base"
        return ModeTickResult(
            commands: commands,
            isStimulationActive: true,
            effectiveStrength: currentS != baseStrength ? currentS : nil,
            activeChannel: .bilateral,
            statusText: "Bilateral · \(trend) wave"
        )
    }

    private var softResume = SoftResumeGate()

    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        if softResume.consume() {
            let initial = soft.begin(target: baseStrength, atElapsed: elapsed)
            lastOffset = 0
            return [BLEConstants.activateCommand, BLEConstants.strengthCommand(initial)]
        }
        // Mid soft: continue ladder before wave offset
        if soft.isEnabled, let level = soft.reconnectCatchUp(elapsed: elapsed, target: baseStrength) {
            lastOffset = 0
            return [BLEConstants.activateCommand, BLEConstants.strengthCommand(level)]
        }
        soft.complete(syncedTo: baseStrength)
        let offset = strengthOffset(elapsed: elapsed)
        let s = max(1, min(9, baseStrength + offset))
        lastOffset = offset
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(s)]
    }

    mutating func noteUserStrength(_ strength: Int, previousBase: Int?) {
        _ = previousBase
        soft.noteExternalStrength(strength)
        // Force next tick to re-apply wave level at new base (do not wait for offset change)
        lastOffset = Int.min
    }

    mutating func notePaused() {
        softResume.arm()
        soft.complete()
    }

    func softSnapshot() -> SoftStartSnapshot? { soft.snapshot() }

    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {
        guard let s = snapshot else { return }
        soft.apply(s)
    }
}

// MARK: - Headache Engine
// Bilateral (D), high intensity, 2-min on / 30s pause / repeat
// Research-inspired comfort burst pattern (wellness framing only)
// BLE reconnect soft only after user pause (mid-session drop stays full)

struct HeadacheEngine: ModeEngine {
    private static let burstDuration = 120   // 2 minutes on
    private static let pauseDuration = 30    // 30 seconds off
    private static let cycleLength = 150     // 2:30 total cycle

    private var wasOn = true
    private var soft = SoftStartState()
    private var softResume = SoftResumeGate()

    private func isOnPhase(elapsed: Int) -> Bool {
        (elapsed % Self.cycleLength) < Self.burstDuration
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        wasOn = true
        softResume.reset()
        let initial = soft.begin(target: baseStrength)
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(initial)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
        let on = isOnPhase(elapsed: elapsed)

        // Off edge
        if !on && wasOn {
            commands.append(BLEConstants.deactivateCommand)
            wasOn = on
            soft.complete(syncedTo: baseStrength)
            let cyclePos = elapsed % Self.cycleLength
            let secsLeft = Self.cycleLength - cyclePos
            return ModeTickResult(
                commands: commands,
                isStimulationActive: false,
                effectiveStrength: 0,
                activeChannel: .off,
                statusText: "Pause · Rest (\(secsLeft)s)"
            )
        }

        // On edge after pause — soft re-entry for comfort
        if on && !wasOn {
            let initial = soft.begin(target: baseStrength, atElapsed: elapsed)
            commands.append(BLEConstants.activateCommand)
            commands.append(BLEConstants.strengthCommand(initial))
            wasOn = on
            let cyclePos = elapsed % Self.cycleLength
            let secsLeft = Self.burstDuration - cyclePos
            let easing = soft.isEasing(elapsed: elapsed, target: baseStrength)
            return ModeTickResult(
                commands: commands,
                isStimulationActive: true,
                effectiveStrength: easing ? initial : nil,
                activeChannel: .bilateral,
                isEasing: easing,
                statusText: easing
                    ? "Burst · Easing in (\(max(0, secsLeft))s)"
                    : "Bilateral · Stimulating (\(max(0, secsLeft))s)"
            )
        }

        // Soft steps during burst
        if on {
            if let stepped = soft.stepIfNeeded(elapsed: elapsed, target: baseStrength) {
                commands.append(BLEConstants.strengthCommand(stepped))
            }
            if soft.isEasing(elapsed: elapsed, target: baseStrength) {
                let current = soft.displayLevel(elapsed: elapsed, target: baseStrength)
                    ?? SoftStart.initialStrength(target: baseStrength)
                wasOn = on
                let cyclePos = elapsed % Self.cycleLength
                let secsLeft = Self.burstDuration - cyclePos
                return ModeTickResult(
                    commands: commands,
                    isStimulationActive: true,
                    effectiveStrength: current < max(1, min(9, baseStrength)) ? current : nil,
                    activeChannel: .bilateral,
                    isEasing: true,
                    statusText: "Burst · Easing in (\(max(0, secsLeft))s)"
                )
            }
            soft.complete(syncedTo: baseStrength)
        }

        wasOn = on

        let cyclePos = elapsed % Self.cycleLength
        let secsLeft = on ? Self.burstDuration - cyclePos : Self.cycleLength - cyclePos
        let status = on
            ? "Bilateral · Stimulating (\(secsLeft)s)"
            : "Pause · Rest (\(secsLeft)s)"

        return ModeTickResult(
            commands: commands,
            isStimulationActive: on,
            effectiveStrength: on ? nil : 0,
            activeChannel: on ? .bilateral : .off,
            statusText: status
        )
    }

    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let on = isOnPhase(elapsed: elapsed)
        // Match Focus: sync edge state so next tick does not re-fire on/off
        wasOn = on
        if on {
            let level = softResume.reconnectLevel(soft: &soft, elapsed: elapsed, target: baseStrength)
            return [BLEConstants.activateCommand, BLEConstants.strengthCommand(level)]
        } else {
            softResume.reset()
            soft.complete(syncedTo: baseStrength)
            return [BLEConstants.deactivateCommand]
        }
    }

    mutating func noteUserStrength(_ strength: Int, previousBase: Int?) {
        _ = previousBase
        soft.noteExternalStrength(strength)
    }

    mutating func notePaused() {
        wasOn = false
        softResume.arm()
        soft.complete()
    }

    func softSnapshot() -> SoftStartSnapshot? { soft.snapshot() }

    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {
        guard let s = snapshot else { return }
        soft.apply(s)
    }
}

// MARK: - Respiratory-Gated Engine (shared by Calm and Meditation)
// Legacy nausea mode maps to StressReliefEngine (Still catalog).
// Parameterized breathing cycle: inhale (stim OFF), hold, exhale (stim ON)

struct BreathingCycle: Equatable {
    let inhaleDuration: Int
    let holdDuration: Int
    let exhaleDuration: Int
    let restDuration: Int       // brief stillness after exhale before next inhale
    let rampLeadTime: Int       // send activate this many seconds before hold starts

    var cycleLength: Int { inhaleDuration + holdDuration + exhaleDuration + restDuration }

    // Calm: 5 in + 5 hold + 7 out = 17s (~3.5 bpm)
    static let calm = BreathingCycle(inhaleDuration: 5, holdDuration: 5, exhaleDuration: 7, restDuration: 0, rampLeadTime: 2)
    // Meditation: 5 in + 4 hold + 5 out = 14s (~4.3 bpm)
    static let meditation = BreathingCycle(inhaleDuration: 5, holdDuration: 4, exhaleDuration: 5, restDuration: 0, rampLeadTime: 2)
}

struct RespiratoryGatedEngine: ModeEngine {
    let cycle: BreathingCycle
    private var wasStimulating = false
    /// Last elapsed fed to tick — gap > 1 uses absolute phase (short early-inhale off).
    private var lastElapsed: Int = -1
    /// Soft after user pause only (mid-session BLE drop stays full phase reassert).
    private var soft = SoftStartState()
    private var softResume = SoftResumeGate()

    init(cycle: BreathingCycle) {
        self.cycle = cycle
    }

    private func cyclePosition(elapsed: Int) -> Int {
        elapsed % cycle.cycleLength
    }

    /// BLE stimulation fires `rampLeadTime` seconds before hold starts,
    /// so the device reaches full intensity by the time exhale begins.
    /// Stays on through hold + exhale, turns off at rest/inhale boundary.
    private func isStimulating(elapsed: Int) -> Bool {
        let pos = cyclePosition(elapsed: elapsed)
        let rampStart = cycle.inhaleDuration - cycle.rampLeadTime
        let stimEnd = cycle.inhaleDuration + cycle.holdDuration + cycle.exhaleDuration
        return pos >= rampStart && pos < stimEnd
    }

    func breathingPhase(elapsed: Int) -> BreathingPhase {
        let pos = cyclePosition(elapsed: elapsed)
        let holdStart = cycle.inhaleDuration
        let exhaleStart = holdStart + cycle.holdDuration
        let restStart = exhaleStart + cycle.exhaleDuration

        if pos < holdStart {
            return .inhale(progress: Double(pos) / Double(max(1, cycle.inhaleDuration)))
        } else if pos < exhaleStart {
            let holdPos = pos - holdStart
            return .hold(progress: Double(holdPos) / Double(max(1, cycle.holdDuration)))
        } else if pos < restStart {
            let exhalePos = pos - exhaleStart
            return .exhale(progress: Double(exhalePos) / Double(max(1, cycle.exhaleDuration)))
        } else {
            let restPos = pos - restStart
            let restDur = max(1, cycle.restDuration)
            return .rest(progress: Double(restPos) / Double(restDur))
        }
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        wasStimulating = false
        lastElapsed = 0
        softResume.reset()
        soft.complete()
        // Always absolute-off at start so prior stim cannot linger through inhale.
        return [BLEConstants.deactivateCommand]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        // Short stalls can skip early-inhale off (~3s) — absolute phase reassert.
        // If the gap included an off second, send off before a landing stim command.
        if lastElapsed >= 0, elapsed - lastElapsed > 1 {
            let skippedOff = skippedStimOff(from: lastElapsed, to: elapsed)
            var cmds = reconnectCommands(
                elapsed: elapsed,
                totalDuration: totalDuration,
                baseStrength: baseStrength
            )
            if skippedOff, cmds.first != BLEConstants.deactivateCommand {
                cmds.insert(BLEConstants.deactivateCommand, at: 0)
            }
            lastElapsed = elapsed
            let stimulating = isStimulating(elapsed: elapsed)
            let easing = soft.isEasing(elapsed: elapsed, target: baseStrength)
            return ModeTickResult(
                commands: cmds,
                isStimulationActive: stimulating,
                effectiveStrength: easing
                    ? soft.displayLevel(elapsed: elapsed, target: baseStrength)
                    : nil,
                breathingPhase: breathingPhase(elapsed: elapsed),
                activeChannel: stimulating ? .bilateral : .off,
                isEasing: easing && stimulating,
                statusText: statusFor(elapsed: elapsed, stimulating: stimulating, easing: easing)
            )
        }

        var commands: [String] = []
        let stimulating = isStimulating(elapsed: elapsed)

        if stimulating && !wasStimulating {
            commands.append(BLEConstants.activateCommand)
            if softResume.consume() {
                // Comfort after user pause — soft ladder, not full blast
                let initial = soft.begin(target: baseStrength, atElapsed: elapsed)
                commands.append(BLEConstants.strengthCommand(initial))
            } else {
                commands.append(BLEConstants.strengthCommand(baseStrength))
            }
        } else if !stimulating && wasStimulating {
            commands.append(BLEConstants.deactivateCommand)
            soft.complete(syncedTo: baseStrength)
        } else if stimulating, let stepped = soft.stepIfNeeded(elapsed: elapsed, target: baseStrength) {
            commands.append(BLEConstants.strengthCommand(stepped))
        }
        wasStimulating = stimulating
        lastElapsed = elapsed

        let easing = soft.isEasing(elapsed: elapsed, target: baseStrength)
        return ModeTickResult(
            commands: commands,
            isStimulationActive: stimulating,
            effectiveStrength: easing && stimulating
                ? soft.displayLevel(elapsed: elapsed, target: baseStrength)
                : nil,
            breathingPhase: breathingPhase(elapsed: elapsed),
            activeChannel: stimulating ? .bilateral : .off,
            isEasing: easing && stimulating,
            statusText: statusFor(elapsed: elapsed, stimulating: stimulating, easing: easing)
        )
    }

    /// True when (last, elapsed) includes a non-stim second while stim was on.
    /// One cycle is enough. Every breath cycle has an early-inhale off.
    private func skippedStimOff(from last: Int, to elapsed: Int) -> Bool {
        guard wasStimulating, elapsed > last + 1 else { return false }
        if elapsed - last >= cycle.cycleLength { return true }
        let end = min(elapsed, last + cycle.cycleLength)
        return (last + 1..<end).contains { !isStimulating(elapsed: $0) }
    }

    private func statusFor(elapsed: Int, stimulating: Bool, easing: Bool = false) -> String {
        switch breathingPhase(elapsed: elapsed) {
        case .inhale: return stimulating ? "Inhale · Preparing" : "Inhale"
        case .hold:   return stimulating ? (easing ? "Hold · Easing in" : "Hold · Active") : "Hold"
        case .exhale: return easing ? "Exhale · Easing in" : "Exhale · Active"
        case .rest:   return "Rest"
        }
    }

    mutating func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let stimulating = isStimulating(elapsed: elapsed)
        wasStimulating = stimulating
        lastElapsed = elapsed
        if stimulating {
            let level = softResume.reconnectLevel(soft: &soft, elapsed: elapsed, target: baseStrength)
            return [BLEConstants.activateCommand, BLEConstants.strengthCommand(level)]
        } else {
            soft.complete(syncedTo: baseStrength)
            return [BLEConstants.deactivateCommand]
        }
    }

    mutating func notePaused() {
        softResume.arm()
        soft.complete()
    }

    func softSnapshot() -> SoftStartSnapshot? { soft.snapshot() }

    mutating func applySoftSnapshot(_ snapshot: SoftStartSnapshot?) {
        guard let s = snapshot else { return }
        soft.apply(s)
    }
}

// Convenience aliases for factory use
enum CalmEngine {
    static func make() -> RespiratoryGatedEngine {
        RespiratoryGatedEngine(cycle: .calm)
    }
}

enum MeditationEngine {
    static func make() -> RespiratoryGatedEngine {
        RespiratoryGatedEngine(cycle: .meditation)
    }
}

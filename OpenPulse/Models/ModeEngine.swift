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
    var statusText: String = ""
}

protocol ModeEngine {
    /// Called once at session start. Returns initial BLE commands.
    mutating func start(baseStrength: Int, totalDuration: Int) -> [String]

    /// Called every 1s tick. elapsed = seconds since start.
    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult

    /// Called on reconnection to get current activation commands.
    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String]
}

// MARK: - Stress Relief Engine
// Bilateral (D), constant intensity, continuous

struct StressReliefEngine: ModeEngine {
    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        ModeTickResult(isStimulationActive: true, activeChannel: .bilateral, statusText: "Bilateral · Continuous")
    }

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }
}

// MARK: - Sleep Engine
// Channel rotation: D→A→D→C→D, each phase = 20% of duration
// Fade: last 20% reduces strength by -1 then -2

struct SleepEngine: ModeEngine {
    private var lastPhaseIndex = -1
    private var lastFadeStrength = -1

    private static let channelSequence = [
        BLEConstants.activateCommand,       // D - bilateral
        BLEConstants.leftChannelCommand,    // A - left
        BLEConstants.activateCommand,       // D - bilateral
        BLEConstants.rightChannelCommand,   // C - right
        BLEConstants.activateCommand,       // D - bilateral
    ]

    private func phaseIndex(elapsed: Int, totalDuration: Int) -> Int {
        guard totalDuration > 0 else { return 0 }
        let phaseLen = totalDuration / 5
        guard phaseLen > 0 else { return 0 }
        return min(elapsed / phaseLen, 4)
    }

    private func fadeStrength(elapsed: Int, totalDuration: Int, baseStrength: Int) -> Int {
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

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        lastPhaseIndex = 0
        lastFadeStrength = baseStrength
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }

    private static let channelNames = ["Bilateral", "Left", "Bilateral", "Right", "Bilateral"]

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []

        let phase = phaseIndex(elapsed: elapsed, totalDuration: totalDuration)
        if phase != lastPhaseIndex {
            commands.append(Self.channelSequence[phase])
            lastPhaseIndex = phase
        }

        let fade = fadeStrength(elapsed: elapsed, totalDuration: totalDuration, baseStrength: baseStrength)
        if fade != lastFadeStrength {
            commands.append(BLEConstants.strengthCommand(fade))
            lastFadeStrength = fade
        }

        let channelName = Self.channelNames[phase]
        let fadeNote = fade < baseStrength ? " · Fading" : ""
        let status = "\(channelName) channel\(fadeNote)"

        let activeChannels: [ActiveChannel] = [.bilateral, .left, .bilateral, .right, .bilateral]

        return ModeTickResult(
            commands: commands,
            isStimulationActive: true,
            effectiveStrength: fade != baseStrength ? fade : nil,
            activeChannel: activeChannels[phase],
            statusText: status
        )
    }

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let phase = phaseIndex(elapsed: elapsed, totalDuration: totalDuration)
        let fade = fadeStrength(elapsed: elapsed, totalDuration: totalDuration, baseStrength: baseStrength)
        return [Self.channelSequence[phase], BLEConstants.strengthCommand(fade)]
    }
}

// MARK: - Focus Engine
// Left channel (A), 30s on / 30s off, +1 bump at midpoint

struct FocusEngine: ModeEngine {
    private var wasOn = false

    private func isOnPhase(elapsed: Int) -> Bool {
        (elapsed % 60) < 30
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        wasOn = true
        return [BLEConstants.leftChannelCommand, BLEConstants.strengthCommand(baseStrength)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
        let on = isOnPhase(elapsed: elapsed)

        // Transition detection
        if on && !wasOn {
            commands.append(BLEConstants.leftChannelCommand)
            commands.append(BLEConstants.strengthCommand(baseStrength))
        } else if !on && wasOn {
            commands.append(BLEConstants.deactivateCommand)
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

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let on = isOnPhase(elapsed: elapsed)
        if on {
            return [BLEConstants.leftChannelCommand, BLEConstants.strengthCommand(baseStrength)]
        } else {
            return [BLEConstants.deactivateCommand]
        }
    }
}

// MARK: - Pain Relief Engine
// Bilateral (D), intensity oscillates ±1 on 30s sine wave

struct PainReliefEngine: ModeEngine {
    private var lastOffset = 0

    private func strengthOffset(elapsed: Int) -> Int {
        let angle = 2.0 * Double.pi * Double(elapsed) / 30.0
        return Int(sin(angle).rounded())
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        lastOffset = 0
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
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

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        let offset = strengthOffset(elapsed: elapsed)
        let s = max(1, min(9, baseStrength + offset))
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(s)]
    }
}

// MARK: - Headache Engine
// Bilateral (D), high intensity, 2-min on / 30s pause / repeat
// Based on gammaCore protocol (FDA-cleared for migraine)

struct HeadacheEngine: ModeEngine {
    private static let burstDuration = 120   // 2 minutes on
    private static let pauseDuration = 30    // 30 seconds off
    private static let cycleLength = 150     // 2:30 total cycle

    private var wasOn = true

    private func isOnPhase(elapsed: Int) -> Bool {
        (elapsed % Self.cycleLength) < Self.burstDuration
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        wasOn = true
        return [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
        let on = isOnPhase(elapsed: elapsed)

        if on && !wasOn {
            commands.append(BLEConstants.activateCommand)
            commands.append(BLEConstants.strengthCommand(baseStrength))
        } else if !on && wasOn {
            commands.append(BLEConstants.deactivateCommand)
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

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        if isOnPhase(elapsed: elapsed) {
            return [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
        } else {
            return [BLEConstants.deactivateCommand]
        }
    }
}

// MARK: - Nausea Engine
// Bilateral (D), continuous, moderate-high intensity, 5 min
// Based on gammaCore anti-nausea protocol (cervical)

struct NauseaEngine: ModeEngine {
    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        ModeTickResult(isStimulationActive: true, activeChannel: .bilateral, statusText: "Bilateral · Continuous")
    }

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
    }
}

// MARK: - Respiratory-Gated Engine (shared by Calm and Meditation)
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
            return .inhale(progress: Double(pos) / Double(cycle.inhaleDuration))
        } else if pos < exhaleStart {
            let holdPos = pos - holdStart
            return .hold(progress: Double(holdPos) / Double(cycle.holdDuration))
        } else if pos < restStart {
            let exhalePos = pos - exhaleStart
            return .exhale(progress: Double(exhalePos) / Double(cycle.exhaleDuration))
        } else {
            let restPos = pos - restStart
            return .rest(progress: Double(restPos) / Double(cycle.restDuration))
        }
    }

    mutating func start(baseStrength: Int, totalDuration: Int) -> [String] {
        wasStimulating = false
        // Starts with inhale — no activation
        return []
    }

    mutating func tick(elapsed: Int, totalDuration: Int, baseStrength: Int) -> ModeTickResult {
        var commands: [String] = []
        let stimulating = isStimulating(elapsed: elapsed)

        if stimulating && !wasStimulating {
            // Late inhale: activate early so device ramps before exhale
            commands.append(BLEConstants.activateCommand)
            commands.append(BLEConstants.strengthCommand(baseStrength))
        } else if !stimulating && wasStimulating {
            // Exhale → rest: deactivate
            commands.append(BLEConstants.deactivateCommand)
        }
        wasStimulating = stimulating

        let phase = breathingPhase(elapsed: elapsed)
        let status: String
        switch phase {
        case .inhale: status = "Inhale · Paused"
        case .hold:   status = "Hold · Ramping"
        case .exhale: status = "Exhale · Stimulating"
        case .rest:   status = "Rest"
        }

        return ModeTickResult(
            commands: commands,
            isStimulationActive: stimulating,
            breathingPhase: phase,
            activeChannel: stimulating ? .bilateral : .off,
            statusText: status
        )
    }

    func reconnectCommands(elapsed: Int, totalDuration: Int, baseStrength: Int) -> [String] {
        if isStimulating(elapsed: elapsed) {
            return [BLEConstants.activateCommand, BLEConstants.strengthCommand(baseStrength)]
        } else {
            return [BLEConstants.deactivateCommand]
        }
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

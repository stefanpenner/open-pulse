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

// MARK: - Calm Engine
// 10s breathing cycle: 4s inhale (stim OFF), 6s exhale (stim ON)

struct CalmEngine: ModeEngine {
    private static let cycleLength = 15
    private static let inhaleDuration = 5
    private static let holdDuration = 3
    private static let exhaleDuration = 7

    private var wasStimulating = false

    private func cyclePosition(elapsed: Int) -> Int {
        elapsed % Self.cycleLength
    }

    /// Stimulation active during hold + exhale (pos >= inhaleDuration).
    /// Activating at hold lets the device ramp finish before exhale.
    private func isStimulating(elapsed: Int) -> Bool {
        cyclePosition(elapsed: elapsed) >= Self.inhaleDuration
    }

    private func breathingPhase(elapsed: Int) -> BreathingPhase {
        let pos = cyclePosition(elapsed: elapsed)
        if pos < Self.inhaleDuration {
            return .inhale(progress: Double(pos) / Double(Self.inhaleDuration))
        } else if pos < Self.inhaleDuration + Self.holdDuration {
            let holdPos = pos - Self.inhaleDuration
            return .hold(progress: Double(holdPos) / Double(Self.holdDuration))
        } else {
            let exhalePos = pos - Self.inhaleDuration - Self.holdDuration
            return .exhale(progress: Double(exhalePos) / Double(Self.exhaleDuration))
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
            // Inhale → hold: activate (ramp during hold, full intensity by exhale)
            commands.append(BLEConstants.activateCommand)
            commands.append(BLEConstants.strengthCommand(baseStrength))
        } else if !stimulating && wasStimulating {
            // Exhale → inhale: deactivate
            commands.append(BLEConstants.deactivateCommand)
        }
        wasStimulating = stimulating

        let phase = breathingPhase(elapsed: elapsed)
        let status: String
        switch phase {
        case .inhale: status = "Inhale · Paused"
        case .hold: status = "Hold · Ramping"
        case .exhale: status = "Exhale · Stimulating"
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

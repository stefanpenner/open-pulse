import SwiftUI

struct BreathingGuideView: View {
    @ObservedObject var vm: SessionViewModel

    private var phaseLabel: String {
        guard let phase = vm.breathingPhase else { return "" }
        switch phase {
        case .inhale: return "Inhale"
        case .hold:   return "Hold"
        case .exhale: return "Exhale"
        case .rest:   return ""  // quiet gap — no label
        }
    }

    private var cycle: BreathingCycle {
        vm.selectedMode.breathingCycle ?? .calm
    }

    private var phaseCountdown: String {
        guard let phase = vm.breathingPhase else { return "" }
        switch phase {
        case .inhale(let p): return secsLeft(progress: p, duration: cycle.inhaleDuration)
        case .hold(let p):   return secsLeft(progress: p, duration: cycle.holdDuration)
        case .exhale(let p): return secsLeft(progress: p, duration: cycle.exhaleDuration)
        case .rest:          return ""  // quiet gap — no number
        }
    }

    private func secsLeft(progress: Double, duration: Int) -> String {
        // Count from duration down to 1. Each tick shows the number for a full second
        // before decrementing: e.g. for 5s → "5","4","3","2","1" then phase transitions.
        let remaining = duration - Int((Double(duration) * progress).rounded(.down))
        return "\(max(1, remaining))"
    }

    private var circleScale: CGFloat {
        guard let phase = vm.breathingPhase else { return 0.5 }
        switch phase {
        case .inhale(let progress): return 0.5 + 0.5 * progress
        case .hold: return 1.0
        case .exhale(let progress): return 1.0 - 0.5 * progress
        case .rest: return 0.5  // stays contracted, stillness
        }
    }

    private var phaseColor: Color {
        guard let phase = vm.breathingPhase else { return Theme.textSecondary }
        switch phase {
        case .inhale: return Theme.accentPurple
        case .hold: return Theme.accentAmber
        case .exhale: return Theme.accentCyan
        case .rest: return Theme.textTertiary
        }
    }

    private var isActive: Bool {
        if case .exhale = vm.breathingPhase { return true }
        return false
    }

    private var isHolding: Bool {
        if case .hold = vm.breathingPhase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 10) {
            // Phase label above circle
            Text(phaseLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(phaseColor)
                .contentTransition(.interpolate)
                .animation(.easeInOut(duration: 1.8), value: phaseLabel)

            ZStack {
                // Outer ring — color blends with phase
                Circle()
                    .stroke(phaseColor.opacity(0.12), lineWidth: 1.5)
                    .frame(width: 160, height: 160)

                // Breathing circle
                Circle()
                    .fill(phaseColor.opacity(0.25))
                    .frame(width: 140, height: 140)
                    .scaleEffect(circleScale)

                // Hold glow — always rendered, opacity-driven
                Circle()
                    .fill(phaseColor.opacity(0.15))
                    .frame(width: 150, height: 150)
                    .blur(radius: 12)
                    .opacity(isHolding ? 1 : 0)
                    .phaseAnimator([false, true]) { content, phase in
                        content.opacity(isHolding ? (phase ? 0.8 : 0.4) : 0)
                    } animation: { _ in
                        .easeInOut(duration: 1.2)
                    }

                // Inner glow
                Circle()
                    .fill(phaseColor.opacity(isActive ? 0.12 : 0))
                    .frame(width: 60, height: 60)
                    .scaleEffect(circleScale)
                    .blur(radius: 10)

                // Phase countdown number
                Text(phaseCountdown)
                    .font(.system(size: 48, weight: .light, design: .rounded))
                    .foregroundStyle(phaseColor)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.6), value: phaseCountdown)
            }
            .animation(.easeInOut(duration: 2.0), value: circleScale)
            .animation(.easeInOut(duration: 1.8), value: phaseColor)
            .sensoryFeedback(trigger: phaseLabel) { _, newPhase in
                switch newPhase {
                case "Inhale": .impact(weight: .light, intensity: 0.4)
                case "Hold": .impact(weight: .medium, intensity: 0.5)
                case "Exhale": .impact(weight: .heavy, intensity: 0.3)
                default: nil
                }
            }

            // Session progress bar with cycle pattern + minimal timer
            HStack(spacing: 8) {
                BreathingProgressBar(
                    progress: vm.progress,
                    phaseColor: phaseColor,
                    sessionSeconds: vm.timerMinutes * 60,
                    cycle: cycle
                )

                Text(vm.displayTime)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                    .animation(.default, value: vm.remainingSeconds)
            }
            .padding(.horizontal, 16)
            .animation(.easeInOut(duration: 1.2), value: phaseColor)
        }
    }
}

private struct BreathingProgressBar: View {
    let progress: Double
    let phaseColor: Color
    let sessionSeconds: Int
    let cycle: BreathingCycle

    private let barHeight: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Background: cycle pattern showing inhale/hold/exhale/rest phases
                Canvas { context, size in
                    let total = max(1.0, Double(sessionSeconds))
                    let cycleLen = Double(cycle.cycleLength)
                    let cycleW = cycleLen / total * size.width
                    let cycles = Int(ceil(size.width / max(1, cycleW)))

                    let inhaleFrac = Double(cycle.inhaleDuration) / cycleLen
                    let holdFrac = Double(cycle.holdDuration) / cycleLen
                    let exhaleFrac = Double(cycle.exhaleDuration) / cycleLen
                    // rest occupies remaining fraction — drawn as gap (no fill)

                    for i in 0..<cycles {
                        let x = Double(i) * cycleW
                        let inhaleW = inhaleFrac * cycleW
                        let holdW = holdFrac * cycleW
                        let exhaleW = exhaleFrac * cycleW

                        context.fill(
                            Path(CGRect(x: x, y: 0, width: inhaleW, height: size.height)),
                            with: .color(Theme.accentPurple.opacity(0.2))
                        )
                        context.fill(
                            Path(CGRect(x: x + inhaleW, y: 0, width: holdW, height: size.height)),
                            with: .color(Theme.accentAmber.opacity(0.2))
                        )
                        context.fill(
                            Path(CGRect(x: x + inhaleW + holdW, y: 0, width: min(exhaleW, size.width - x - inhaleW - holdW), height: size.height)),
                            with: .color(Theme.accentCyan.opacity(0.2))
                        )
                        // Rest segment: no fill (gap between cycles)
                    }
                }
                .clipShape(Capsule())

                // Foreground: filled progress
                Capsule()
                    .fill(phaseColor)
                    .shadow(color: phaseColor.opacity(0.4), radius: 3)
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 1), value: progress)
            }
        }
        .frame(height: barHeight)
    }
}

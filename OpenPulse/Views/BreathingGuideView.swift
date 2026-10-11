import SwiftUI

struct BreathingGuideView: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var outerRingSize: CGFloat = 160
    @ScaledMetric(relativeTo: .largeTitle) private var breathCircleSize: CGFloat = 140
    @ScaledMetric(relativeTo: .largeTitle) private var holdGlowSize: CGFloat = 150
    @ScaledMetric(relativeTo: .largeTitle) private var innerGlowSize: CGFloat = 60

    private var phaseLabel: String {
        // Pause / offline / incomplete stop-off use shared status (matches Island + hero).
        // Mid-run durable pending alone must not replace breath phase — use Reconnecting via link.
        let showPendingOff = PendingOffPresentation.shouldShowBanner(
            isRunning: vm.isRunning,
            pendingDeviceOff: vm.pendingDeactivate
        )
        if vm.isPaused || showPendingOff || !vm.ble.isReady {
            return vm.sessionStatusText
        }
        guard let phase = vm.breathingPhase else { return "" }
        switch phase {
        case .inhale: return "Inhale"
        case .hold:   return "Hold"
        case .exhale: return "Exhale"
        case .rest:   return ""  // quiet gap — no label
        }
    }

    private var cycle: BreathingCycle {
        // Align UI with resolveEngine: primary Breathe uses pace; legacy meditation uses med cycle
        if vm.selectedMode == .calm {
            return vm.breathePace.cycle
        }
        if vm.selectedMode == .meditation {
            return .meditation
        }
        return vm.selectedMode.breathingCycle ?? vm.breathePace.cycle
    }

    private var phaseCountdown: String {
        if vm.isPaused { return "—" }
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

    /// Matches engine stim window (late inhale prep + hold + exhale), not exhale-only.
    private var isActive: Bool {
        vm.stimulationActive && !vm.isPaused
    }

    private var isHolding: Bool {
        if case .hold = vm.breathingPhase { return true }
        return false
    }

    private var breathingAccessibilityLabel: String {
        let showPendingOff = PendingOffPresentation.shouldShowBanner(
            isRunning: vm.isRunning,
            pendingDeviceOff: vm.pendingDeactivate
        )
        if vm.isPaused || showPendingOff || !vm.ble.isReady {
            return vm.sessionStatusText
        }
        let phase = phaseLabel.isEmpty ? "Breathing" : phaseLabel
        let count = phaseCountdown.isEmpty || phaseCountdown == "—" ? "" : ", \(phaseCountdown)"
        let stim = isActive ? ", session active" : ""
        return "\(phase)\(count)\(stim)"
    }

    var body: some View {
        VStack(spacing: 10) {
            // Phase label above circle (title2+ at accessibility sizes)
            Text(phaseLabel)
                .font(
                    vm.isPaused
                        ? Theme.statusLabel
                        : (dynamicTypeSize.isAccessibilitySize
                            ? .title2.weight(.regular)
                            : Theme.breathingLabel)
                )
                .foregroundStyle(vm.isPaused ? Theme.accentAmber : phaseColor)
                .minimumScaleFactor(0.8)
                .lineLimit(2)
                .contentTransition(reduceMotion ? .identity : .interpolate)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.8), value: phaseLabel)

            ZStack {
                // Outer ring — color blends with phase
                Circle()
                    .stroke((vm.isPaused ? Theme.accentAmber : phaseColor).opacity(0.12), lineWidth: 1.5)
                    .frame(width: outerRingSize, height: outerRingSize)

                // Breathing circle
                Circle()
                    .fill((vm.isPaused ? Theme.accentAmber : phaseColor).opacity(0.25))
                    .frame(width: breathCircleSize, height: breathCircleSize)
                    .scaleEffect(vm.isPaused ? 0.85 : circleScale)

                // Hold glow — static when Reduce Motion; pulse otherwise
                Circle()
                    .fill(phaseColor.opacity(0.15))
                    .frame(width: holdGlowSize, height: holdGlowSize)
                    .blur(radius: 12)
                    .opacity(isHolding && !vm.isPaused ? (reduceMotion ? 0.6 : 1) : 0)
                    .modifier(HoldPulseModifier(
                        isActive: isHolding && !vm.isPaused && !reduceMotion
                    ))

                // Inner glow — follows stimulationActive (prep + hold + exhale)
                Circle()
                    .fill(phaseColor.opacity(isActive ? 0.12 : 0))
                    .frame(width: innerGlowSize, height: innerGlowSize)
                    .scaleEffect(circleScale)
                    .blur(radius: 10)

                // Phase countdown number (Dynamic Type)
                Text(phaseCountdown)
                    .font(.system(.largeTitle, design: .rounded).weight(.light))
                    .foregroundStyle(vm.isPaused ? Theme.accentAmber : phaseColor)
                    .minimumScaleFactor(0.7)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: phaseCountdown)
                    .accessibilityHidden(true)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.0), value: circleScale)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.8), value: phaseColor)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(breathingAccessibilityLabel)
            .sensoryFeedback(trigger: phaseLabel) { _, newPhase in
                // Keep phase haptics even with Reduce Motion — they replace visual motion
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
                    sessionSeconds: vm.sessionDurationSeconds,
                    cycle: cycle
                )

                // Time lives on LiveTimerStepper — progress bar only here
            }
            .padding(.horizontal, 16)
            .animation(reduceMotion ? nil : .easeInOut(duration: 1.2), value: phaseColor)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Session progress")
            .accessibilityValue("\(Int((vm.progress * 100).rounded())) percent complete")
        }
    }
}

/// Hold pulse only when motion is allowed (Reduce Motion → static opacity).
private struct HoldPulseModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if isActive {
            content
                .phaseAnimator([false, true]) { view, phase in
                    view.opacity(phase ? 0.8 : 0.4)
                } animation: { _ in
                    .easeInOut(duration: 1.2)
                }
        } else {
            content
        }
    }
}

private struct BreathingProgressBar: View {
    let progress: Double
    let phaseColor: Color
    let sessionSeconds: Int
    let cycle: BreathingCycle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    .shadow(
                        color: reduceMotion ? .clear : phaseColor.opacity(0.4),
                        radius: reduceMotion ? 0 : 3
                    )
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: barHeight)
    }
}

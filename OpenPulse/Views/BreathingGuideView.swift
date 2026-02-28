import SwiftUI

struct BreathingGuideView: View {
    @ObservedObject var vm: SessionViewModel

    private var phaseText: String {
        guard let phase = vm.breathingPhase else { return "" }
        switch phase {
        case .inhale(let p): return "Inhale \(secsLeft(progress: p, duration: 4))"
        case .hold(let p): return "Hold \(secsLeft(progress: p, duration: 2))"
        case .exhale(let p): return "Exhale \(secsLeft(progress: p, duration: 4))"
        }
    }

    private func secsLeft(progress: Double, duration: Int) -> String {
        let remaining = max(1, Int(ceil(Double(duration) * (1.0 - progress))))
        return "\(remaining)"
    }

    private var circleScale: CGFloat {
        guard let phase = vm.breathingPhase else { return 0.5 }
        switch phase {
        case .inhale(let progress): return 0.5 + 0.5 * progress
        case .hold: return 1.0
        case .exhale(let progress): return 1.0 - 0.5 * progress
        }
    }

    private var phaseColor: Color {
        guard let phase = vm.breathingPhase else { return Theme.textSecondary }
        switch phase {
        case .inhale: return Theme.accentPurple
        case .hold: return Theme.accentAmber
        case .exhale: return Theme.accentCyan
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
        VStack(spacing: 14) {
            Text(phaseText)
                .font(.title2.weight(.medium))
                .foregroundStyle(phaseColor)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: phaseText)

            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                    .frame(width: 140, height: 140)

                // Breathing circle
                Circle()
                    .fill(phaseColor.opacity(0.25))
                    .frame(width: 120, height: 120)
                    .scaleEffect(circleScale)
                    .animation(.easeInOut(duration: 1), value: circleScale)

                // Hold pulsing glow
                if isHolding {
                    Circle()
                        .fill(phaseColor.opacity(0.15))
                        .frame(width: 130, height: 130)
                        .blur(radius: 12)
                        .phaseAnimator([false, true]) { content, phase in
                            content.opacity(phase ? 0.8 : 0.3)
                        } animation: { _ in
                            .easeInOut(duration: 1.0)
                        }
                }

                // Inner glow
                Circle()
                    .fill(
                        isActive
                            ? phaseColor.opacity(0.12)
                            : Color.clear
                    )
                    .frame(width: 60, height: 60)
                    .scaleEffect(circleScale)
                    .blur(radius: 10)
                    .animation(.easeInOut(duration: 1), value: circleScale)

                // Timer overlay
                Text(vm.displayTime)
                    .font(.system(size: 26, weight: .light, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.default, value: vm.remainingSeconds)
            }

            if !vm.modeStatus.isEmpty {
                Text(vm.modeStatus)
                    .font(Theme.statusLabel)
                    .foregroundStyle(phaseColor.opacity(0.8))
                    .contentTransition(.opacity)
                    .animation(.default, value: vm.modeStatus)
            }

            // Progress bar
            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: 3)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(phaseColor)
                            .shadow(color: phaseColor.opacity(0.4), radius: 4)
                            .frame(width: geo.size.width * vm.progress)
                            .animation(.linear(duration: 1), value: vm.progress)
                    }
            }
            .frame(height: 3)
            .padding(.horizontal, 20)
        }
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}

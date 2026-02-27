import SwiftUI

struct BreathingGuideView: View {
    @ObservedObject var vm: SessionViewModel

    private var phaseText: String {
        guard let phase = vm.breathingPhase else { return "" }
        switch phase {
        case .inhale: return "Inhale"
        case .exhale: return "Exhale"
        }
    }

    private var circleScale: CGFloat {
        guard let phase = vm.breathingPhase else { return 0.5 }
        switch phase {
        case .inhale(let progress): return 0.5 + 0.5 * progress
        case .exhale(let progress): return 1.0 - 0.5 * progress
        }
    }

    private var isActive: Bool {
        if case .exhale = vm.breathingPhase { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(phaseText)
                .font(Theme.breathingLabel)
                .foregroundStyle(isActive ? Theme.accentCyan : Theme.textSecondary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: phaseText)

            ZStack {
                // Outer ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
                    .frame(width: 140, height: 140)

                // Breathing circle
                Circle()
                    .fill(
                        isActive
                            ? Theme.accentCyan.opacity(0.25)
                            : Color.white.opacity(0.08)
                    )
                    .frame(width: 120, height: 120)
                    .scaleEffect(circleScale)
                    .animation(.easeInOut(duration: 1), value: circleScale)

                // Inner glow
                Circle()
                    .fill(
                        isActive
                            ? Theme.accentCyan.opacity(0.12)
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
                    .foregroundStyle(isActive ? Theme.accentCyan.opacity(0.8) : Theme.textTertiary)
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
                            .fill(Theme.accentCyan)
                            .shadow(color: Theme.accentCyan.opacity(0.4), radius: 4)
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

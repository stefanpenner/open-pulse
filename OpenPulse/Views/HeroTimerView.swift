import SwiftUI

struct HeroTimerView: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        VStack(spacing: 8) {
            // Mode status
            if !vm.modeStatus.isEmpty {
                Text(vm.isPaused ? "Paused" : vm.modeStatus)
                    .font(Theme.statusLabel)
                    .foregroundStyle(vm.isPaused ? Theme.accentAmber : vm.selectedMode.accentColor.opacity(0.8))
                    .contentTransition(.opacity)
                    .animation(.default, value: vm.modeStatus)
            }

            // Progress bar with embedded timer
            HStack(spacing: 8) {
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(vm.selectedMode.accentColor)
                                .shadow(color: vm.selectedMode.accentColor.opacity(0.4), radius: 4)
                                .frame(width: geo.size.width * vm.progress)
                                .animation(.linear(duration: 1), value: vm.progress)
                        }
                }
                .frame(height: 4)

                Text(vm.displayTime)
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .contentTransition(.numericText())
                    .animation(.default, value: vm.remainingSeconds)
            }
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

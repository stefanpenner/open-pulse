import SwiftUI

struct TimerCardView: View {
    @ObservedObject var vm: SessionViewModel

    private var isLocked: Bool { vm.isRunning || vm.isPaused }

    var body: some View {
        VStack(spacing: 14) {
            // Section header
            VStack(spacing: 4) {
                Text("SESSION TIMER")
                    .font(Theme.sectionLabel)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)

                if vm.selectedMode != .custom {
                    Text(vm.selectedMode.name)
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(vm.selectedMode.accentColor)
                }
            }

            HStack(spacing: 28) {
                // Minus button
                Button {
                    vm.decreaseTimer()
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(isLocked)
                .opacity(isLocked ? 0.25 : 1)

                // Time display
                VStack(spacing: 8) {
                    Text(vm.displayTime)
                        .font(Theme.heroTimer)
                        .foregroundStyle(vm.isPaused ? Theme.textSecondary : Theme.textPrimary)
                        .contentTransition(.numericText())
                        .animation(.default, value: vm.remainingSeconds)

                    // Progress bar
                    if isLocked {
                        GeometryReader { geo in
                            Capsule()
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(vm.selectedMode.accentColor)
                                        .shadow(color: vm.selectedMode.accentColor.opacity(0.4), radius: 4)
                                        .frame(width: geo.size.width * vm.progress)
                                        .animation(.linear(duration: 1), value: vm.progress)
                                }
                        }
                        .frame(height: 3)
                    }

                    // Mode status
                    if isLocked && !vm.modeStatus.isEmpty {
                        Text(vm.isPaused ? "Paused" : vm.modeStatus)
                            .font(Theme.statusLabel)
                            .foregroundStyle(vm.isPaused ? Theme.accentAmber : vm.selectedMode.accentColor.opacity(0.8))
                            .contentTransition(.opacity)
                            .animation(.default, value: vm.modeStatus)
                    }
                }
                .frame(minWidth: 180)

                // Plus button
                Button {
                    vm.increaseTimer()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .disabled(isLocked)
                .opacity(isLocked ? 0.25 : 1)
            }
        }
        .padding(24)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
    }
}

import SwiftUI

struct ModePicker: View {
    @ObservedObject var vm: SessionViewModel

    private var isLocked: Bool { vm.isRunning || vm.isPaused }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(StimulationMode.allCases) { mode in
                    ModeCard(
                        mode: mode,
                        isSelected: vm.selectedMode == mode,
                        action: { vm.selectMode(mode) }
                    )
                }
            }
            .padding(.horizontal, 4)
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.5 : 1)
    }
}

private struct ModeCard: View {
    let mode: StimulationMode
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: mode.icon)
                    .font(.callout)
                    .frame(height: 22)

                Text(mode.name)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : Theme.textSecondary)
            .frame(width: 70, height: 60)
            .glassEffect(
                isSelected
                    ? .regular.tint(mode.accentColor)
                    : .regular,
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
        .buttonStyle(.plain)
    }
}

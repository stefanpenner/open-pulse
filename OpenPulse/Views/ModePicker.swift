import SwiftUI

struct ModePicker: View {
    @ObservedObject var vm: SessionViewModel

    private var isLocked: Bool { vm.isRunning || vm.isPaused }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(AutonomicState.allCases) { state in
                FeelingCard(
                    icon: state.icon,
                    label: state.label,
                    accentColor: state.accentColor,
                    isSelected: vm.selectedFeeling == state,
                    action: { vm.selectFeeling(state) }
                )
            }

            FeelingCard(
                icon: "slider.horizontal.3",
                label: "Custom",
                accentColor: Theme.textSecondary,
                isSelected: vm.selectedMode == .custom && vm.selectedFeeling == nil,
                action: { vm.selectMode(.custom) }
            )
        }
        .disabled(isLocked)
        .opacity(isLocked ? 0.5 : 1)
    }
}

private struct FeelingCard: View {
    let icon: String
    let label: String
    let accentColor: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.callout)
                    .frame(height: 20)

                Text(label)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? .white : accentColor.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
            .glassEffect(
                isSelected
                    ? .regular.tint(accentColor)
                    : .regular.tint(accentColor.opacity(0.12)),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
    }
}

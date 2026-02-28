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

struct ExpandedModePicker: View {
    @ObservedObject var vm: SessionViewModel
    var onInfo: ((StimulationMode) -> Void)? = nil

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
                    subtitle: state.primaryMode.name,
                    accentColor: state.accentColor,
                    isSelected: vm.selectedFeeling == state,
                    expanded: true,
                    onInfo: onInfo != nil ? { onInfo?(state.primaryMode) } : nil,
                    action: { vm.selectFeeling(state) }
                )
            }

            FeelingCard(
                icon: "slider.horizontal.3",
                label: "Custom",
                subtitle: "Manual",
                accentColor: Theme.textSecondary,
                isSelected: vm.selectedMode == .custom && vm.selectedFeeling == nil,
                expanded: true,
                onInfo: nil,
                action: { vm.selectMode(.custom) }
            )
        }
    }
}

struct FeelingCard: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    let accentColor: Color
    let isSelected: Bool
    var expanded: Bool = false
    var onInfo: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: expanded ? 6 : 4) {
                Image(systemName: icon)
                    .font(expanded ? .title3 : .callout)
                    .frame(height: expanded ? 28 : 20)

                Text(label)
                    .font(expanded
                        ? .caption.weight(.semibold)
                        : .system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if expanded, let subtitle {
                    Text(subtitle)
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .foregroundStyle(isSelected ? .white.opacity(0.7) : accentColor.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? .white : accentColor.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: expanded ? 80 : 52)
            .contentShape(Rectangle())
            .overlay(alignment: .topTrailing) {
                if expanded, let onInfo {
                    Button(action: onInfo) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundStyle(isSelected ? .white.opacity(0.6) : accentColor.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .padding(8)
                }
            }
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

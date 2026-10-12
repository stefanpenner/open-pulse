import SwiftUI

struct StrengthCardView: View {
    @ObservedObject var vm: SessionViewModel
    /// Idle Still already shows the shared comfort line — hide duplicate here.
    var showIdleComfortHint: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var controlSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 56 : 48
    }

    /// True when Active line already owns intensity VO (avoid dual announcements).
    private var showsActiveIntensityLine: Bool {
        vm.isRunning && vm.effectiveStrength != nil
    }

    var body: some View {
        VStack(spacing: 14) {
            // Section header
            VStack(spacing: 4) {
                Text("INTENSITY")
                    .font(Theme.sectionLabel)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)

                if let eff = vm.effectiveStrength, vm.isRunning {
                    Text(eff == 0 ? "Off" : "Active: \(eff)")
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(vm.selectedMode.accentColor)
                        .accessibilityLabel(
                            SessionDurationOptions.activeIntensityAccessibility(
                                effective: eff,
                                target: vm.strength
                            )
                        )
                } else if showIdleComfortHint, !vm.isRunning, !vm.isPaused {
                    // Shared Still comfort line (settings sheet only by default)
                    Text(SessionDurationOptions.softStartComfortHint)
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .accessibilityLabel(SessionDurationOptions.softStartComfortHint)
                }
            }

            // Strength display with +/- buttons
            HStack(spacing: 20) {
                Button {
                    vm.setStrength(vm.strength - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.medium))
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Circle())
                }
                .wellnessGlass(.regular.interactive(), in: .circle)
                .accessibilityLabel("Decrease intensity")

                // Strength badge — target control (Active line owns effective VO)
                Text("\(vm.strength)")
                    .font(Theme.heroNumber)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(minWidth: controlSize + 28, minHeight: controlSize)
                    .wellnessGlass(.regular.tint(Theme.accentBlue), in: .capsule)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .default, value: vm.strength)
                    .accessibilityLabel("Target intensity \(vm.strength) of 9")
                    .accessibilityHidden(showsActiveIntensityLine)

                Button {
                    vm.setStrength(vm.strength + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(width: controlSize, height: controlSize)
                        .contentShape(Circle())
                }
                .wellnessGlass(.regular.interactive(), in: .circle)
                .accessibilityLabel("Increase intensity")
            }

            // Slider
            HStack(spacing: 10) {
                Text("1")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)

                Slider(
                    value: Binding(
                        get: { Double(vm.strength) },
                        set: { vm.setStrength(Int($0.rounded())) }
                    ),
                    in: 1...9,
                    step: 1
                )
                .tint(Theme.accentBlue)
                .accessibilityLabel("Intensity")
                .accessibilityValue("\(vm.strength)")

                Text("9")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        // Content card = solid surface; ± / badge keep glass (control layer)
        .wellnessContentSurface(in: RoundedRectangle(cornerRadius: 16))
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: vm.strength
        )
    }
}

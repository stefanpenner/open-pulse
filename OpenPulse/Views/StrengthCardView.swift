import SwiftUI

/// Intensity: one control, one number. The number is the target.
/// During the soft ease-in, the ring under the number fills to the target.
struct StrengthCardView: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var controlSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 56 : 48
    }

    /// 0…1 of the target that the device runs now. Nil when idle.
    private var rampFraction: Double? {
        guard vm.isRunning, let eff = vm.effectiveStrength, vm.strength > 0 else { return nil }
        return min(1, Double(eff) / Double(vm.strength))
    }

    var body: some View {
        HStack(spacing: Theme.spaceM) {
            Text("Intensity")
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)

            Spacer(minLength: 0)

            nudge("minus", label: "Decrease intensity", by: -1)
                .disabled(vm.strength <= 1)

            Text("\(vm.strength)")
                .font(Theme.heroNumber)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .frame(minWidth: controlSize + 12, minHeight: controlSize)
                .overlay(alignment: .bottom) { rampBar }
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .default, value: vm.strength)
                .accessibilityHidden(true)

            nudge("plus", label: "Increase intensity", by: 1)
                .disabled(vm.strength >= 9)
        }
        .padding(.horizontal, Theme.spaceL)
        .padding(.vertical, 12)
        .wellnessContentSurface(in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Intensity")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("session.intensity")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: vm.setStrength(vm.strength + 1)
            case .decrement: vm.setStrength(vm.strength - 1)
            @unknown default: break
            }
        }
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: vm.strength
        )
    }

    private var accessibilityValue: String {
        if let eff = vm.effectiveStrength, vm.isRunning, eff != vm.strength {
            return SessionDurationOptions.activeIntensityAccessibility(effective: eff, target: vm.strength)
        }
        return "\(vm.strength) of 9"
    }

    /// A thin bar under the number. It shows only while the device eases in.
    @ViewBuilder
    private var rampBar: some View {
        if let f = rampFraction, f < 1 {
            Capsule()
                .fill(Theme.textTertiary.opacity(0.4))
                .frame(width: 28, height: 3)
                .overlay(alignment: .leading) {
                    Capsule().fill(vm.selectedMode.accentColor).frame(width: 28 * f, height: 3)
                }
                .offset(y: 2)
                .animation(reduceMotion ? nil : .easeInOut, value: f)
        }
    }

    private func nudge(_ icon: String, label: String, by delta: Int) -> some View {
        Button(label, systemImage: icon) { vm.setStrength(vm.strength + delta) }
            .labelStyle(.iconOnly)
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .frame(width: controlSize, height: controlSize)
            .contentShape(Circle())
            .buttonStyle(.plain)
            .wellnessGlass(.regular.interactive(), in: .circle)
    }
}

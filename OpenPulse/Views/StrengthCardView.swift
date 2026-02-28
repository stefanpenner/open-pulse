import SwiftUI

struct StrengthCardView: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        VStack(spacing: 14) {
            // Section header
            VStack(spacing: 4) {
                Text("INTENSITY")
                    .font(Theme.sectionLabel)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)

                if let eff = vm.effectiveStrength, vm.isRunning {
                    Text(eff == 0 ? "Off" : "Active: \(eff)")
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(vm.selectedMode.accentColor)
                }
            }

            // Strength display with +/- buttons
            HStack(spacing: 20) {
                Button {
                    vm.setStrength(vm.strength - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.body.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                // Strength badge
                Text("\(vm.strength)")
                    .font(Theme.heroNumber)
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 48)
                    .glassEffect(.regular.tint(Theme.accentBlue), in: .capsule)
                    .contentTransition(.numericText())
                    .animation(.default, value: vm.strength)

                Button {
                    vm.setStrength(vm.strength + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.medium))
                        .frame(width: 48, height: 48)
                }
                .glassEffect(.regular.interactive(), in: .circle)
            }

            // Slider
            HStack(spacing: 10) {
                Text("1")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)

                Slider(
                    value: Binding(
                        get: { Double(vm.strength) },
                        set: { vm.setStrength(Int($0.rounded())) }
                    ),
                    in: 1...9,
                    step: 1
                )
                .tint(Theme.accentBlue)

                Text("9")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }
}

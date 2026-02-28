import SwiftUI

struct ActiveSessionLayout: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        VStack(spacing: 12) {
            StatusBarView(vm: vm)

            // Mode name label
            Text(vm.selectedMode.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(vm.selectedMode.accentColor)
                .tracking(0.5)

            ChannelIndicatorView(
                activeChannel: vm.activeChannel,
                accentColor: vm.selectedMode.accentColor
            )

            if vm.selectedMode == .calm {
                BreathingGuideView(vm: vm)
            } else {
                HeroTimerView(vm: vm)
            }

            if vm.stimulationActive {
                IntensityWaveView(
                    strength: vm.strength,
                    effectiveStrength: vm.effectiveStrength,
                    accentColor: vm.selectedMode.accentColor
                )
                .padding(.horizontal, 20)
            }

            StrengthCardView(vm: vm)

            Spacer()

            ActionButtonView(vm: vm)
        }
    }
}

import SwiftUI

struct ActiveSessionLayout: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        GeometryReader { geo in
            let heroHeight = geo.size.height * 2.0 / 3.0

            VStack(spacing: 0) {
                // Top 2/3: session hero area
                VStack(spacing: 12) {
                    StatusBarView(vm: vm)

                    Text(vm.selectedMode.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(vm.selectedMode.accentColor)
                        .tracking(0.5)

                    ChannelIndicatorView(
                        activeChannel: vm.activeChannel,
                        accentColor: vm.selectedMode.accentColor
                    )

                    Spacer(minLength: 0)

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

                    Spacer(minLength: 0)
                }
                .frame(height: heroHeight)

                // Bottom 1/3: controls
                VStack(spacing: 8) {
                    StrengthCardView(vm: vm)

                    if vm.selectedMode == .custom {
                        ChannelCommandPanel(vm: vm)
                    }

                    Spacer(minLength: 0)

                    ActionButtonView(vm: vm)
                }
            }
        }
    }
}

private struct ChannelCommandPanel: View {
    @ObservedObject var vm: SessionViewModel

    private let buttons: [(label: String, cmd: String)] = [
        ("OFF", "0"),
        ("Left", "A"),
        ("Ramp", "B"),
        ("Right", "C"),
        ("Both", "D"),
    ]

    var body: some View {
        VStack(spacing: 6) {
            Text("CHANNEL")
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.5)
            HStack(spacing: 6) {
                ForEach(buttons, id: \.cmd) { btn in
                    let isActive = vm.debugActiveChannel == btn.cmd
                    Button {
                        vm.sendDebugCommand(btn.cmd)
                    } label: {
                        Text(btn.label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isActive ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                    }
                    .background(isActive ? Theme.accentTeal.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

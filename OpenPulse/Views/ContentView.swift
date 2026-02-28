import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SessionViewModel()

    private var accentColor: Color {
        if let feeling = vm.selectedFeeling {
            return feeling.accentColor
        }
        return vm.selectedMode.accentColor
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            RadialGradient(
                colors: [accentColor.opacity(0.1), .clear],
                center: .top,
                startRadius: 50,
                endRadius: 500
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: vm.selectedMode)
            .animation(.easeInOut(duration: 0.6), value: vm.selectedFeeling)

            GlassEffectContainer {
                VStack(spacing: 12) {
                    StatusBarView(vm: vm)
                    ModePicker(vm: vm)
                    ModeDescriptionView(mode: vm.selectedMode)
                        .animation(.default, value: vm.selectedMode)
                    if vm.selectedMode == .calm && vm.isRunning {
                        BreathingGuideView(vm: vm)
                    } else {
                        TimerCardView(vm: vm)
                    }
                    StrengthCardView(vm: vm)
                    Spacer()
                    ActionButtonView(vm: vm)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ModeDescriptionView: View {
    let mode: StimulationMode

    var body: some View {
        VStack(spacing: 4) {
            Text(mode.summary)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)

            if !mode.researchLinks.isEmpty {
                VStack(spacing: 2) {
                    Text("Evidence: \(mode.evidenceLevel)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(mode.accentColor.opacity(0.7))
                        .tracking(0.3)

                    ForEach(mode.researchLinks, id: \.url) { link in
                        if let url = URL(string: link.url) {
                            Link(destination: url) {
                                Text(link.label)
                                    .font(.system(size: 9, weight: .regular))
                                    .foregroundStyle(Theme.accentBlue.opacity(0.7))
                                    .underline()
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SessionViewModel()

    var body: some View {
        ZStack {
            Theme.backgroundGradient
                .ignoresSafeArea()

            GlassEffectContainer {
                VStack(spacing: 16) {
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
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct ModeDescriptionView: View {
    let mode: StimulationMode

    var body: some View {
        VStack(spacing: 5) {
            Text(mode.summary)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)

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

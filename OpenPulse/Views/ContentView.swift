import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SessionViewModel()

    private var isActive: Bool { vm.isRunning || vm.isPaused }

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
                Group {
                    if isActive {
                        ActiveSessionLayout(vm: vm)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    } else {
                        IdleSessionLayout(vm: vm)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
                .animation(.spring(duration: 0.5, bounce: 0.15), value: isActive)
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}

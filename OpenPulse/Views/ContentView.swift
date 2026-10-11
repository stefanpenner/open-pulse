import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SessionViewModel()
    @State private var showOnboarding: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {
        _showOnboarding = State(initialValue: !AppPreferences.hasCompletedOnboarding())
    }

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

            // Soft mode-tinted bloom — Tide Glass: depth without sugar-high gloss
            RadialGradient(
                colors: [accentColor.opacity(Theme.modeBloomOpacity), .clear],
                center: .top,
                startRadius: 40,
                endRadius: 420
            )
            .ignoresSafeArea()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: vm.selectedMode)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.6), value: vm.selectedFeeling)

            GlassEffectContainer {
                Group {
                    if isActive {
                        if reduceMotion {
                            ActiveSessionLayout(vm: vm)
                                .transition(.opacity)
                        } else {
                            ActiveSessionLayout(vm: vm)
                                .transition(.blurReplace)
                        }
                    } else {
                        if reduceMotion {
                            IdleSessionLayout(vm: vm)
                                .transition(.opacity)
                        } else {
                            IdleSessionLayout(vm: vm)
                                .transition(.blurReplace)
                        }
                    }
                }
                .padding(.horizontal, Theme.spaceL)
                .padding(.top, Theme.spaceS)
                .padding(.bottom, Theme.spaceXL + 4)
                .animation(
                    reduceMotion ? nil : .spring(duration: 0.5, bounce: 0.15),
                    value: isActive
                )
            }
        }
        .preferredColorScheme(.dark)
        .overlay(alignment: .top) {
            if let banner = vm.completionBanner {
                Text(banner)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // Status toast (content), not interactive control glass
                    .wellnessContentSurface(
                        in: .capsule,
                        color: Theme.accentTeal.opacity(0.85)
                    )
                    .padding(.top, 56)
                    .transition(
                        reduceMotion
                            ? AnyTransition.opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .accessibilityLabel(banner)
                    .onAppear {
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2.5))
                            if reduceMotion {
                                vm.clearCompletionBanner()
                            } else {
                                withAnimation(.easeOut(duration: 0.35)) {
                                    vm.clearCompletionBanner()
                                }
                            }
                        }
                    }
            }
        }
        .animation(
            reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2),
            value: vm.completionBanner
        )
        .sensoryFeedback(trigger: vm.completionBanner) { _, new in
            guard new != nil else { return nil }
            return reduceMotion ? .impact(weight: .light) : .success
        }
        // Device off confirmed via write ACK only (not start/resume clearing pending)
        .sensoryFeedback(trigger: vm.deviceOffConfirmedToken) { old, new in
            guard new > old else { return nil }
            return reduceMotion ? .impact(weight: .light) : .success
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                AppPreferences.markOnboardingCompleted()
                showOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .appScenePhaseChanged)) { notification in
            guard let userInfo = notification.userInfo,
                  let oldPhase = userInfo["oldPhase"] as? ScenePhase,
                  let newPhase = userInfo["newPhase"] as? ScenePhase else { return }
            if newPhase == .background {
                vm.handleBackgroundTransition()
            } else if oldPhase == .background {
                vm.handleForegroundTransition()
                // User may have flipped system notification permission while away
                vm.refreshSessionEndAlertAuthorization()
            }
        }
        // Live Activity intents + wall complete use SessionActionBridge only
        .onAppear {
            SessionActionBridge.shared.bind(vm)
        }
        .onChange(of: vm.ble.isReady) { _, ready in
            if ready { SessionActionBridge.shared.drainPending() }
        }
        // Battery-read grace / sample can flip canStart without a ready edge
        .onChange(of: vm.canStart) { _, can in
            if can { SessionActionBridge.shared.drainPending() }
        }
    }
}

#Preview {
    ContentView()
}

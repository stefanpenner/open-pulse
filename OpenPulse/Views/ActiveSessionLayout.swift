import SwiftUI

struct ActiveSessionLayout: View {
    @ObservedObject var vm: SessionViewModel
    @State private var showingInfo = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isA11yType: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        Group {
            if isA11yType {
                ScrollView {
                    activeStack(heroHeight: nil)
                        .padding(.bottom, 8)
                }
            } else {
                GeometryReader { geo in
                    let heroHeight = geo.size.height * 2.0 / 3.0
                    activeStack(heroHeight: heroHeight)
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.3),
            value: vm.pendingDeactivate
        )
        .sheet(isPresented: $showingInfo) {
            ModeInfoSheet(mode: vm.selectedMode)
                .presentationDetents([.medium])
                .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func activeStack(heroHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            // Top: session hero area
            VStack(spacing: 12) {
                StatusBarView(vm: vm)

                // Incomplete stop/pause off — not mid-run reconnect (session still active)
                if PendingOffPresentation.shouldShowBanner(
                    isRunning: vm.isRunning,
                    pendingDeviceOff: vm.pendingDeactivate
                ) {
                    PendingOffBanner(isReady: vm.ble.isReady, isPaused: vm.isPaused)
                        .padding(.horizontal, 4)
                        .transition(.opacity)
                }

                // Still: quiet mode word — soft accent, not rainbow chrome
                HStack(spacing: 6) {
                    Text(vm.sessionTitle)
                        .font(isA11yType ? .title3.weight(.medium) : .subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .tracking(isA11yType ? 0.4 : 0.8)
                        .minimumScaleFactor(isA11yType ? 0.85 : 0.85)
                        .lineLimit(isA11yType ? 3 : 2)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("\(vm.sessionTitle) session")

                    if vm.selectedMode != .custom {
                        Button { showingInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(isA11yType ? .body : .caption)
                                .foregroundStyle(vm.selectedMode.accentColor.opacity(0.45))
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("About \(vm.sessionTitle)")
                    }
                }

                ChannelIndicatorView(
                    activeChannel: vm.activeChannel,
                    accentColor: vm.selectedMode.accentColor
                )

                if heroHeight != nil {
                    Spacer(minLength: 0)
                }

                // Tide-in-Still: breath owns the field for Breathe; timer elsewhere is secondary
                if vm.selectedMode.usesBreathingGuide {
                    BreathingGuideView(vm: vm)
                } else {
                    HeroTimerView(vm: vm)
                }

                // Still motion budget: Tide owns the field for Breathe — no competing wave
                if vm.stimulationActive, !vm.selectedMode.usesBreathingGuide {
                    IntensityWaveView(
                        strength: vm.strength,
                        effectiveStrength: vm.effectiveStrength,
                        accentColor: vm.selectedMode.accentColor
                    )
                    .padding(.horizontal, 20)
                }

                if heroHeight != nil {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: heroHeight)

            // Bottom: controls
            VStack(spacing: 8) {
                StrengthCardView(vm: vm, showIdleComfortHint: false)

                // ±time for all modes (engine already anchors Sleep phase / fade)
                if vm.isRunning || vm.isPaused {
                    LiveTimerStepper(vm: vm)
                }

                if vm.selectedMode == .custom, vm.isRunning {
                    ChannelCommandPanel(vm: vm)
                }

                if heroHeight != nil {
                    Spacer(minLength: 0)
                }

                ActionButtonView(vm: vm)
            }
        }
    }
}

private struct LiveTimerStepper: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canDecrease: Bool { vm.remainingSeconds > 60 }
    private var isA11yType: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        HStack(spacing: 6) {
            // Glass on controls only
            Button { vm.decreaseTimer() } label: {
                Image(systemName: "minus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(canDecrease ? Theme.textPrimary : Theme.textTertiary.opacity(0.35))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canDecrease)
            .wellnessGlass(.regular.interactive(), in: .circle)
            .accessibilityLabel("Decrease remaining time")
            .accessibilityHint(canDecrease ? "Subtract one minute" : "Minimum one minute remaining")

            // Solid hero time field (readable mid-session)
            Text(vm.displayTime)
                .font(isA11yType ? Theme.heroTimerA11y : .title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .frame(minWidth: isA11yType ? 120 : 88)
                .padding(.vertical, isA11yType ? 10 : 6)
                .padding(.horizontal, 12)
                .wellnessContentSurface(
                    in: .capsule,
                    color: Theme.contentHeroFill
                )
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .default, value: vm.remainingSeconds)
                .accessibilityLabel(
                    LiveActivityPresentation.timeAccessibility(
                        remainingSeconds: vm.remainingSeconds
                    )
                )

            Button { vm.increaseTimer() } label: {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .wellnessGlass(.regular.interactive(), in: .circle)
            .accessibilityLabel("Increase remaining time")
            .accessibilityHint("Add one minute")
        }
        .padding(.vertical, 4)
        // User ± only — not every wall-clock second; light haptic under Reduce Motion
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: vm.userAdjustedRemainingToken
        )
    }
}

private struct ChannelCommandPanel: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttons: [(label: String, cmd: String, a11y: String)] = [
        ("OFF", "0", "Turn channels off"),
        ("Left", "A", "Left channel"),
        ("Ramp", "B", "Ramp intensity"),
        ("Right", "C", "Right channel"),
        ("Both", "D", "Both channels"),
    ]

    var body: some View {
        VStack(spacing: 6) {
            Text("CHANNEL")
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.5)
                .accessibilityAddTraits(.isHeader)
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
                            .frame(minHeight: 44)
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .background(isActive ? Theme.accentTeal.opacity(0.3) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                    .wellnessGlass(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel(btn.a11y)
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
        }
        .padding(.horizontal, 12)
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: vm.debugActiveChannel
        )
    }
}

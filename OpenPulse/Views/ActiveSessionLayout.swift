import SwiftUI

struct ActiveSessionLayout: View {
    @ObservedObject var vm: SessionViewModel
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                StatusBarView(vm: vm, ownsGlass: false)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func activeStack(heroHeight: CGFloat?) -> some View {
        VStack(spacing: 0) {
            // Top: session hero area
            VStack(spacing: Theme.spaceM) {
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
                        .font(Theme.screenTitle)
                        .foregroundStyle(Theme.textPrimary.opacity(0.92))
                        .minimumScaleFactor(isA11yType ? 0.85 : 0.85)
                        .lineLimit(isA11yType ? 3 : 2)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityLabel("\(vm.sessionTitle) session")

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
                    LiveTimerStepper(vm: vm, isHero: true)
                }
                if heroHeight != nil {
                    Spacer(minLength: 0)
                }
            }
            .frame(height: heroHeight)

            // Bottom: controls
            VStack(spacing: 8) {
                StrengthCardView(vm: vm)

                // ±time for all modes (engine already anchors Sleep phase / fade)
                if vm.selectedMode.usesBreathingGuide {
                    LiveTimerStepper(vm: vm, isHero: false)
                }

                if vm.selectedMode == .custom, vm.isRunning {
                    ChannelCommandPanel(vm: vm)
                }

                if heroHeight != nil {
                    Spacer(minLength: 0)
                }

                ActionButtonView(vm: vm)
            }
            .padding(.top, heroHeight == nil ? 0 : Theme.spaceXL)
        }
    }
}

private struct LiveTimerStepper: View {
    @ObservedObject var vm: SessionViewModel
    /// True when the clock is the main item on screen.
    let isHero: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var canDecrease: Bool { vm.remainingSeconds > 60 }
    private var isA11yType: Bool { dynamicTypeSize.isAccessibilitySize }

    private var timeFont: Font {
        if isA11yType { return Theme.heroTimerA11y }
        return isHero ? Theme.heroClock : .title3.weight(.semibold).monospacedDigit()
    }

    var body: some View {
        Group {
            if isHero && !isA11yType { ringClock } else { inlineClock }
        }
        // User ± only — not every wall-clock second; light haptic under Reduce Motion
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: vm.userAdjustedRemainingToken
        )
    }

    /// The clock sits inside a progress ring. Labeled buttons sit under it.
    private var ringClock: some View {
        let accent = vm.selectedMode.accentColor
        return VStack(spacing: Theme.spaceL) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: vm.progress)
                    .stroke(accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(reduceMotion ? 0 : 0.45), radius: 8)
                    .animation(reduceMotion ? nil : .linear(duration: 1), value: vm.progress)
                timeText
            }
            .frame(width: 236, height: 236)
            .accessibilityElement(children: .combine)
            .accessibilityValue("\(Int((vm.progress * 100).rounded())) percent complete")

            HStack(spacing: Theme.spaceM) {
                stepButton("minus", enabled: canDecrease) { vm.decreaseTimer() }
                    .accessibilityLabel("Subtract one minute")
                stepButton("plus", enabled: true) { vm.increaseTimer() }
                    .accessibilityLabel("Add one minute")
            }
        }
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("1 min", systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary.opacity(0.4))
                .padding(.horizontal, Theme.spaceL)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .wellnessGlass(.regular.interactive(), in: .capsule)
    }

    private var timeText: some View {
        Text(vm.displayTime)
            .font(timeFont)
            .foregroundStyle(Theme.textPrimary)
            .minimumScaleFactor(0.75)
            .lineLimit(1)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .default, value: vm.remainingSeconds)
            .accessibilityLabel(
                LiveActivityPresentation.timeAccessibility(remainingSeconds: vm.remainingSeconds)
            )
    }

    private var inlineClock: some View {
        HStack(spacing: isHero ? Theme.spaceL : 6) {
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
                .font(timeFont)
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                .frame(minWidth: isA11yType ? 120 : 88)
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
            Text("Channel")
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.textTertiary)
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

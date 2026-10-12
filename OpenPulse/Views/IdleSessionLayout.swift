import SwiftUI

/// Still shell — one screen, one primary action.
/// Mode is a large tappable title; grid picker retired for cognitive calm.
struct IdleSessionLayout: View {
    @ObservedObject var vm: SessionViewModel
    @State private var showModeSheet = false
    @State private var showHistory = false
    /// Expand intensity until the user has stored a level.
    @State private var showStrength = false
    @State private var didSeedStrengthDisclosure = false
    @State private var showPrivacySettings = false
    @State private var infoMode: StimulationMode? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var modeAccent: Color {
        if let feeling = vm.selectedFeeling {
            return feeling.accentColor
        }
        return vm.selectedMode.accentColor
    }

    /// Quiet logbook line — always present for VoiceOver / hierarchy (never blank strip).
    private var logbookWhisperText: String {
        if vm.minutesToday > 0 {
            return "\(vm.minutesToday) min today"
        }
        if vm.ble.isReady && vm.recentSessions.isEmpty {
            return "Ready for a short session"
        }
        if !vm.recentSessions.isEmpty {
            let week = SessionHistory.minutesThisWeek(defaults: vm.defaults)
            return "\(week) min this week"
        }
        if vm.ble.isBluetoothOff {
            return "Turn on Bluetooth to begin"
        }
        if !vm.ble.isConnected {
            return "Looking for your Pulsetto"
        }
        return "Connecting…"
    }

    var body: some View {
        VStack(spacing: Theme.spaceM) {
            connection
            modeHero
            durationChoices
            startControl
            strengthDisclosure
            logbook
            wellnessLine
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.35),
            value: vm.ble.isReady
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.3),
            value: vm.pendingDeactivate
        )
        .sheet(isPresented: $showModeSheet) {
            ModeSelectSheet(vm: vm)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .sheet(item: $infoMode) { mode in
            ModeInfoSheet(mode: mode)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistorySheet(sessions: vm.recentSessions) {
                vm.clearSessionHistory()
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPrivacySettings) {
            SessionPrivacySettingsSheet(vm: vm)
        }
        .onAppear(perform: seedStrengthDisclosure)
    }

    private var connection: some View {
        VStack(spacing: Theme.spaceM) {
            StatusBarView(vm: vm, hideConnectionChip: !vm.ble.isReady)

            if !vm.ble.isReady {
                if reduceMotion {
                    ConnectionEmptyState(vm: vm)
                        .transition(.opacity)
                } else {
                    ConnectionEmptyState(vm: vm)
                        .transition(.blurReplace)
                }
            }

            if vm.pendingDeactivate {
                if reduceMotion {
                    PendingOffBanner(isReady: vm.ble.isReady)
                        .transition(.opacity)
                } else {
                    PendingOffBanner(isReady: vm.ble.isReady)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }

            Spacer(minLength: Theme.spaceS)
        }
    }

    private var modeHero: some View {
        Button {
            showModeSheet = true
        } label: {
            VStack(spacing: 6) {
                Text(vm.sessionTitle.uppercased())
                    .font(Theme.heroMode)
                    .foregroundStyle(Theme.textPrimary)
                    .tracking(dynamicTypeSize.isAccessibilitySize ? 0.5 : 2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.85 : 0.7)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(vm.timerMinutes) min")
                    .font(.title3.weight(.light).monospacedDigit())
                    .foregroundStyle(modeAccent.opacity(0.9))
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)

                Text("Tap to change")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spaceL)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vm.sessionTitle), \(vm.timerMinutes) minutes")
        .accessibilityHint("Opens mode list")
        .disabled(vm.isRunning || vm.isPaused)
    }

    private var durationChoices: some View {
        VStack(spacing: Theme.spaceM) {
            DurationPresetRow(vm: vm)
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25),
                    value: vm.selectedMode
                )

            if vm.selectedMode.usesBreathingGuide {
                advancedSegmented(
                    title: "Pace",
                    selection: Binding(
                        get: { vm.breathePace },
                        set: { vm.breathePace = $0 }
                    ),
                    options: BreathePace.allCases,
                    label: { $0.label }
                )
            } else if vm.selectedMode == .painRelief {
                advancedSegmented(
                    title: "Pattern",
                    selection: Binding(
                        get: { vm.easePattern },
                        set: { vm.easePattern = $0 }
                    ),
                    options: EasePattern.allCases,
                    label: { $0.label }
                )
            }

            Spacer(minLength: Theme.spaceS)
        }
    }

    private var startControl: some View {
        VStack(spacing: Theme.spaceM) {
            ActionButtonView(vm: vm)

            Text(SessionDurationOptions.softStartComfortHint)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(SessionDurationOptions.softStartComfortHint)
        }
    }

    private var strengthDisclosure: some View {
        VStack(spacing: Theme.spaceM) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    showStrength.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Intensity")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(vm.strength)")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Image(systemName: showStrength ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Intensity \(vm.strength)")
            .accessibilityHint(showStrength ? "Collapse intensity control" : "Expand intensity control")

            if showStrength {
                StrengthCardView(vm: vm, showIdleComfortHint: false)
                    .transition(.opacity)
            }
        }
    }

    private var logbook: some View {
        HStack(spacing: 12) {
            Text(logbookWhisperText)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .accessibilityLabel(logbookWhisperText)

            Spacer(minLength: 0)

            Button {
                showHistory = true
            } label: {
                Text("History")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accentTeal.opacity(0.9))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Session history")
            .accessibilityHint(
                vm.recentSessions.isEmpty
                    ? "No sessions yet. Stored only on this device."
                    : "Opens your private session log"
            )

            Button {
                showPrivacySettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Privacy settings")
            .accessibilityHint("Mindful Minutes and session end alerts. On-device only.")

            Button {
                infoMode = vm.selectedMode == .custom
                    ? .custom
                    : (vm.selectedFeeling?.primaryMode ?? vm.selectedMode)
            } label: {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("About \(vm.sessionTitle)")
        }
        .padding(.horizontal, 4)
    }

    private var wellnessLine: some View {
        Text("Wellness device control — not a medical treatment.")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.top, Theme.spaceXS)
    }

    private func seedStrengthDisclosure() {
        guard !didSeedStrengthDisclosure else { return }
        didSeedStrengthDisclosure = true
        let hasStored = AppPreferences.lastStrength(defaults: vm.defaults) != nil
        showStrength = IntensityIdlePolicy.expandByDefault(hasStoredStrength: hasStored)
    }

    @ViewBuilder
    private func advancedSegmented<T: Hashable & Identifiable>(
        title: String,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.textTertiary)
                .tracking(1.5)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = selection.wrappedValue.id == option.id
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(label(option))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? .white : Theme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .wellnessGlass(
                        selected
                            ? .regular.tint(modeAccent)
                            : .regular.tint(modeAccent.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .accessibilityLabel(label(option))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: selection.wrappedValue.id
        )
    }
}

// MARK: - Mode select sheet (Still)

struct ModeSelectSheet: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AutonomicState.pickerCases) { state in
                        modeRow(
                            title: state.primaryMode.name,
                            subtitle: state.whenToUse,
                            icon: state.icon,
                            accent: state.accentColor,
                            selected: isFeelingSelected(state)
                        ) {
                            vm.selectFeeling(state)
                            dismiss()
                        }
                    }

                    modeRow(
                        title: "Custom",
                        subtitle: "Manual timer and intensity",
                        icon: "slider.horizontal.3",
                        accent: Theme.textSecondary,
                        selected: vm.selectedMode == .custom && vm.selectedFeeling == nil
                    ) {
                        vm.selectMode(.custom)
                        dismiss()
                    }
                } header: {
                    Text("Session")
                } footer: {
                    Text("Five sessions plus Custom. Stress is the default. Wellness only — not a medical treatment.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func isFeelingSelected(_ state: AutonomicState) -> Bool {
        if vm.selectedMode == .custom { return false }
        if let feeling = vm.selectedFeeling {
            return feeling == state
        }
        return AutonomicState.pickerFeeling(for: vm.selectedMode) == state
    }

    private func modeRow(
        title: String,
        subtitle: String,
        icon: String,
        accent: Color,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accentTeal)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.solidSurfaceElevated.opacity(0.6))
        .accessibilityLabel(title)
        .accessibilityHint(subtitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Mode info

struct ModeInfoSheet: View {
    let mode: StimulationMode
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: mode.icon)
                            .font(.title2)
                            .foregroundStyle(mode.accentColor)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.name)
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)

                            if !mode.evidenceLevel.isEmpty {
                                Text(mode.evidenceLevel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(mode.accentColor.opacity(0.8))
                            }
                        }
                    }

                    Text(mode.summary)
                        .font(.body)
                        .foregroundStyle(Theme.textSecondary)

                    Text("For general wellness only. Not intended to diagnose, treat, cure, or prevent any disease. Consult a clinician if you have questions.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)

                    if !mode.researchLinks.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("RESEARCH")
                                .font(Theme.sectionLabel)
                                .foregroundStyle(Theme.textTertiary)
                                .tracking(1.5)

                            ForEach(mode.researchLinks, id: \.url) { link in
                                if let url = URL(string: link.url) {
                                    Link(destination: url) {
                                        HStack {
                                            Text(link.label)
                                                .font(.callout)
                                                .foregroundStyle(Theme.accentBlue)
                                                .multilineTextAlignment(.leading)

                                            Spacer()

                                            Image(systemName: "arrow.up.right")
                                                .font(.caption)
                                                .foregroundStyle(Theme.accentBlue.opacity(0.6))
                                        }
                                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel(link.label)
                                    .accessibilityHint("Opens in browser")
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle(mode.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

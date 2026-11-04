import SwiftUI

/// Still shell — one screen, one primary action.
/// Mode is a large tappable title; grid picker retired for cognitive calm.
struct IdleSessionLayout: View {
    @ObservedObject var vm: SessionViewModel
    @State private var showModeSheet = false
    @State private var showHistory = false
    @State private var showPrivacySettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var modeAccent: Color {
        if let feeling = vm.selectedFeeling {
            return feeling.accentColor
        }
        return vm.selectedMode.accentColor
    }

    var body: some View {
        VStack(spacing: Theme.spaceM) {
            pendingOff
            Spacer(minLength: 0)
            modeHero
            Spacer(minLength: 0)
            durationChoices
            StrengthCardView(vm: vm)
            startControl
                .padding(.top, Theme.spaceS)
        }
        .toolbar { toolbarContent }
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
                .presentationDetents([.large])
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showHistory) {
            SessionHistorySheet(
                sessions: vm.recentSessions,
                onCleared: vm.clearSessionHistory,
                onDelete: vm.deleteSession
            )
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showPrivacySettings) {
            SessionPrivacySettingsSheet(vm: vm)
        }
        .onAppear(perform: openFixtureSheet)
    }

    /// UI review only: open the sheet the launch fixture names.
    private func openFixtureSheet() {
        switch UIFixture.current?.sheet {
        case .settings: showPrivacySettings = true
        case .history: showHistory = true
        case .mode: showModeSheet = true
        case nil: break
        }
    }

    @ViewBuilder
    private var pendingOff: some View {
        if vm.pendingDeactivate {
            if reduceMotion {
                PendingOffBanner(isReady: vm.ble.isReady)
                    .transition(.opacity)
            } else {
                PendingOffBanner(isReady: vm.ble.isReady)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var modeHero: some View {
        Button {
            showModeSheet = true
        } label: {
            VStack(spacing: Theme.spaceS) {
                Image(systemName: vm.selectedFeeling?.icon ?? vm.selectedMode.icon)
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(modeAccent)
                    .symbolEffect(.breathe, options: .repeating, isActive: !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 120, height: 120)
                    .wellnessGlass(.regular.tint(modeAccent.opacity(0.25)), in: .circle)
                    .shadow(color: modeAccent.opacity(reduceMotion ? 0 : 0.35), radius: 24)
                    .padding(.bottom, Theme.spaceS)
                    .accessibilityHidden(true)
                Label(vm.sessionTitle, systemImage: "chevron.down")
                    .labelStyle(TrailingIconLabelStyle())
                    .font(Theme.heroMode)
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 0.85 : 0.7)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(vm.sessionSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.spaceL)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(vm.sessionTitle). \(vm.sessionSubtitle)")
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
        }
    }

    private var startControl: some View {
        VStack(spacing: Theme.spaceM) {
            ActionButtonView(vm: vm)

            Group {
                if vm.ble.isBluetoothOff {
                    Label(vm.startHint, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.accentAmber)
                        .padding(.horizontal, Theme.spaceL)
                        .frame(minHeight: 36)
                        .wellnessGlass(.regular.tint(Theme.accentAmber.opacity(0.15)), in: .capsule)
                } else {
                    Text(vm.startHint)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(minHeight: 36)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            StatusBarView(vm: vm, ownsGlass: false)
                .fixedSize()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("History", systemImage: "clock.arrow.circlepath") { showHistory = true }
                .accessibilityHint("Opens your private session log")
            Button("Settings", systemImage: "gearshape") { showPrivacySettings = true }
                .accessibilityHint("Tapper, Mindful Minutes, and alerts. On-device only.")
        }
    }

    @ViewBuilder
    private func advancedSegmented<T: Hashable & Identifiable>(
        title: String,
        selection: Binding<T>,
        options: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.sectionLabel)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    let selected = selection.wrappedValue.id == option.id
                    Button {
                        selection.wrappedValue = option
                    } label: {
                        Text(label(option))
                            .font(.subheadline.weight(.semibold))
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
    @State private var infoMode: StimulationMode?

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
                            selected: isFeelingSelected(state),
                            info: state.primaryMode
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
                        selected: vm.selectedMode == .custom && vm.selectedFeeling == nil,
                        info: .custom
                    ) {
                        vm.selectMode(.custom)
                        dismiss()
                    }
                } header: {
                    Text("Session")
                } footer: {
                    Text("Tap \(Image(systemName: "info.circle")) to learn how a session works. Wellness only. Not a medical treatment.")
                }
            }
            .tint(Theme.accentTeal)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $infoMode) { mode in
                ModeInfoSheet(mode: mode)
                    .presentationDetents([.medium, .large])
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
        info: StimulationMode,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
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
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    if selected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.accentTeal)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(subtitle)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button("About \(title)", systemImage: "info.circle") { infoMode = info }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
        }
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
                            Text("Research")
                                .font(Theme.sectionLabel)
                                .foregroundStyle(Theme.textTertiary)

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

/// Title first, then a small icon, so the mode name reads as a menu.
private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.title
            configuration.icon
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

import SwiftUI

/// Mode duration chips, plus a custom wheel.
struct DurationPresetRow: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showWheel = false

    private var presets: [Int] {
        vm.selectedMode.durationPresets.filter { $0 <= BLEConstants.maxSessionMinutes }
    }

    private var isCustomSelected: Bool {
        !SessionDurationOptions.isPreset(vm.timerMinutes, for: vm.selectedMode)
            || (presets.isEmpty && vm.selectedMode == .custom)
    }

    var body: some View {
        if !vm.isRunning, !vm.isPaused {
            VStack(alignment: .leading, spacing: 8) {
                Text("DURATION")
                    .font(Theme.sectionLabel)
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(1.5)
                    .accessibilityAddTraits(.isHeader)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { minutes in
                            presetChip(minutes)
                        }
                        customChip
                    }
                    VStack(spacing: 8) {
                        ForEach(presets, id: \.self) { minutes in
                            presetChip(minutes)
                        }
                        customChip
                    }
                }

                if vm.selectedMode == .sleep {
                    Text("Use before sleep — not after you’re already asleep.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Use before sleep, not during sleep")
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: vm.selectedMode)
            .transition(.opacity)
            .sheet(isPresented: $showWheel) {
                DurationWheelSheet(vm: vm)
                    .presentationDetents([.height(320), .medium])
                    .preferredColorScheme(.dark)
            }
        }
    }

    private func presetChip(_ minutes: Int) -> some View {
        chip(
            title: "\(minutes) min",
            selected: vm.timerMinutes == minutes,
            accessibilityLabel: "\(minutes) minutes"
        ) {
            vm.timerMinutes = min(minutes, BLEConstants.maxSessionMinutes)
        }
    }

    private var customChip: some View {
        chip(
            title: isCustomSelected ? "\(vm.timerMinutes) min" : "Custom…",
            selected: isCustomSelected,
            accessibilityLabel: isCustomSelected
                ? "Custom duration \(vm.timerMinutes) minutes"
                : "Custom duration",
            hint: "Opens duration picker"
        ) {
            vm.timerMinutes = SessionDurationOptions.snap(vm.timerMinutes, for: vm.selectedMode)
            showWheel = true
        }
    }

    @ViewBuilder
    private func chip(
        title: String,
        selected: Bool,
        accessibilityLabel: String,
        hint: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let base = Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .wellnessGlass(
            selected
                ? .regular.tint(vm.selectedMode.accentColor)
                : .regular.tint(vm.selectedMode.accentColor.opacity(0.12)),
            in: .capsule
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: selected
        )
        if let hint {
            base.accessibilityHint(hint)
        } else {
            base
        }
    }
}

// MARK: - Glass drum sheet

struct DurationWheelSheet: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var values: [Int] {
        SessionDurationOptions.wheelMinutes(for: vm.selectedMode)
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: {
                SessionDurationOptions.snap(vm.timerMinutes, for: vm.selectedMode)
            },
            set: { newValue in
                vm.timerMinutes = min(newValue, BLEConstants.maxSessionMinutes)
            }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.spaceM) {
                Text("\(vm.sessionTitle) · default \(vm.selectedMode.defaultDurationMinutes) min")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, Theme.spaceS)

                if reduceMotion {
                    // Stepper / menu — calmer than spinning drum for Reduce Motion
                    durationStepper
                        .padding(.vertical, Theme.spaceL)
                } else {
                    Picker("Session length", selection: minutesBinding) {
                        ForEach(values, id: \.self) { minutes in
                            Text("\(minutes) min")
                                .tag(minutes)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(maxHeight: 180)
                    .accessibilityLabel("Session length in minutes")
                    .sensoryFeedback(.selection, trigger: vm.timerMinutes)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.spaceL)
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Session length")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        vm.timerMinutes = SessionDurationOptions.snap(
                            vm.timerMinutes,
                            for: vm.selectedMode
                        )
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            vm.timerMinutes = SessionDurationOptions.snap(vm.timerMinutes, for: vm.selectedMode)
        }
    }

    private var durationStepper: some View {
        let snapped = SessionDurationOptions.snap(vm.timerMinutes, for: vm.selectedMode)
        let idx = values.firstIndex(of: snapped) ?? 0
        return HStack(spacing: 20) {
            Button {
                if idx > 0 { vm.timerMinutes = values[idx - 1] }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(idx <= 0)
            .accessibilityLabel("Decrease duration")

            Text("\(snapped) min")
                .font(.largeTitle.weight(.light).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .accessibilityLabel("\(snapped) minutes")

            Button {
                if idx < values.count - 1 { vm.timerMinutes = values[idx + 1] }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(idx >= values.count - 1)
            .accessibilityLabel("Increase duration")
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(
            reduceMotion ? .impact(weight: .light) : .selection,
            trigger: vm.timerMinutes
        )
    }
}

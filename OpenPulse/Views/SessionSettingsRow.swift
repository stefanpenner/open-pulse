import SwiftUI
import UIKit

/// Privacy + notifications sheet — Mindful Minutes and session end alerts.
/// Still idle opens this via gear; duration/intensity live on the main shell.
struct SessionPrivacySettingsSheet: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Optional local ticks (on-device synth — no streaming / accounts)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("TAPPER")
                            .font(Theme.sectionLabel)
                            .foregroundStyle(Theme.textTertiary)
                            .tracking(1.5)

                        Toggle(isOn: Binding(
                            get: { vm.ambientMusicEnabled },
                            set: { vm.setAmbientMusicEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Calming music")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Soft left-right tick-tock during sessions, like tappers. On-device only — no streaming or accounts. Off by default.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .accessibilityHint("Optional. Plays only while a session runs in the foreground.")

                        Toggle(isOn: Binding(
                            get: { vm.hapticTicksEnabled },
                            set: { vm.setHapticTicksEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Haptic taps")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("The phone taps on the same beat: a sharp tap for left, a soft tap for right. Hold the phone or keep it in a pocket. Off by default.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .accessibilityHint("Optional. Taps only while a session runs in the foreground.")

                        Toggle(isOn: Binding(
                            get: { vm.joyConEnabled },
                            set: { vm.setJoyConEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Use Joy-Con")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(vm.joyConEnabled
                                     ? vm.joyConStatus
                                     : "Hold one Joy-Con in each hand. Each taps its own side. Off by default.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .disabled(!vm.hapticTicksEnabled)
                        .accessibilityHint("Optional. Needs Haptic taps. Pair your Joy-Cons in Bluetooth settings first.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wellnessContentSurface(in: .rect(cornerRadius: Theme.cornerCard))

                    // Privacy-first Health integration (write-only Mindful Minutes)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("APPLE HEALTH")
                            .font(Theme.sectionLabel)
                            .foregroundStyle(Theme.textTertiary)
                            .tracking(1.5)

                        Toggle(isOn: Binding(
                            get: { vm.mindfulMinutesEnabled },
                            set: { vm.setMindfulMinutesEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Save Mindful Minutes")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Writes completed Breathe sessions to Health. Never reads your data.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .accessibilityHint("Optional. Open Pulse only writes mindful minutes when enabled.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wellnessContentSurface(in: .rect(cornerRadius: Theme.cornerCard))

                    // Opt-in session end alert (local only — no tracking)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("NOTIFICATIONS")
                            .font(Theme.sectionLabel)
                            .foregroundStyle(Theme.textTertiary)
                            .tracking(1.5)

                        Toggle(isOn: Binding(
                            get: { vm.sessionEndAlertsEnabled },
                            set: { vm.setSessionEndAlertsEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Session end alert")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Optional local reminder when a session finishes in the background. Never leaves your device.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .accessibilityHint("Optional. On-device notification only. No accounts or tracking.")

                        if vm.sessionEndAlertsEnabled, vm.sessionEndAlertsDenied {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(SessionEndNotifier.deniedHelpText())
                                    .font(.caption2)
                                    .foregroundStyle(Theme.accentAmber)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .accessibilityLabel(SessionEndNotifier.deniedHelpText())
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    Link("Open Settings", destination: url)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Theme.accentTeal)
                                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                        .contentShape(Rectangle())
                                        .accessibilityLabel("Open Settings")
                                        .accessibilityHint("Opens iOS Settings for Open Pulse notifications")
                                }
                            }
                        }

                        Toggle(isOn: Binding(
                            get: { vm.sessionRemindersEnabled },
                            set: { vm.setSessionRemindersEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Session reminders")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Optional morning and evening nudge. Never tracks streaks or shames you.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .accessibilityHint("Optional local reminders only. No accounts or tracking.")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .wellnessContentSurface(in: .rect(cornerRadius: Theme.cornerCard))

                    VStack(spacing: 6) {
                        Text(PrivacyTrustCopy.nothingLeavesPhone)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .accessibilityAddTraits(.isHeader)
                        Text(PrivacyTrustCopy.privateByDesign)
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)

                    DeviceInfoFooter(ble: vm.ble)
                }
                .padding(16)
            }
            .background(Theme.backgroundGradient.ignoresSafeArea())
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { vm.refreshSessionEndAlertAuthorization() }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

/// Quiet footer: device name and firmware, when the device has told us.
private struct DeviceInfoFooter: View {
    @ObservedObject var ble: DeviceState

    var body: some View {
        if let text = DeviceInfoParser.footer(name: ble.deviceName, firmware: ble.firmwareVersion) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("Device " + text)
        }
    }
}

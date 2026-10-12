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
                    // Optional local ambience (bundled pad — no streaming / accounts)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SOUND")
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
                                Text("Soft ambient pad during sessions. On-device only — no streaming or accounts. Off by default.")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(Theme.accentTeal)
                        .accessibilityHint("Optional. Plays a bundled ambient loop only while a session is active in the foreground.")
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

import SwiftUI
import UIKit

/// Settings sheet: tapper, Apple Health, and notifications. All on-device.
struct SessionPrivacySettingsSheet: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tapper") {
                    settingToggle(
                        "Calming music",
                        detail: "Soft left-right tick-tock during sessions, like tappers. On-device only. Off by default.",
                        isOn: Binding(get: { vm.ambientMusicEnabled }, set: { vm.setAmbientMusicEnabled($0) }),
                        hint: "Optional. Plays only while a session runs in the foreground."
                    )
                    settingToggle(
                        "Haptic taps",
                        detail: "A sharp tap for left, a soft tap for right. Hold the phone or keep it in a pocket. Off by default.",
                        isOn: Binding(get: { vm.hapticTicksEnabled }, set: { vm.setHapticTicksEnabled($0) }),
                        hint: "Optional. Taps only while a session runs in the foreground."
                    )
                }

                Section("Apple Health") {
                    settingToggle(
                        "Save Mindful Minutes",
                        detail: "Writes completed Breathe sessions to Health. Never reads your data.",
                        isOn: Binding(get: { vm.mindfulMinutesEnabled }, set: { vm.setMindfulMinutesEnabled($0) }),
                        hint: "Optional. Open Pulse only writes mindful minutes when enabled."
                    )
                }

                Section {
                    settingToggle(
                        "Session end alert",
                        detail: "A local alert when a session ends in the background.",
                        isOn: Binding(get: { vm.sessionEndAlertsEnabled }, set: { vm.setSessionEndAlertsEnabled($0) }),
                        hint: "Optional. On-device notification only."
                    )
                    if vm.sessionEndAlertsEnabled, vm.sessionEndAlertsDenied {
                        deniedHelp
                    }
                    settingToggle(
                        "Session reminders",
                        detail: "A morning and evening nudge. No streak pressure.",
                        isOn: Binding(get: { vm.sessionRemindersEnabled }, set: { vm.setSessionRemindersEnabled($0) }),
                        hint: "Optional local reminders only."
                    )
                } header: {
                    Text("Notifications")
                } footer: {
                    VStack(spacing: 6) {
                        Text(PrivacyTrustCopy.nothingLeavesPhone).fontWeight(.semibold)
                        Text(PrivacyTrustCopy.privateByDesign)
                        DeviceInfoFooter(ble: vm.ble)
                    }
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.spaceL)
                }
            }
            .tint(Theme.accentTeal)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { vm.refreshSessionEndAlertAuthorization() }
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }

    private func settingToggle(
        _ title: String, detail: String, isOn: Binding<Bool>, hint: String
    ) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
            Text(detail)
        }
        .accessibilityHint(hint)
    }

    @ViewBuilder
    private var deniedHelp: some View {
        Text(SessionEndNotifier.deniedHelpText())
            .font(.footnote)
            .foregroundStyle(Theme.accentAmber)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Link("Open Settings", destination: url)
                .accessibilityHint("Opens iOS Settings for Open Pulse notifications")
        }
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

import SwiftUI

/// Avoids ternary on blurReplace (not on AnyTransition).
private struct ConnectionChipTransition: ViewModifier {
    let reduceMotion: Bool
    func body(content: Content) -> some View {
        if reduceMotion {
            content.transition(.opacity)
        } else {
            content.transition(.blurReplace)
        }
    }
}

struct StatusBarView: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// When true, connection empty state owns the link story — chip would double VO/copy.
    var hideConnectionChip: Bool = false

    private var showsBattery: Bool { vm.ble.batteryPercentage != nil }
    private var showsConnection: Bool { !hideConnectionChip }
    private var isVisible: Bool { showsConnection || showsBattery }

    var body: some View {
        Group {
            if isVisible {
                HStack(spacing: 12) {
                    if showsConnection {
                        connectionControl
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.3),
                                value: vm.ble.isConnected
                            )
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.3),
                                value: vm.ble.isReady
                            )
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.3),
                                value: vm.ble.isBluetoothOff
                            )
                    }

                    Spacer(minLength: 0)

                    if let pct = vm.ble.batteryPercentage {
                        batteryInfo(pct)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .wellnessGlass(.regular, in: .capsule)
                .sensoryFeedback(trigger: vm.ble.isReady) { old, new in
                    guard !old && new else { return nil }
                    return reduceMotion ? .impact(weight: .light) : .success
                }
                .sensoryFeedback(trigger: vm.ble.isConnected) { old, new in
                    guard old && !new else { return nil }
                    return reduceMotion ? .impact(weight: .light) : .warning
                }
            }
        }
    }

    @ViewBuilder
    private var connectionControl: some View {
        // Bluetooth off wins over stale Connected flags
        Group {
            if vm.ble.isBluetoothOff {
                connectionChip(
                    icon: "antenna.radiowaves.left.and.right.slash",
                    text: ConnectionPresentation.chipText(
                        isBluetoothOff: true, isConnected: false, isReady: false
                    ),
                    color: Theme.disconnectedRed,
                    showProgress: false,
                    showDot: false
                )
            } else if vm.ble.isConnected && vm.ble.isReady {
                connectionChip(
                    icon: nil,
                    text: ConnectionPresentation.chipText(
                        isBluetoothOff: false, isConnected: true, isReady: true
                    ),
                    color: Theme.textSecondary,
                    showProgress: false,
                    showDot: true
                )
            } else if vm.ble.isConnected {
                connectionChip(
                    icon: nil,
                    text: ConnectionPresentation.chipText(
                        isBluetoothOff: false, isConnected: true, isReady: false
                    ),
                    color: Theme.connectedGreen,
                    showProgress: true,
                    showDot: false
                )
            } else {
                connectionChip(
                    icon: nil,
                    text: ConnectionPresentation.chipText(
                        isBluetoothOff: false, isConnected: false, isReady: false
                    ),
                    color: Theme.accentBlue,
                    showProgress: true,
                    showDot: false
                )
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ConnectionPresentation.accessibilityLabel(
            isBluetoothOff: vm.ble.isBluetoothOff,
            isConnected: vm.ble.isConnected,
            isReady: vm.ble.isReady
        ))
    }

    @ViewBuilder
    private func connectionChip(
        icon: String?,
        text: String,
        color: Color,
        showProgress: Bool,
        showDot: Bool
    ) -> some View {
        HStack(spacing: 6) {
            if showDot {
                Circle()
                    .fill(Theme.connectedGreen)
                    .frame(width: 7, height: 7)
                    .shadow(
                        color: reduceMotion ? .clear : Theme.connectedGreen.opacity(0.6),
                        radius: 3
                    )
                    .accessibilityHidden(true)
            }
            if showProgress {
                ProgressView()
                    .scaleEffect(0.6)
                    .tint(color)
                    .accessibilityHidden(true)
            }
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(color)
        }
        .modifier(ConnectionChipTransition(reduceMotion: reduceMotion))
    }

    private func batteryInfo(_ pct: Int) -> some View {
        let charging = vm.ble.isCharging
        let confirmed = vm.ble.batterySampleConfirmed
        let low = BatteryPresentation.isLow(percent: pct, isCharging: charging)
        let color = low ? Theme.disconnectedRed : Theme.textSecondary

        return HStack(spacing: 4) {
            Image(systemName: BatteryPresentation.iconName(percent: pct))
                .font(.caption2)
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: low && !reduceMotion)
                .accessibilityHidden(true)

            Text(BatteryPresentation.chipText(percent: pct, sampleConfirmed: confirmed))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(color)
                .accessibilityHidden(true)

            if charging == true {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accentTeal)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            BatteryPresentation.accessibilityLabel(
                percent: pct, isCharging: charging, isLow: low, sampleConfirmed: confirmed
            )
        )
    }
}

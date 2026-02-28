import SwiftUI

struct StatusBarView: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        HStack(spacing: 12) {
            connectionControl

            Spacer()

            if let pct = vm.ble.batteryPercentage {
                batteryInfo(pct)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    @ViewBuilder
    private var connectionControl: some View {
        if vm.ble.isScanning {
            Button { vm.stopScan() } label: {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(Theme.accentBlue)

                    Text("Scanning…")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accentBlue)

                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .buttonStyle(.plain)
        } else if vm.ble.isConnected {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.connectedGreen)
                    .frame(width: 7, height: 7)
                    .shadow(color: Theme.connectedGreen.opacity(0.6), radius: 3)

                Text("Connected")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            Button { vm.scan() } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.disconnectedRed)
                        .frame(width: 7, height: 7)
                        .shadow(color: Theme.disconnectedRed.opacity(0.6), radius: 3)

                    Text("Tap to Connect")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func batteryInfo(_ pct: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon(pct))
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            if let v = vm.ble.batteryVoltage {
                Text(String(format: "%.2fV", v))
                    .font(.caption2.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text("\(pct)%")
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textSecondary)

            if let charging = vm.ble.isCharging, charging {
                Image(systemName: "bolt.fill")
                    .font(.caption2)
                    .foregroundStyle(Theme.accentTeal)
            }
        }
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 0..<13: "battery.0percent"
        case 13..<38: "battery.25percent"
        case 38..<63: "battery.50percent"
        case 63..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }
}

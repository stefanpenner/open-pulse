import SwiftUI

struct StatusBarView: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        HStack(spacing: 16) {
            // Connection
            HStack(spacing: 6) {
                Circle()
                    .fill(vm.ble.isConnected ? Theme.connectedGreen : Theme.disconnectedRed)
                    .frame(width: 8, height: 8)
                    .shadow(color: vm.ble.isConnected ? Theme.connectedGreen.opacity(0.6) : Theme.disconnectedRed.opacity(0.6), radius: 4)

                Text(vm.ble.isConnected ? "Connected" : "Disconnected")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            // Battery
            if let pct = vm.ble.batteryPercentage {
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

                    // Charging
                    if let charging = vm.ble.isCharging, charging {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.accentTeal)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
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

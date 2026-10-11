import SwiftUI

/// Industry-standard empty state when the device is not ready.
/// Surfaces the real blocker instead of only a tiny status chip.
struct ConnectionEmptyState: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        ConnectionPresentation.emptyTitle(
            isBluetoothOff: vm.ble.isBluetoothOff,
            isConnected: vm.ble.isConnected,
            isReady: vm.ble.isReady
        )
    }

    private var detail: String {
        ConnectionPresentation.emptyDetail(
            isBluetoothOff: vm.ble.isBluetoothOff,
            isConnected: vm.ble.isConnected,
            isReady: vm.ble.isReady,
            batteryPercent: vm.ble.batteryPercentage,
            isCharging: vm.ble.isCharging,
            batterySampleConfirmed: vm.ble.batterySampleConfirmed
        )
    }

    private var icon: String {
        if vm.ble.isBluetoothOff {
            return "antenna.radiowaves.left.and.right.slash"
        }
        return "dot.radiowaves.left.and.right"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(
                    vm.ble.isBluetoothOff ? Theme.disconnectedRed : Theme.accentBlue
                )
                .symbolEffect(
                    .variableColor.iterative,
                    isActive: !reduceMotion && !vm.ble.isBluetoothOff && !vm.ble.isReady
                )
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.85)

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.85)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        // Content surface — glass reserved for controls
        .wellnessContentSurface(in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}

import SwiftUI

struct ActionButtonView: View {
    @ObservedObject var vm: SessionViewModel

    var body: some View {
        if vm.isRunning || vm.isPaused {
            HStack(spacing: 12) {
                Button(action: { vm.isPaused ? vm.resume() : vm.pause() }) {
                    HStack(spacing: 8) {
                        Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                            .font(.callout)
                        Text(vm.isPaused ? "Resume" : "Pause")
                            .font(Theme.buttonLabel)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .glassEffect(
                    .regular.tint(vm.isPaused ? Theme.accentTeal : Theme.accentAmber).interactive(),
                    in: .capsule
                )
                .disabled(vm.isPaused && !vm.ble.isConnected)

                Button(action: { vm.stop() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.callout)
                        Text("Stop")
                            .font(Theme.buttonLabel)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .glassEffect(.regular.tint(Theme.accentRed).interactive(), in: .capsule)
            }
        } else {
            Button(action: handleTap) {
                HStack(spacing: 10) {
                    if vm.ble.isScanning {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(buttonLabel)
                        .font(Theme.buttonLabel)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .glassEffect(.regular.tint(buttonTint).interactive(), in: .capsule)
            .disabled(vm.ble.isScanning)
            .opacity(vm.ble.isScanning ? 0.7 : 1)
        }
    }

    private var buttonLabel: String {
        if !vm.ble.isConnected {
            return vm.ble.isScanning ? "Scanning..." : "Scan for Device"
        }
        return "Start"
    }

    private var buttonTint: Color {
        if !vm.ble.isConnected { return Theme.accentBlue }
        return Theme.accentTeal
    }

    private func handleTap() {
        if !vm.ble.isConnected {
            vm.scan()
        } else {
            vm.start()
        }
    }
}

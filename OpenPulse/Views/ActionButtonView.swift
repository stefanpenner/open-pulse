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
                    .frame(height: 50)
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
                    .frame(height: 50)
                }
                .glassEffect(.regular.tint(Theme.accentRed).interactive(), in: .capsule)
            }
        } else {
            Button(action: { vm.start() }) {
                Text("Start")
                    .font(Theme.buttonLabel)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .glassEffect(.regular.tint(Theme.accentTeal).interactive(), in: .capsule)
            .disabled(!vm.ble.isReady)
            .opacity(vm.ble.isReady ? 1 : 0.4)
        }
    }
}

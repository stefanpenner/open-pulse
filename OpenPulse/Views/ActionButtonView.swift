import SwiftUI

struct ActionButtonView: View {
    @ObservedObject var vm: SessionViewModel

    private var sessionState: String {
        if vm.isRunning { return "running" }
        if vm.isPaused { return "paused" }
        return "idle"
    }

    var body: some View {
        Group {
            if vm.isRunning || vm.isPaused {
                HStack(spacing: 16) {
                    Button(action: { vm.isPaused ? vm.resume() : vm.pause() }) {
                        Image(systemName: vm.isPaused ? "play.fill" : "pause.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(vm.isPaused && !vm.ble.isConnected)

                    Button(action: { vm.stop() }) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                }
            } else {
                Button(action: { vm.start() }) {
                    HStack(spacing: 6) {
                        Text("Start")
                            .font(Theme.buttonLabel)
                        Text("\(vm.timerMinutes) min")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .glassEffect(.regular.tint(Theme.accentTeal).interactive(), in: .capsule)
            }
        }
        .sensoryFeedback(trigger: sessionState) { old, new in
            switch (old, new) {
            case ("idle", "running"): .impact(weight: .medium)
            case ("running", "paused"): .impact(weight: .light)
            case ("paused", "running"): .impact(weight: .medium)
            case (_, "idle"): .impact(weight: .heavy)
            default: nil
            }
        }
    }
}

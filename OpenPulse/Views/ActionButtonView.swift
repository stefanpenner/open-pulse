import SwiftUI

struct ActionButtonView: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sessionState: String {
        if vm.isRunning { return "running" }
        if vm.isPaused { return "paused" }
        return "idle"
    }

    private var controlSize: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 56 : 50
    }

    var body: some View {
        Group {
            if vm.isRunning || vm.isPaused {
                HStack(spacing: 12) {
                    Button(action: { vm.isPaused ? vm.resume() : vm.pause() }) {
                        Label(vm.isPaused ? "Resume" : "Pause", systemImage: vm.isPaused ? "play.fill" : "pause.fill")
                            .font(Theme.buttonLabel)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: controlSize)
                            .contentShape(Capsule())
                    }
                    .opacity(vm.isPaused && !vm.canResume ? 0.55 : 1)
                    .wellnessGlass(.regular.tint(Theme.accentTeal).interactive(), in: .capsule)
                    .disabled(vm.isPaused && !vm.canResume)
                    .accessibilityLabel(vm.isPaused ? "Resume session" : "Pause session")
                    .accessibilityHint(vm.isPaused && !vm.canResume ? "Waiting for device connection" : "")

                    Button(action: { vm.stop() }) {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: controlSize, height: controlSize)
                            .contentShape(Circle())
                    }
                    .wellnessGlass(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Stop session")
                    .accessibilityHint("Ends the session and turns the device off")
                }
            } else {
                VStack(spacing: 8) {
                Button(action: { vm.start() }) {
                    Group {
                        if vm.canStart {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(spacing: 2) {
                                    Text("Start")
                                        .font(Theme.buttonLabel)
                                    Text("\(vm.timerMinutes) min")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            } else {
                                HStack(spacing: 6) {
                                    Text("Start")
                                        .font(Theme.buttonLabel)
                                    Text("\(vm.timerMinutes) min")
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                        } else {
                            Text(vm.startButtonTitle)
                                .font(Theme.buttonLabel)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: controlSize)
                    .padding(.horizontal, 16)
                    .contentShape(Capsule())
                }
                .disabled(!vm.canStart)
                .opacity(vm.canStart ? 1 : 0.55)
                .wellnessGlass(
                    .regular.tint(vm.canStart ? Theme.accentTeal : Theme.textTertiary).interactive(),
                    in: .capsule
                )
                .accessibilityLabel(vm.canStart ? "Start \(vm.timerMinutes) minute session" : (vm.startBlockedReason ?? "Start unavailable"))
                .accessibilityHint(
                    vm.canStart
                        ? "Begins the \(vm.sessionTitle) session"
                        : (vm.startBlockedReason ?? "Connect your device to start")
                )

                if vm.canStart, let hint = BatteryPresentation.startHint(
                    percent: vm.ble.batteryPercentage, isCharging: vm.ble.isCharging
                ) {
                    Label(hint, systemImage: "battery.25percent")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accentAmber)
                }
                }
            }
        }
        .sensoryFeedback(trigger: sessionState) { old, new in
            // Reduce Motion: light impacts only (Still control language)
            if reduceMotion {
                switch (old, new) {
                case ("idle", "running"), ("paused", "running"), ("running", "paused"), (_, "idle"):
                    return .impact(weight: .light)
                default:
                    return nil
                }
            }
            switch (old, new) {
            case ("idle", "running"): return .impact(weight: .medium)
            case ("running", "paused"): return .impact(weight: .light)
            case ("paused", "running"): return .impact(weight: .medium)
            case (_, "idle"): return .impact(weight: .heavy)
            default: return nil
            }
        }
    }
}

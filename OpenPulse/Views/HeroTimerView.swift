import SwiftUI

struct HeroTimerView: View {
    @ObservedObject var vm: SessionViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isA11yType: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(spacing: 8) {
            // Mode status — same honesty as Live Activity (pending / offline / phase)
            let status = vm.sessionStatusText
            let showPendingOff = PendingOffPresentation.shouldShowBanner(
                isRunning: vm.isRunning,
                pendingDeviceOff: vm.pendingDeactivate
            )
            if vm.isPaused || showPendingOff || !vm.ble.isReady || !vm.modeStatus.isEmpty {
                Text(status)
                    .font(isA11yType ? .body.weight(.medium) : .subheadline.weight(.medium))
                    .foregroundStyle(
                        (vm.isPaused || showPendingOff)
                            ? Theme.accentAmber
                            : vm.selectedMode.accentColor.opacity(0.8)
                    )
                    .minimumScaleFactor(0.8)
                    .lineLimit(isA11yType ? 3 : 2)
                    .multilineTextAlignment(.center)
                    .contentTransition(reduceMotion ? .identity : .opacity)
                    .animation(reduceMotion ? nil : .default, value: status)
                    .accessibilityLabel(status)
            }

            // Progress bar — time lives on LiveTimerStepper (single clock hierarchy)
            GeometryReader { geo in
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .frame(height: isA11yType ? 6 : 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(vm.selectedMode.accentColor.opacity(0.9))
                            .shadow(
                                color: reduceMotion
                                    ? .clear
                                    : vm.selectedMode.accentColor.opacity(0.28),
                                radius: 4
                            )
                            .frame(width: geo.size.width * vm.progress)
                            .animation(
                                reduceMotion ? nil : .linear(duration: 1),
                                value: vm.progress
                            )
                    }
            }
            .frame(height: isA11yType ? 6 : 4)
            .padding(.horizontal, 8)
            .accessibilityElement(children: .ignore)
            // Time lives on LiveTimerStepper — progress reports percent only (no dual clock VO)
            .accessibilityLabel("Session progress")
            .accessibilityValue("\(Int((vm.progress * 100).rounded())) percent complete")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        // Solid content field — glass reserved for ± / Start controls
        .wellnessContentSurface(
            in: .rect(cornerRadius: Theme.cornerCard),
            color: Theme.contentHeroFill
        )
    }
}

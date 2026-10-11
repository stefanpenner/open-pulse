import SwiftUI

/// First-run intro — short, wellness-framed, industry-standard pattern.
struct OnboardingView: View {
    var onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 20) {
                Image(systemName: "waveform.path.ecg")
                    .font(.largeTitle.weight(.light))
                    .imageScale(.large)
                    .foregroundStyle(Theme.accentTeal)
                    .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
                    .accessibilityHidden(true)

                Text("Open Pulse")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("Private control for your Pulsetto.\nNo accounts. No tracking.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open Pulse. Private control for your Pulsetto. No accounts. No tracking.")

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 16) {
                onboardingRow(
                    icon: "heart.fill",
                    title: "Choose a session",
                    detail: "Stress, Breathe, Sleep, Focus, or Ease — plus Custom."
                )
                onboardingRow(
                    icon: "slider.horizontal.3",
                    title: "Set time & intensity",
                    detail: SessionDurationOptions.softStartComfortHint
                )
                onboardingRow(
                    icon: "lock.shield",
                    title: "Stay private",
                    detail: "Mindful Minutes and end alerts stay opt-in. Open Privacy anytime from Still."
                )
                onboardingRow(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Connect your device",
                    detail: "Pair over Bluetooth, then Start. Private — no accounts."
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Content checklist — glass reserved for Continue control
            .wellnessContentSurface(in: .rect(cornerRadius: 20))

            Spacer(minLength: 24)

            Text("For general wellness only — not a medical treatment.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 12)
                .accessibilityLabel("For general wellness only, not a medical treatment")

            Button(action: onContinue) {
                Text("Continue")
                    .font(Theme.buttonLabel)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .wellnessGlass(.regular.tint(Theme.accentTeal).interactive(), in: .capsule)
            .accessibilityLabel("Continue to app")
        }
        .padding(24)
        .background(Theme.backgroundGradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func onboardingRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.accentTeal)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OnboardingView(onContinue: {})
}

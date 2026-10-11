import SwiftUI

/// Shown while a durable hardware-off is waiting on the link (or retrying).
/// Used on idle and paused surfaces so incomplete off is never silent.
struct PendingOffBanner: View {
    let isReady: Bool
    /// When true, copy reflects pause vs idle stop.
    var isPaused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "power")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.disconnectedRed)
                .symbolEffect(.pulse, isActive: !reduceMotion)

            VStack(alignment: .leading, spacing: 2) {
                Text(isPaused ? "Paused · stopping device" : "Turning device off")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(isReady
                     ? "Sending stop to hardware…"
                     : "Will stop as soon as the device reconnects.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Status content (not control glass) — solid elevated for Reduce Transparency / hierarchy
        .wellnessContentSurface(in: .rect(cornerRadius: 14), color: Theme.solidSurfaceElevated)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.disconnectedRed.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let head = isPaused ? "Paused. Turning device off." : "Turning device off."
        let tail = isReady
            ? "Sending stop to hardware."
            : "Will stop when the device reconnects."
        return "\(head) \(tail)"
    }
}

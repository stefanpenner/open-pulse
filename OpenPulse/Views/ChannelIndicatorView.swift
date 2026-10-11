import SwiftUI

struct ChannelIndicatorView: View {
    let activeChannel: ActiveChannel
    let accentColor: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            // Left neck
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(leftActive ? accentColor : Theme.textTertiary)
                .opacity(leftActive ? 1.0 : 0.3)

            Text("L")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(leftActive ? accentColor : Theme.textTertiary)
                .opacity(leftActive ? 1.0 : 0.3)

            Text("R")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(rightActive ? accentColor : Theme.textTertiary)
                .opacity(rightActive ? 1.0 : 0.3)

            // Right neck
            Image(systemName: "bolt.fill")
                .font(.caption)
                .foregroundStyle(rightActive ? accentColor : Theme.textTertiary)
                .opacity(rightActive ? 1.0 : 0.3)
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.3),
            value: activeChannel
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var leftActive: Bool {
        activeChannel == .bilateral || activeChannel == .left
    }

    private var rightActive: Bool {
        activeChannel == .bilateral || activeChannel == .right
    }

    private var accessibilitySummary: String {
        switch activeChannel {
        case .bilateral: "Both channels active"
        case .left: "Left channel active"
        case .right: "Right channel active"
        case .off: "Channels off"
        }
    }
}

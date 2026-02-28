import SwiftUI

struct ChannelIndicatorView: View {
    let activeChannel: ActiveChannel
    let accentColor: Color

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
        .animation(.easeInOut(duration: 0.3), value: activeChannel)
    }

    private var leftActive: Bool {
        activeChannel == .bilateral || activeChannel == .left
    }

    private var rightActive: Bool {
        activeChannel == .bilateral || activeChannel == .right
    }
}

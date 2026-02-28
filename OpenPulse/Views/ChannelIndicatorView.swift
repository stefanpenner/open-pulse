import SwiftUI

struct ChannelIndicatorView: View {
    let activeChannel: ActiveChannel
    let accentColor: Color

    var body: some View {
        HStack(spacing: 10) {
            // Left ear
            Image(systemName: "ear.fill")
                .font(.body)
                .foregroundStyle(leftActive ? accentColor : Theme.textTertiary)
                .opacity(leftActive ? 1.0 : 0.3)

            // Right ear (mirrored)
            Image(systemName: "ear.fill")
                .font(.body)
                .scaleEffect(x: -1, y: 1)
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

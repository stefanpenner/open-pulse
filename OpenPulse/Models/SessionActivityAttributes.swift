import ActivityKit
import Foundation

/// Shared Activity attributes for app + widget extension (must match exactly).
struct SessionActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        var remainingSeconds: Int
        /// Mutable total so mid-session ±time keeps progress correct.
        var totalSeconds: Int
        var isPaused: Bool
        var statusText: String
        var stimulationActive: Bool
        /// Sticky hardware-off still in flight (pause / incomplete stop).
        var pendingDeviceOff: Bool
        /// Wall end for system countdown (nil when paused / frozen).
        var endsAt: Date?
        /// BLE ready — resume control honesty on Lock Screen / Island.
        var isLinkReady: Bool
    }

    var modeRaw: String
    var modeName: String
    /// Initial planned total (legacy fallback; prefer ContentState.totalSeconds).
    var totalSeconds: Int
}

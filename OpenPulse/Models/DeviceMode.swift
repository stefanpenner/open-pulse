import Foundation

/// Stim state the pack reports in an unprompted "mode:<0|A|C|D>" notice.
/// Pure. Other text ("Batt:", "BR:") is not a mode report.
enum DeviceMode: Equatable, Sendable {
    case off, left, right, bilateral

    /// Parse a whole notice. Returns nil for anything but a known "mode:" code.
    init?(report text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("mode:") else { return nil }
        switch trimmed.dropFirst("mode:".count).trimmingCharacters(in: .whitespaces) {
        case "0": self = .off
        case "A": self = .left
        case "C": self = .right
        case "D": self = .bilateral
        default: return nil
        }
    }

    init(channel: ActiveChannel) {
        switch channel {
        case .off: self = .off
        case .left: self = .left
        case .right: self = .right
        case .bilateral: self = .bilateral
        }
    }
}

/// What the app does with a mode report. Policy: specs/PendingOff.tla (DeviceReport, HostReport).
enum ModeReportAction: Equatable {
    case ignore
    /// Idle or paused, pack is on: arm pending off and send off.
    case armOff
    /// Idle or paused, pack is off, nothing in flight: clear pending off.
    case clearPendingOff
    /// Running, pack differs from the program: reprogram on the next tick.
    case reassert

    /// - Parameter quiet: no write is in flight or queued.
    static func decide(
        report: DeviceMode,
        isRunning: Bool,
        expected: DeviceMode,
        pendingOff: Bool,
        quiet: Bool
    ) -> ModeReportAction {
        if isRunning {
            return quiet && report != expected ? .reassert : .ignore
        }
        if report != .off { return .armOff }
        return quiet && pendingOff ? .clearPendingOff : .ignore
    }
}

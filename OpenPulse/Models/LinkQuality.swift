import Foundation

/// Bluetooth signal level from RSSI. Pure. The widget does not use it.
enum LinkQuality: Equatable, Sendable {
    case good, fair, weak

    /// Seconds between RSSI reads while the link is ready.
    static let pollSeconds: TimeInterval = 3

    static func level(rssi: Int) -> LinkQuality {
        switch rssi {
        case (-70)...: .good
        case (-85)...: .fair
        default: .weak
        }
    }

    /// Fill for the `cellularbars` symbol.
    var bars: Double {
        switch self {
        case .good: 1
        case .fair: 0.66
        case .weak: 0.33
        }
    }

    var label: String {
        switch self {
        case .good: "Strong signal"
        case .fair: "OK signal"
        case .weak: "Weak signal"
        }
    }

    var hint: String? {
        self == .weak ? "Keep your phone near the Pulsetto." : nil
    }
}

/// Median of the last few RSSI reads, so one bad read does not flip the level.
struct LinkQualityMeter {
    static let window = 5
    /// CoreBluetooth sends 127 when it has no reading.
    static let unavailable = 127

    private var samples: [Int] = []

    mutating func add(rssi: Int) -> LinkQuality? {
        if rssi != Self.unavailable {
            samples.append(rssi)
            if samples.count > Self.window { samples.removeFirst() }
        }
        guard !samples.isEmpty else { return nil }
        return LinkQuality.level(rssi: samples.sorted()[samples.count / 2])
    }

    mutating func reset() {
        samples.removeAll()
    }
}

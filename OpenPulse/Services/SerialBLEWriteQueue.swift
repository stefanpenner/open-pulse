import Foundation

/// Pure serial withResponse write model (aligned with `specs/BLEWriteQueue.tla`).
///
/// - `waiting` holds not-yet-started commands only
/// - at most one in-flight
/// - deactivate purges non-off waiting and sits at head
/// - `cancelProgramWrites` never abandons in-flight (single-flight CB rule)
struct SerialBLEWriteQueue: Equatable, Sendable {
    private(set) var waiting: [String] = []
    private(set) var inFlight: String?

    var hasPending: Bool { inFlight != nil || !waiting.isEmpty }

    var hasPendingProgramWrites: Bool {
        if let inFlight, !Self.isStatusQuery(inFlight), !Self.isDeactivate(inFlight) {
            return true
        }
        return waiting.contains { !Self.isStatusQuery($0) && !Self.isDeactivate($0) }
    }

    static func isDeactivate(_ command: String) -> Bool {
        // Match SessionSafety.isDeactivateCommand — exact off only
        SessionSafety.isDeactivateCommand(command)
    }

    static func isStatusQuery(_ command: String) -> Bool {
        command == BLEConstants.batteryQueryCommand
            || command == BLEConstants.chargingQueryCommand
    }

    /// Enqueue a command. Deactivate jumps the queue and drops program traffic waiting.
    mutating func enqueue(_ command: String) {
        if Self.isDeactivate(command) {
            waiting.removeAll { !Self.isDeactivate($0) }
            if waiting.first != command {
                waiting.insert(command, at: 0)
            }
        } else {
            waiting.append(command)
        }
    }

    /// Drop waiting program/status cmds (keep deactivates). Does **not** clear in-flight.
    mutating func cancelProgramWrites() {
        waiting.removeAll { !Self.isDeactivate($0) }
    }

    /// Start next write when idle. Returns command to hand to CoreBluetooth, or nil.
    mutating func beginWrite() -> String? {
        guard inFlight == nil, let head = waiting.first else { return nil }
        waiting.removeFirst()
        inFlight = head
        return head
    }

    /// Complete current write (success or fail). Returns finished command.
    @discardableResult
    mutating func finishWrite() -> String? {
        let cmd = inFlight
        inFlight = nil
        return cmd
    }

    /// Link loss / cleanup — drop everything including in-flight bookkeeping.
    mutating func clear() {
        waiting.removeAll()
        inFlight = nil
    }
}

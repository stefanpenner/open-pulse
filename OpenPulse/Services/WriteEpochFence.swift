import Foundation

/// Guards withResponse completions against stale callbacks after cleanup/reconnect.
///
/// - `beginWrite()` stamps the in-flight generation
/// - `invalidate()` bumps generation so late `didWrite` is ignored
/// - `acceptsCompletion()` is true only for the current in-flight stamp
struct WriteEpochFence: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var inFlightStamp: UInt64 = 0

    /// Call when starting a CB withResponse write.
    /// The returned stamp is the only identity a later didWrite may present.
    @discardableResult
    mutating func beginWrite() -> UInt64 {
        generation &+= 1
        inFlightStamp = generation
        return inFlightStamp
    }

    /// Call on link cleanup / queue clear — abandons any in-flight identity.
    mutating func invalidate() {
        generation &+= 1
        inFlightStamp = 0
    }

    /// Whether a didWrite callback should finish the current in-flight command.
    var acceptsCompletion: Bool {
        inFlightStamp != 0 && inFlightStamp == generation
    }

    /// Stamp of the current in-flight write. Zero after invalidate or finish.
    var issuedStamp: UInt64 { inFlightStamp }

    /// True only when this callback's stamp is the current in-flight write.
    /// A stamp from before invalidate must not finish a later write.
    func accepts(_ stamp: UInt64) -> Bool {
        stamp != 0 && stamp == inFlightStamp
    }

    /// Call after accepting a completion (success or fail).
    mutating func finish() {
        inFlightStamp = 0
    }
}

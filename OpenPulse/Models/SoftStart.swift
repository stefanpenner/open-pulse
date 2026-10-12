import Foundation

/// Pure BLE write policy after user changes intensity mid-session.
/// Avoids base-then-wave double writes when the engine tick already reasserted strength.
enum StrengthWritePolicy {
    /// True if any command is a strength level line (`"1\n"`…`"9\n"`).
    /// Deactivate `"0\n"` is **not** strength — must not skip absolute base write.
    static func containsStrengthCommand(_ commands: [String]) -> Bool {
        commands.contains { cmd in
            guard let n = Int(cmd.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return false
            }
            return (1...9).contains(n)
        }
    }

    /// Commands to enqueue after setStrength + engine tick.
    /// If the tick already set strength, use the tick only.
    /// Otherwise send channel or off, then the user base.
    static func bleCommands(userBase: Int, tickCommands: [String]) -> [String] {
        if containsStrengthCommand(tickCommands) {
            return tickCommands
        }
        return tickCommands + [BLEConstants.strengthCommand(userBase)]
    }
}

/// Gradual intensity ease-in for continuous modes (comfort / wellness).
/// Pure and unit-tested — never overshoots the user-chosen target.
///
/// Elapsed-aware: restore / wall-clock jumps catch up to the correct level
/// (no re-easing from target−2 after mid-session restore).
enum SoftStart {
    /// Seconds between strength steps during soft-start.
    static let stepIntervalSeconds = 2

    /// Opening strength for a soft-start (at least 2 below target when target ≥ 3).
    static func initialStrength(target: Int) -> Int {
        let t = max(1, min(9, target))
        guard t >= 3 else { return t }
        return t - 2
    }

    /// Whether soft-start is needed (target is high enough to ease into).
    static func isNeeded(target: Int) -> Bool {
        let t = max(1, min(9, target))
        return initialStrength(target: t) < t
    }

    /// Strength at session elapsed (clamped to target). Pure catch-up for restore.
    static func strength(atElapsed elapsed: Int, target: Int) -> Int {
        let t = max(1, min(9, target))
        let initial = initialStrength(target: t)
        if initial >= t { return t }
        let e = max(0, elapsed)
        let steps = e / stepIntervalSeconds
        return min(t, initial + steps)
    }

    /// Soft-start finished for this elapsed / target.
    static func isComplete(elapsed: Int, target: Int) -> Bool {
        strength(atElapsed: elapsed, target: target) >= max(1, min(9, target))
    }

}

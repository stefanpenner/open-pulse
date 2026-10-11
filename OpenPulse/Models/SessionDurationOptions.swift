import Foundation

/// Still shell duration UX — chips for presets, wheel for Custom…
/// Pure helpers so wheel steps are unit-tested without SwiftUI.
enum SessionDurationOptions {
    /// Soft-start comfort line (wellness only — no medical claims).
    /// Single source for idle Still + intensity card (Still hierarchy).
    static let softStartComfortHint =
        "Eases in low — raise only when comfortable."

    /// Active intensity VoiceOver — honest about mid soft ease-in.
    static func activeIntensityAccessibility(effective: Int, target: Int) -> String {
        if effective <= 0 { return "Intensity off" }
        let t = max(1, min(9, target))
        let e = max(0, min(9, effective))
        if e < t {
            return "Active intensity \(e), easing in toward \(t)"
        }
        return "Active intensity \(e)"
    }

    /// Minute values for the glass drum (mode-aware step rules).
    /// Sleep: 5-min steps. Others: 1-min through 15, then 5-min to max.
    static func wheelMinutes(for mode: StimulationMode) -> [Int] {
        let maxM = BLEConstants.maxSessionMinutes
        if mode == .sleep {
            return Array(stride(from: 5, through: maxM, by: 5))
        }
        var vals: [Int] = Array(1...min(15, maxM))
        if maxM > 15 {
            vals += Array(stride(from: 20, through: maxM, by: 5))
        }
        return vals
    }

    /// Nearest legal wheel value for mode (used when opening sheet / mode change).
    static func snap(_ minutes: Int, for mode: StimulationMode) -> Int {
        let allowed = wheelMinutes(for: mode)
        guard let first = allowed.first else {
            return max(1, min(BLEConstants.maxSessionMinutes, minutes))
        }
        return allowed.min(by: { abs($0 - minutes) < abs($1 - minutes) }) ?? first
    }

    /// True when minutes match a mode chip preset.
    static func isPreset(_ minutes: Int, for mode: StimulationMode) -> Bool {
        mode.durationPresets.contains(minutes)
    }
}

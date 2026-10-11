import Foundation

/// Breath / Island phase labels (wellness only — no medical claims).
/// App target only — depends on `BreathingPhase` in ModeEngine.
enum BreathPhasePresentation {
    /// Short Island / lock status for a breathing phase.
    static func statusText(phase: BreathingPhase?) -> String? {
        guard let phase else { return nil }
        switch phase {
        case .inhale: return "Inhale"
        case .hold: return "Hold"
        case .exhale: return "Exhale"
        case .rest: return "Rest"
        }
    }
}

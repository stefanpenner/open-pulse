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

    /// Circle word. Rest is a quiet gap, so the circle stays blank.
    static func guideLabel(phase: BreathingPhase?) -> String {
        if case .rest = phase { return "" }
        return statusText(phase: phase) ?? ""
    }
}

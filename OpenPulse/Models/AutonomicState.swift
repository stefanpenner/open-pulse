import SwiftUI

/// Describes how the user feels right now; maps to a recommended stimulation mode.
///
/// **Picker** shows five primary feelings (+ Custom in UI).
/// Legacy cases stay for history/restore decode only.
enum AutonomicState: String, CaseIterable, Identifiable {
    case stressed
    case anxious
    case wired
    case foggy
    case learning
    case hurting
    case headachy
    case nauseous
    case scattered

    var id: String { rawValue }

    /// Surface feelings for Still shell (5 max). Custom is separate.
    static var pickerCases: [AutonomicState] {
        [.stressed, .anxious, .wired, .foggy, .hurting]
    }

    var label: String {
        switch self {
        case .stressed:  "Stressed"
        case .anxious:   "Anxious"
        case .wired:     "Can't Sleep"
        case .foggy:     "Foggy"
        case .learning:  "Learning"
        case .hurting:   "Aching"
        case .headachy:  "Head-heavy"
        case .nauseous:  "Queasy"
        case .scattered: "Scattered"
        }
    }

    /// One-line “when to use” for Still mode sheet.
    var whenToUse: String {
        switch self {
        case .stressed:  "Ease the day — steady comfort"
        case .anxious:   "Breath-led calm"
        case .wired:     "Wind down before rest"
        case .foggy:     "Steady left-side focus block"
        case .hurting:   "Gentle body comfort wave"
        case .learning:  "Longer focus block"
        case .headachy:  "Burst comfort pattern"
        case .nauseous:  "Steady bilateral ease"
        case .scattered: "Slower breath pace"
        }
    }

    var icon: String { primaryMode.icon }

    var accentColor: Color { primaryMode.accentColor }

    /// Maps feeling → primary engine mode (merges collapse twins).
    var primaryMode: StimulationMode {
        switch self {
        case .stressed:  .stressRelief
        case .anxious:   .calm
        case .wired:     .sleep
        case .foggy:     .focus
        case .learning:  .focus       // was learn (same engine)
        case .hurting:   .painRelief
        case .headachy:  .painRelief  // Ease · Burst
        case .nauseous:  .stressRelief // same continuous bilateral
        case .scattered: .calm        // Breathe · Meditate pace
        }
    }

    /// Picker row for a primary mode. Twin feelings stay nil.
    static func pickerFeeling(for mode: StimulationMode) -> AutonomicState? {
        switch mode {
        case .stressRelief: .stressed
        case .calm: .anxious
        case .sleep: .wired
        case .focus: .foggy
        case .painRelief: .hurting
        default: nil
        }
    }
}

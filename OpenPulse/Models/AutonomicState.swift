import SwiftUI

/// Describes how the user feels right now; maps to a recommended stimulation mode.
enum AutonomicState: String, CaseIterable, Identifiable {
    case stressed
    case anxious
    case wired
    case foggy
    case hurting
    case headachy
    case nauseous
    case scattered

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stressed:  "Stressed"
        case .anxious:   "Anxious"
        case .wired:     "Can't Sleep"
        case .foggy:     "Foggy"
        case .hurting:   "In Pain"
        case .headachy:  "Headache"
        case .nauseous:  "Nauseous"
        case .scattered: "Scattered"
        }
    }

    var icon: String { primaryMode.icon }

    var accentColor: Color { primaryMode.accentColor }

    var primaryMode: StimulationMode {
        switch self {
        case .stressed:  .stressRelief
        case .anxious:   .calm
        case .wired:     .sleep
        case .foggy:     .focus
        case .hurting:   .painRelief
        case .headachy:  .headache
        case .nauseous:  .nausea
        case .scattered: .meditation
        }
    }
}

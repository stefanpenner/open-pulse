import SwiftUI

enum StimulationMode: String, CaseIterable, Identifiable {
    case stressRelief
    case sleep
    case focus
    case painRelief
    case calm
    case custom

    var id: String { rawValue }

    var name: String {
        switch self {
        case .stressRelief: "Stress Relief"
        case .sleep:        "Sleep"
        case .focus:        "Focus"
        case .painRelief:   "Pain Relief"
        case .calm:         "Calm"
        case .custom:       "Custom"
        }
    }

    var icon: String {
        switch self {
        case .stressRelief: "heart.fill"
        case .sleep:        "moon.fill"
        case .focus:        "brain.head.profile"
        case .painRelief:   "cross.fill"
        case .calm:         "wind"
        case .custom:       "slider.horizontal.3"
        }
    }

    var defaultDurationMinutes: Int {
        switch self {
        case .stressRelief: 6
        case .sleep:        10
        case .focus:        6
        case .painRelief:   8
        case .calm:         5
        case .custom:       10
        }
    }

    var defaultStrength: Int {
        switch self {
        case .stressRelief: 5
        case .sleep:        5
        case .focus:        5
        case .painRelief:   5
        case .calm:         5
        case .custom:       5
        }
    }

    var accentColor: Color {
        switch self {
        case .stressRelief: Theme.accentTeal
        case .sleep:        Theme.accentPurple
        case .focus:        Theme.accentAmber
        case .painRelief:   Theme.accentBlue
        case .calm:         Theme.accentCyan
        case .custom:       Theme.textSecondary
        }
    }

    var summary: String {
        switch self {
        case .stressRelief: "Bilateral stimulation at constant intensity for general vagal toning."
        case .sleep:        "Rotating channels with gentle fade-out to ease into sleep."
        case .focus:        "Left-side only, 30s on/off cycles with a midpoint intensity boost."
        case .painRelief:   "Bilateral with oscillating intensity on a 30-second wave."
        case .calm:         "Respiratory-gated: stimulates on exhale, pauses on inhale."
        case .custom:       "Manual control — set your own timer and intensity."
        }
    }

    var researchLinks: [(label: String, url: String)] {
        switch self {
        case .stressRelief:
            [
                ("Miyaguchi 2024 – Continuous vs intermittent", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11099104/"),
                ("Chen 2022 – HRV effects", "https://peerj.com/articles/14447/"),
                ("Badran 2019 – Heart rate", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6536129/"),
            ]
        case .sleep:
            [
                ("Bottari 2024 – Sleep optimization", "https://onlinelibrary.wiley.com/doi/10.1111/jsr.13891"),
                ("Zhang 2024 – JAMA insomnia RCT", "https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2828072"),
                ("Li 2022 – Primary insomnia", "https://pmc.ncbi.nlm.nih.gov/articles/PMC9599790/"),
            ]
        case .focus:
            [
                ("Sun 2021 – Spatial working memory", "https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2021.790793/full"),
                ("Loerwald 2018 – Inverted-U curve", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6347516/"),
                ("Sharon 2021 – Pupil/alpha response", "https://pmc.ncbi.nlm.nih.gov/articles/PMC7810665/"),
            ]
        case .painRelief:
            [
                ("Straube 2015 – Chronic migraine", "https://pubmed.ncbi.nlm.nih.gov/26156114/"),
                ("Pantaleao 2011 – Amplitude adjustment", "https://pubmed.ncbi.nlm.nih.gov/21277840/"),
                ("CPM study 2024 – Trigeminal", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11543976/"),
            ]
        case .calm:
            [
                ("Garcia 2017 – RAVANS 7T fMRI", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6592731/"),
                ("Sclocco 2021 – RAVANS depression", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8429271/"),
                ("Juel 2019 – Respiratory gating HR", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8041682/"),
            ]
        case .custom:
            []
        }
    }

    var evidenceLevel: String {
        switch self {
        case .stressRelief: "Strong"
        case .sleep:        "Moderate"
        case .focus:        "Moderate-Strong"
        case .painRelief:   "Weak"
        case .calm:         "Strong"
        case .custom:       ""
        }
    }

    func makeEngine() -> ModeEngine? {
        switch self {
        case .stressRelief: StressReliefEngine()
        case .sleep:        SleepEngine()
        case .focus:        FocusEngine()
        case .painRelief:   PainReliefEngine()
        case .calm:         CalmEngine()
        case .custom:       nil
        }
    }
}

import SwiftUI

/// Pace option for Breathe (respiratory-gated) sessions.
enum BreathePace: String, CaseIterable, Identifiable, Sendable {
    case calm
    case meditate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calm: "Calm"
        case .meditate: "Meditate"
        }
    }

    var cycle: BreathingCycle {
        switch self {
        case .calm: .calm
        case .meditate: .meditation
        }
    }
}

/// Pattern option for Ease sessions.
enum EasePattern: String, CaseIterable, Identifiable, Sendable {
    case wave
    case burst

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wave: "Wave"
        case .burst: "Burst"
        }
    }
}

enum StimulationMode: String, CaseIterable, Identifiable {
    case stressRelief
    case sleep
    case focus
    case learn
    case painRelief
    case calm
    case headache
    case nausea
    case meditation
    case custom

    var id: String { rawValue }

    /// Top-level modes for Still shell (engines that differ). Custom is separate.
    static var primaryModes: [StimulationMode] {
        [.stressRelief, .sleep, .focus, .calm, .painRelief]
    }

    var name: String {
        switch self {
        case .stressRelief: "Stress"
        case .sleep:        "Sleep"
        case .focus:        "Focus"
        case .learn:        "Focus"       // merged display
        case .painRelief:   "Ease"
        case .calm:         "Breathe"
        case .headache:     "Ease burst"  // legacy / advanced
        case .nausea:       "Stress"      // same engine as Stress
        case .meditation:   "Breathe"     // merged display
        case .custom:       "Custom"
        }
    }

    var icon: String {
        switch self {
        case .stressRelief: "heart.fill"
        case .sleep:        "moon.fill"
        case .focus:        "brain.head.profile"
        case .learn:        "book.fill"
        case .painRelief:   "waveform.path"
        case .calm:         "wind"
        case .headache:     "bolt.fill"
        case .nausea:       "leaf.circle"
        case .meditation:   "leaf.fill"
        case .custom:       "slider.horizontal.3"
        }
    }

    var defaultDurationMinutes: Int {
        switch self {
        case .stressRelief: 6
        case .sleep:        10
        case .focus:        6
        case .learn:        10
        case .painRelief:   8
        case .calm:         5
        case .headache:     6
        case .nausea:       5
        case .meditation:   10
        case .custom:       10
        }
    }

    /// Optional quick-pick durations (minutes). Sleep offers longer rest windows (20–30).
    var durationPresets: [Int] {
        switch self {
        case .sleep:        [10, 20, 30]
        case .meditation:   [10, 15, 20]
        case .learn:        [6, 10, 15]
        // Focus absorbs Learn lengths (study 10 / deep 15)
        case .focus:        [6, 10, 15]
        // Short sessions match common nVNS wellness session lengths (2–6 min)
        case .stressRelief, .nausea: [4, 6, 10]
        // Breathe absorbs Meditation lengths
        case .calm:         [4, 6, 10, 15, 20]
        case .painRelief, .headache: [6, 10, 15]
        default:            []
        }
    }

    /// Default intensity 1…9 (device max is 9). Slightly higher “comfortable”
    /// defaults — soft-start still eases in; last-used strength wins when set.
    var defaultStrength: Int {
        switch self {
        case .stressRelief: 6
        case .sleep:        5
        case .focus:        6
        case .learn:        6
        case .painRelief:   7
        case .calm:         6
        case .headache:     6
        case .nausea:       6
        case .meditation:   5
        case .custom:       6
        }
    }

    var accentColor: Color {
        switch self {
        case .stressRelief: Theme.accentTeal
        case .sleep:        Theme.accentPurple
        case .focus:        Theme.accentAmber
        case .learn:        Theme.accentAmber
        case .painRelief:   Theme.accentBlue
        case .calm:         Theme.accentCyan
        case .headache:     Theme.accentRed
        case .nausea:       Theme.accentMint
        case .meditation:   Theme.accentIndigo
        case .custom:       Theme.textSecondary
        }
    }

    var summary: String {
        switch self {
        case .stressRelief: "Steady bilateral comfort at constant intensity."
        case .sleep:        "Rotating channels with gentle fade-out to ease into rest."
        case .focus:        "Left-side only, 30s on/off duty cycles at constant intensity."
        case .learn:        "Left-side duty cycles (10 min) as a pre-study primer."
        case .painRelief:   "Bilateral with oscillating intensity on a 30-second comfort wave."
        case .calm:         "Respiratory-gated: prepares on late inhale, active through hold and exhale."
        case .headache:     "Bilateral bursts with brief pauses (comfort pattern)."
        case .nausea:       "Continuous bilateral comfort for general gut-brain ease."
        case .meditation:   "Slower respiratory gating (~4 breaths/min) for a meditative pace."
        case .custom:       "Manual control — set your own timer and intensity."
        }
    }

    var researchLinks: [(label: String, url: String)] {
        switch self {
        case .stressRelief:
            [
                ("Horinouchi 2024 – Continuous vs intermittent", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11099104/"),
                ("Forte 2022 – Heart-rate variability study", "https://peerj.com/articles/14447/"),
                ("Badran 2018 – Heart rate study", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6536129/"),
            ]
        case .sleep:
            [
                ("Bottari 2024 – Sleep pilot", "https://onlinelibrary.wiley.com/doi/10.1111/jsr.13891"),
                ("Zhang 2024 – Sleep quality study", "https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2828072"),
                ("Wu 2022 – Sleep comfort pilot", "https://pmc.ncbi.nlm.nih.gov/articles/PMC9599790/"),
            ]
        case .focus:
            [
                ("Sun 2021 – Spatial working memory", "https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2021.790793/full"),
                ("Morrison 2018 – Inverted-U curve", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6347516/"),
                ("Sharon 2021 – Pupil/alpha response", "https://pmc.ncbi.nlm.nih.gov/articles/PMC7810665/"),
            ]
        case .learn:
            [
                ("Miyatsu 2024 – Vocabulary acquisition study", "https://www.nature.com/articles/s41598-024-68015-4"),
                ("Sun 2021 – Spatial working memory", "https://www.frontiersin.org/journals/neuroscience/articles/10.3389/fnins.2021.790793/full"),
                ("Morrison 2018 – Inverted-U curve", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6347516/"),
            ]
        case .painRelief:
            [
                ("Straube 2015 – Head comfort study", "https://pubmed.ncbi.nlm.nih.gov/26156114/"),
                ("Pantaleao 2011 – Amplitude adjustment", "https://pubmed.ncbi.nlm.nih.gov/21277840/"),
                ("CPM study 2024 – Comfort pathways", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11543976/"),
            ]
        case .calm:
            [
                ("Sclocco 2019 – Breathing-gated imaging", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6592731/"),
                ("Garcia 2021 – Mood & breathing study", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8429271/"),
                ("Paleczny 2019 – Respiratory gating HR", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8041682/"),
            ]
        case .headache:
            [
                ("Head comfort meta-analysis 2023", "https://pmc.ncbi.nlm.nih.gov/articles/PMC10213755/"),
                ("Real-world registry (PubMed)", "https://pubmed.ncbi.nlm.nih.gov/32109020/"),
            ]
        case .nausea:
            [
                ("Gut comfort study 2023", "https://journals.lww.com/ajg/fulltext/2023/10001/s1846_non_invasive_vagal_nerve_stimulation_reduces.2187.aspx"),
                ("Motion comfort study 2024", "https://pmc.ncbi.nlm.nih.gov/articles/PMC11531436/"),
            ]
        case .meditation:
            [
                ("Meditation comfort RCT 2025", "https://pmc.ncbi.nlm.nih.gov/articles/PMC12341030/"),
                ("Sclocco 2019 – Breathing-gated imaging", "https://pmc.ncbi.nlm.nih.gov/articles/PMC6592731/"),
                ("Paleczny 2019 – Respiratory gating HR", "https://pmc.ncbi.nlm.nih.gov/articles/PMC8041682/"),
            ]
        case .custom:
            []
        }
    }

    /// Pattern design label (bibliographic / wellness — not a clinical efficacy claim).
    var evidenceLevel: String {
        switch self {
        // Bibliographic / pattern labels — not efficacy claims (wellness framing)
        case .stressRelief: "Pattern informed by published research"
        case .sleep:        "Emerging research pattern"
        case .focus:        "Pattern informed by published research"
        case .learn:        "Emerging research pattern"
        case .painRelief:   "Exploratory comfort pattern"
        case .calm:         "Pattern informed by published research"
        case .headache:     "Inspired by published patterns"
        case .nausea:       "Emerging research pattern"
        case .meditation:   "Emerging research pattern"
        case .custom:       ""
        }
    }

    /// Whether this mode uses a breathing guide UI instead of the standard timer hero.
    var usesBreathingGuide: Bool {
        switch self {
        case .calm, .meditation: true
        default: false
        }
    }

    /// Modes whose stim on/off edges matter under background (duty / breath / burst / sleep fade).
    /// Continuous bilateral Stress is more tolerant of coarse keepalive.
    var needsBackgroundEdgeHonesty: Bool {
        switch self {
        case .focus, .learn, .calm, .meditation, .headache: true
        case .painRelief: true // Ease · Wave / Burst — pure tick + absolute on long gaps
        case .sleep: true      // channel rotate + fade floors need wall-clock honesty
        default: false
        }
    }

    /// The breathing cycle parameters, if this mode uses respiratory gating.
    var breathingCycle: BreathingCycle? {
        switch self {
        case .calm: .calm
        case .meditation: .meditation
        default: nil
        }
    }

    /// Default engine for the mode (ignores pace/pattern options).
    func makeEngine() -> ModeEngine? {
        makeEngine(breathePace: .calm, easePattern: .wave)
    }

    /// Engine with Still advanced options (Breathe pace, Ease pattern).
    func makeEngine(breathePace: BreathePace, easePattern: EasePattern) -> ModeEngine? {
        switch self {
        case .stressRelief, .nausea: StressReliefEngine()
        case .sleep:        SleepEngine()
        case .focus, .learn: FocusEngine()
        case .painRelief:
            easePattern == .burst ? HeadacheEngine() : PainReliefEngine()
        case .headache:     HeadacheEngine()
        case .calm:
            breathePace == .meditate ? MeditationEngine.make() : CalmEngine.make()
        case .meditation:   MeditationEngine.make()
        case .custom:       nil
        }
    }
}

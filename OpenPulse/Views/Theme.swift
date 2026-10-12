import SwiftUI

enum Theme {
    // Background gradient — deep, calm wellness palette
    static let backgroundTop = Color(hex: 0x0A0E1A)
    static let backgroundBottom = Color(hex: 0x141B2D)

    // Accent colors
    static let accentTeal = Color(hex: 0x00E5CC)
    static let accentBlue = Color(hex: 0x4A90E2)
    static let accentRed = Color(hex: 0xEF4444)

    // Mode accent colors
    static let accentPurple = Color(hex: 0xA855F7)
    static let accentAmber = Color(hex: 0xF59E0B)
    static let accentCyan = Color(hex: 0x06B6D4)
    static let accentMint = Color(hex: 0x34D399)
    static let accentIndigo = Color(hex: 0x818CF8)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x9CA3AF)
    static let textTertiary = Color(hex: 0x6B7280)

    // Status
    static let connectedGreen = Color(hex: 0x10B981)
    static let disconnectedRed = Color(hex: 0xEF4444)

    // MARK: - Spacing (content rhythm)

    static let spaceXS: CGFloat = 4
    static let spaceS: CGFloat = 8
    static let spaceM: CGFloat = 12
    static let spaceL: CGFloat = 16
    static let spaceXL: CGFloat = 24
    static let cornerCard: CGFloat = 18
    static let cornerControl: CGFloat = 14

    // Background gradient
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Type Scale (Dynamic Type friendly where system fonts allow)

    /// Section headers: "SESSION TIMER", "INTENSITY LEVEL"
    static let sectionLabel = Font.caption.weight(.semibold).width(.expanded)
    /// Card subtitles: mode name, effective strength
    static let cardSubtitle = Font.caption2.weight(.medium)
    /// Hero numbers: timer display (scales with Dynamic Type)
    static let heroTimer = Font.system(.largeTitle, design: .monospaced).weight(.light)
    /// Large hero timer for active session
    static let heroTimerLarge = Font.system(.largeTitle, design: .monospaced).weight(.light)
    /// Large numbers: strength badge
    static let heroNumber = Font.system(.title, design: .rounded).weight(.semibold)
    /// Mode status text
    static let statusLabel = Font.caption.weight(.medium)
    /// Button text
    static let buttonLabel = Font.body.weight(.semibold)
    /// Breathing phase label
    static let breathingLabel = Font.title3.weight(.regular)
    /// Screen title
    static let screenTitle = Font.title2.weight(.medium)
    /// Still shell hero mode word (STRESS / SLEEP / …)
    static let heroMode = Font.system(.largeTitle, design: .rounded).weight(.light)
    /// Active remaining time at accessibility sizes (glasses-off / stim-on).
    static let heroTimerA11y = Font.system(.title, design: .monospaced).weight(.semibold)

    /// Soft mode bloom opacity — restrained (not rainbow sugar-high).
    static let modeBloomOpacity: Double = 0.10
    /// Idle hero / timer content field (solid — glass reserved for controls).
    static let contentHeroFill = Color(hex: 0x151C2C)

    /// Solid surface when Reduce Transparency is on (wellness chrome still readable).
    static let solidSurface = Color(hex: 0x1A2336)
    static let solidSurfaceElevated = Color(hex: 0x222C42)
}

// MARK: - Reduce Transparency glass fallback

/// Style token for unit tests (glass vs solid).
enum WellnessSurfaceStyle: Equatable, Sendable {
    case glass
    case solid
}

enum WellnessSurface {
    /// Prefer glass; solid when accessibility Reduce Transparency is enabled.
    static func style(reduceTransparency: Bool) -> WellnessSurfaceStyle {
        reduceTransparency ? .solid : .glass
    }
}

extension View {
    /// Glass chrome that falls back to solid fill under Reduce Transparency.
    /// Prefer for interactive controls (HIG functional layer), not content cards.
    func wellnessGlass(
        _ glass: Glass = .regular,
        in shape: some Shape,
        solid: Color = Theme.solidSurface
    ) -> some View {
        modifier(WellnessGlassModifier(glass: glass, shape: AnyShape(shape), solid: solid))
    }

    /// Content-layer surface (solid elevated fill) — keeps glass for controls only.
    func wellnessContentSurface(in shape: some Shape, color: Color = Theme.solidSurfaceElevated) -> some View {
        background(color, in: shape)
    }
}

/// Type-erased shape for the glass modifier.
private struct AnyShape: Shape, @unchecked Sendable {
    private let _path: @Sendable (CGRect) -> Path
    init<S: Shape>(_ shape: S) {
        _path = { shape.path(in: $0) }
    }
    func path(in rect: CGRect) -> Path { _path(rect) }
}

private struct WellnessGlassModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let glass: Glass
    let shape: S
    let solid: Color

    func body(content: Content) -> some View {
        if WellnessSurface.style(reduceTransparency: reduceTransparency) == .solid {
            content.background(solid, in: shape)
        } else {
            content.glassEffect(glass, in: shape)
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

import SwiftUI

enum Theme {
    // Background gradient
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

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x9CA3AF)
    static let textTertiary = Color(hex: 0x6B7280)

    // Status
    static let connectedGreen = Color(hex: 0x10B981)
    static let disconnectedRed = Color(hex: 0xEF4444)

    // Background gradient
    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundTop, backgroundBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Type Scale

    /// Section headers: "SESSION TIMER", "INTENSITY LEVEL"
    static let sectionLabel = Font.caption.weight(.semibold).width(.expanded)
    /// Card subtitles: mode name, effective strength
    static let cardSubtitle = Font.caption2.weight(.medium)
    /// Hero numbers: timer display
    static let heroTimer = Font.system(size: 54, weight: .light, design: .monospaced)
    /// Large hero timer for active session
    static let heroTimerLarge = Font.system(size: 64, weight: .light, design: .monospaced)
    /// Large numbers: strength badge
    static let heroNumber = Font.system(size: 30, weight: .semibold, design: .rounded)
    /// Mode status text
    static let statusLabel = Font.caption.weight(.medium)
    /// Button text
    static let buttonLabel = Font.body.weight(.semibold)
    /// Breathing phase label
    static let breathingLabel = Font.title3.weight(.regular)
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

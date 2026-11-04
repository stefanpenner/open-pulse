import Foundation

/// The words for the Joy-Con pairing card. Pure: no UI types.
enum JoyConPairing {
    struct Row: Equatable {
        let side: BilateralTicks.Side
        let text: String
        let accessibilityLabel: String
        /// The Joy-Con is connected and can tap.
        let isReady: Bool
    }

    static let title = "Pair your Joy-Cons"

    static let steps = [
        "1. Hold the small sync button on the rail until the lights run.",
        "2. Open Settings, then Bluetooth. Tap the Joy-Con under Other Devices.",
        "3. Come back here. Each side shows connected.",
    ]

    /// The app cannot open the Bluetooth page. It can open its own page in Settings.
    static let settingsNote = "The app cannot open the Bluetooth page. Settings opens, then tap Bluetooth."

    static let settingsLinkTitle = "Open Settings"
    static let testButtonTitle = "Test taps"
    static let testHint = "Taps left, then right, once."

    /// `found`: every Joy-Con iOS shows. `working`: the ones that can tap now.
    static func rows(found: JoyConTapper.Plan, working: JoyConTapper.Plan) -> [Row] {
        [
            row(.left, name: "Left", found: found.left != nil, working: working.left != nil),
            row(.right, name: "Right", found: found.right != nil, working: working.right != nil),
        ]
    }

    private static func row(_ side: BilateralTicks.Side, name: String, found: Bool, working: Bool) -> Row {
        let (state, detail): (String, String) = switch (found, working) {
        case (_, true): ("connected", "connected")
        case (true, false): ("found, but it cannot tap. The phone taps this side.", "found, but it cannot tap. The phone taps this side")
        case (false, _): ("not found", "not found")
        }
        return Row(
            side: side,
            text: "\(name): \(state)",
            accessibilityLabel: "\(name) Joy-Con: \(detail)",
            isReady: working
        )
    }

    /// The test needs a Joy-Con that can tap. It must not cut into a running session.
    static func canTestTaps(working: JoyConTapper.Plan, sessionPlaying: Bool) -> Bool {
        !working.isEmpty && !sessionPlaying
    }
}

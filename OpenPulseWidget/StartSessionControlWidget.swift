import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock-adjacent control: Start last session path (opens app + bridge).
/// Privacy-first — no network; device must still be ready for Start.
@available(iOS 18.0, *)
struct StartSessionControlWidget: ControlWidget {
    static let kind = "com.stefanpenner.OpenPulse.startSession"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartOpenPulseSessionIntent()) {
                Label("Start session", systemImage: "play.circle.fill")
            }
        }
        .displayName("Start Open Pulse")
        .description("Starts a session when your Pulsetto is connected.")
    }
}

import SwiftUI

@main
struct OpenPulseApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        // Scene phase changes need to reach the SessionViewModel.
        // Post a notification that ContentView (which owns the VM) can relay,
        // or use the notification center directly.
        NotificationCenter.default.post(
            name: .appScenePhaseChanged,
            object: nil,
            userInfo: ["oldPhase": oldPhase, "newPhase": newPhase]
        )
    }
}

extension Notification.Name {
    static let appScenePhaseChanged = Notification.Name("appScenePhaseChanged")
}

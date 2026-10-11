import SwiftUI
import WidgetKit

@main
struct OpenPulseWidgetBundle: WidgetBundle {
    var body: some Widget {
        SessionLiveActivityWidget()
        if #available(iOS 18.0, *) {
            StartSessionControlWidget()
        }
    }
}

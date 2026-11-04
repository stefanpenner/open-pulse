import CoreHaptics
import Foundation
import GameController

/// Finds paired Joy-Cons and loops each side's tap on that side's controller.
/// Which controller plays which side is decided by `JoyConTapper` (pure).
@MainActor
final class JoyConHaptics {
    private(set) var plan = JoyConTapper.Plan()
    var onChange: (@MainActor (JoyConTapper.Plan) -> Void)?

    private var controllers: [GCController] = []
    private var observers: [NSObjectProtocol] = []
    private var engines: [CHHapticEngine] = []
    private var players: [CHHapticAdvancedPatternPlayer] = []

    var isTapping: Bool { !players.isEmpty }

    // MARK: - Discovery

    func watch() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    func unwatch() {
        guard !observers.isEmpty else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        stopTaps()
        controllers = []
        publish(JoyConTapper.Plan())
    }

    private func refresh() {
        controllers = GCController.controllers()
        let candidates = controllers.enumerated().compactMap { index, controller in
            JoyConTapper.kind(name: controller.vendorName, category: controller.productCategory)
                .map { JoyConTapper.Candidate(id: index, kind: $0) }
        }
        publish(JoyConTapper.plan(candidates))
    }

    private func publish(_ next: JoyConTapper.Plan) {
        guard next != plan else { return }
        plan = next
        onChange?(next)
    }

    // MARK: - Taps

    /// One engine per covered side. Each loops its own side's tap on the shared beat.
    func startTaps(_ plan: JoyConTapper.Plan) {
        guard !isTapping else { return }
        let sides: [(BilateralTicks.Side, JoyConTapper.Slot?)] = [(.left, plan.left), (.right, plan.right)]
        for (side, slot) in sides {
            guard let slot, let player = makePlayer(side: side, slot: slot) else { continue }
            players.append(player)
        }
        for player in players {
            try? player.start(atTime: CHHapticTimeImmediate)
        }
    }

    func stopTaps() {
        for player in players { try? player.stop(atTime: CHHapticTimeImmediate) }
        for engine in engines { engine.stop() }
        players = []
        engines = []
    }

    private func makePlayer(side: BilateralTicks.Side, slot: JoyConTapper.Slot) -> CHHapticAdvancedPatternPlayer? {
        guard controllers.indices.contains(slot.controller),
              let haptics = controllers[slot.controller].haptics,
              let engine = haptics.createEngine(withLocality: Self.locality(slot.part, in: haptics)) else {
            return nil
        }
        do {
            engine.isAutoShutdownEnabled = false
            try engine.start()
            let player = try engine.makeAdvancedPlayer(
                with: SessionAmbientAudio.tapPattern(for: [side])
            )
            player.loopEnabled = true
            player.loopEnd = BilateralTicks.loopSeconds
            engines.append(engine)
            return player
        } catch {
            engine.stop()
            return nil
        }
    }

    /// A handle locality when the controller offers it. Otherwise the default one.
    private static func locality(_ part: JoyConTapper.Part, in haptics: GCDeviceHaptics) -> GCHapticsLocality {
        let wanted: GCHapticsLocality = switch part {
        case .whole: .default
        case .leftHandle: .leftHandle
        case .rightHandle: .rightHandle
        }
        return haptics.supportedLocalities.contains(wanted) ? wanted : .default
    }
}

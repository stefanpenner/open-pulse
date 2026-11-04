import CoreHaptics
import Foundation
import GameController

/// Finds paired Joy-Cons and loops each side's tap on that side's controller.
/// Which controller plays which side is decided by `JoyConTapper` (pure).
///
/// An engine that stops or resets marks its controller failed. The plan then drops that
/// controller, and the owner hands the side to the phone. Failed clears at the next
/// session start (`retryFailed`) and when a controller connects or disconnects.
@MainActor
final class JoyConHaptics {
    /// Joy-Cons that can tap now. A failed controller is not in it.
    private(set) var plan = JoyConTapper.Plan()
    /// Every Joy-Con iOS shows, even one that cannot tap.
    private(set) var found = JoyConTapper.Plan()
    /// What `JoyConTapper.route` reads. Index into `controllers`.
    private(set) var candidates: [JoyConTapper.Candidate] = []
    var failedIDs: Set<Int> {
        Set(controllers.indices.filter { failed.contains(ObjectIdentifier(controllers[$0])) })
    }
    var onChange: (@MainActor () -> Void)?

    private var controllers: [GCController] = []
    private var failed: Set<ObjectIdentifier> = []
    private var observers: [NSObjectProtocol] = []
    private var voices: [Voice] = []
    private var testTask: Task<Void, Never>?

    private struct Voice {
        let engine: CHHapticEngine
        let player: CHHapticPatternPlayer
        let controller: ObjectIdentifier
    }

    var isTapping: Bool { !voices.isEmpty }
    var isWatching: Bool { !observers.isEmpty }

    // MARK: - Discovery

    func watch() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                // The object is the controller. On a disconnect it may still be listed.
                let gone = name == .GCControllerDidDisconnect
                    ? (note.object as? GCController).map(ObjectIdentifier.init) : nil
                MainActor.assumeIsolated { self?.refresh(excluding: gone, clearFailed: true) }
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
        failed = []
        publish(candidates: [])
    }

    /// A new session retries every engine that failed.
    func retryFailed() {
        guard !failed.isEmpty, !isTapping else { return }
        failed = []
        publish(candidates: candidates)
    }

    private func refresh(excluding gone: ObjectIdentifier? = nil, clearFailed: Bool = false) {
        controllers = GCController.controllers().filter { ObjectIdentifier($0) != gone }
        if clearFailed { failed = [] }
        failed.formIntersection(controllers.map(ObjectIdentifier.init))
        let next = controllers.enumerated().compactMap { index, controller in
            JoyConTapper.classify(
                name: controller.vendorName,
                category: controller.productCategory,
                haptics: controller.haptics.map(Self.handles)
            ).map { JoyConTapper.Candidate(id: index, kind: $0.kind, canTap: $0.canTap) }
        }
        publish(candidates: next)
    }

    @discardableResult
    private func publish(candidates next: [JoyConTapper.Candidate], notify: Bool = true) -> Bool {
        let usable = next.filter { !failedIDs.contains($0.id) && $0.canTap }
        let nextPlan = JoyConTapper.plan(usable)
        let nextFound = JoyConTapper.plan(next)
        guard next != candidates || nextPlan != plan || nextFound != found else { return false }
        candidates = next
        plan = nextPlan
        found = nextFound
        if notify { onChange?() }
        return true
    }

    private static func handles(_ haptics: GCDeviceHaptics) -> JoyConTapper.Handles {
        JoyConTapper.Handles(
            left: haptics.supportedLocalities.contains(.leftHandle),
            right: haptics.supportedLocalities.contains(.rightHandle)
        )
    }

    // MARK: - Taps

    /// One engine per covered side. Each loops its own side's tap on the shared beat.
    /// Returns the sides that now tap. A side that fails to start is not in it.
    /// The failed controller leaves the plan. The caller gives its side to the phone.
    @discardableResult
    func startTaps(_ plan: JoyConTapper.Plan) -> Set<BilateralTicks.Side> {
        guard !isTapping else { return self.plan.covered }
        let started = startVoices(plan, loop: true, watchLoss: true)
        // Tell the owner later. A call now would restart this start in the middle.
        if publish(candidates: candidates, notify: false) {
            Task { @MainActor [weak self] in self?.onChange?() }
        }
        return started
    }

    func stopTaps() {
        testTask?.cancel()
        testTask = nil
        for voice in voices {
            Self.detach(voice.engine)
            try? voice.player.stop(atTime: CHHapticTimeImmediate)
            voice.engine.stop()
        }
        voices = []
    }

    /// One tap left, then one tap right, on the Joy-Cons that can tap. Not for use in a session.
    func playTest() {
        guard !isTapping else { return }
        _ = startVoices(plan, loop: false, watchLoss: false)
        testTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(BilateralTicks.loopSeconds + 0.5))
            guard !Task.isCancelled else { return }
            self?.stopTaps()
        }
    }

    private func startVoices(_ plan: JoyConTapper.Plan, loop: Bool, watchLoss: Bool) -> Set<BilateralTicks.Side> {
        var sides: [(BilateralTicks.Side, Voice)] = []
        for (side, slot) in [(BilateralTicks.Side.left, plan.left), (.right, plan.right)] {
            guard let slot else { continue }
            if let voice = makeVoice(side: side, slot: slot, loop: loop, watchLoss: watchLoss) {
                sides.append((side, voice))
            } else if controllers.indices.contains(slot.controller) {
                failed.insert(ObjectIdentifier(controllers[slot.controller]))
            }
        }
        // Start together, after every engine is up, so the sides share one beat.
        var playing: [(BilateralTicks.Side, Voice)] = []
        for (side, voice) in sides {
            do {
                try voice.player.start(atTime: CHHapticTimeImmediate)
                playing.append((side, voice))
            } catch {
                failed.insert(voice.controller)
                release(voice)
            }
        }
        // A pair that lost one handle loses both. Its other side goes to the phone too.
        for (_, voice) in playing where failed.contains(voice.controller) {
            try? voice.player.stop(atTime: CHHapticTimeImmediate)
            release(voice)
        }
        playing.removeAll { failed.contains($0.1.controller) }
        voices = playing.map(\.1)
        return Set(playing.map(\.0))
    }

    private func release(_ voice: Voice) {
        Self.detach(voice.engine)
        voice.engine.stop()
    }

    /// The handlers are not optional. Swap in empty ones so a stop does not call back.
    private nonisolated static func detach(_ engine: CHHapticEngine) {
        engine.stoppedHandler = { _ in }
        engine.resetHandler = {}
    }

    private func makeVoice(side: BilateralTicks.Side, slot: JoyConTapper.Slot, loop: Bool, watchLoss: Bool) -> Voice? {
        guard controllers.indices.contains(slot.controller) else { return nil }
        let controller = controllers[slot.controller]
        guard let haptics = controller.haptics,
              let engine = haptics.createEngine(withLocality: Self.locality(slot.part, in: haptics)) else {
            return nil
        }
        let id = ObjectIdentifier(controller)
        do {
            engine.isAutoShutdownEnabled = !loop
            if watchLoss {
                engine.stoppedHandler = { [weak self] _ in Task { @MainActor in self?.lost(id) } }
                engine.resetHandler = { [weak self] in Task { @MainActor in self?.lost(id) } }
            }
            try engine.start()
            let player = try engine.makeAdvancedPlayer(with: SessionAmbientAudio.tapPattern(for: [side]))
            if loop {
                player.loopEnabled = true
                // The pattern holds one tap. The loop runs the full beat pair, so the gap is silence.
                player.loopEnd = BilateralTicks.loopSeconds
            }
            return Voice(engine: engine, player: player, controller: id)
        } catch {
            Self.detach(engine)
            engine.stop()
            return nil
        }
    }

    /// An engine stopped or reset while it played. The controller leaves the plan.
    private func lost(_ id: ObjectIdentifier) {
        guard voices.contains(where: { $0.controller == id }) else { return }
        failed.insert(id)
        // The owner restarts every output on the new plan, so the beat stays shared.
        publish(candidates: candidates)
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

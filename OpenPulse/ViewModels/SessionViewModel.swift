import Foundation
import UIKit
import Combine

@MainActor
final class SessionViewModel: ObservableObject {
    @Published var timerMinutes = 10
    @Published var strength = 5
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var remainingSeconds = 0

    // Mode support
    @Published var selectedMode: StimulationMode = .custom
    @Published var selectedFeeling: AutonomicState? = nil
    @Published var stimulationActive = false
    @Published var effectiveStrength: Int? = nil
    @Published var breathingPhase: BreathingPhase? = nil
    @Published var modeStatus: String = ""
    @Published var activeChannel: ActiveChannel = .off

    let ble = BluetoothManager()

    // Computed
    var displayTime: String {
        let total = (isRunning || isPaused) ? remainingSeconds : timerMinutes * 60
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }

    var progress: Double {
        guard isRunning || isPaused, sessionTotalDuration > 0 else { return 0 }
        return 1.0 - Double(remainingSeconds) / Double(sessionTotalDuration)
    }

    private var countdownTimer: Timer?
    private var keepaliveSource: DispatchSourceTimer?
    private var statusPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var engine: ModeEngine?
    private var sessionTotalDuration = 0
    private var elapsed: Int { sessionTotalDuration - remainingSeconds }

    // Wall-clock tracking (internal for testability)
    var sessionStartDate: Date?
    var accumulatedPauseTime: TimeInterval = 0
    private var pauseStartDate: Date?
    var backgroundEntryDate: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ble.onDisconnect = { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleDisconnect()
            }
        }

        // Restart keepalive/poll when connection comes back
        ble.$isReady
            .removeDuplicates()
            .sink { [weak self] ready in
                guard let self, ready else { return }
                self.startStatusPoll()
                if self.isRunning {
                    self.resumeSessionOnDevice()
                }
            }
            .store(in: &cancellables)

        restoreSessionIfNeeded()
    }

    // MARK: - Mode Selection

    func selectMode(_ mode: StimulationMode) {
        guard !isRunning, !isPaused else { return }
        selectedMode = mode
        selectedFeeling = nil
        timerMinutes = mode.defaultDurationMinutes
        strength = mode.defaultStrength
    }

    func selectFeeling(_ state: AutonomicState) {
        guard !isRunning, !isPaused else { return }
        selectMode(state.primaryMode)
        selectedFeeling = state
    }

    // MARK: - Actions

    func start() {

        isRunning = true
        sessionTotalDuration = timerMinutes * 60
        remainingSeconds = sessionTotalDuration
        UIApplication.shared.isIdleTimerDisabled = true

        // Wall-clock tracking
        sessionStartDate = Date()
        accumulatedPauseTime = 0
        pauseStartDate = nil
        backgroundEntryDate = nil

        // Initialize engine
        engine = selectedMode.makeEngine()

        if var engine {
            let cmds = engine.start(baseStrength: strength, totalDuration: sessionTotalDuration)
            self.engine = engine
            ble.sendCommands(cmds)
            // Set initial state from engine
            stimulationActive = true
            activeChannel = .bilateral
            if selectedMode == .calm {
                // Calm starts with inhale (stim off)
                stimulationActive = false
                activeChannel = .off
                breathingPhase = .inhale(progress: 0)
                modeStatus = "Inhale · Paused"
            } else if selectedMode == .focus {
                activeChannel = .left
            } else {
                modeStatus = "Starting"
            }
        } else {
            // Custom mode: original behavior
            ble.sendCommands([BLEConstants.activateCommand, BLEConstants.strengthCommand(strength)])
            stimulationActive = true
            activeChannel = .bilateral
            debugActiveChannel = "D"
            modeStatus = "Bilateral · Continuous"
        }

        startCountdown()
        startKeepalive()
        persistSession()
    }

    func stop() {
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        sessionTotalDuration = 0
        UIApplication.shared.isIdleTimerDisabled = false

        // Clear wall-clock state
        sessionStartDate = nil
        accumulatedPauseTime = 0
        pauseStartDate = nil
        backgroundEntryDate = nil

        // Clear engine state
        engine = nil
        stimulationActive = false
        effectiveStrength = nil
        breathingPhase = nil
        activeChannel = .off
        debugActiveChannel = ""
        modeStatus = ""

        stopCountdown()
        stopKeepalive()
        clearPersistedSession()

        if ble.isConnected {
            ble.sendCommand(BLEConstants.deactivateCommand)
            queryStatus()
        }
    }

    func pause() {
        guard isRunning else { return }
        isPaused = true
        isRunning = false

        // Record pause start for wall-clock tracking
        pauseStartDate = Date()

        stopCountdown()
        stopKeepalive()

        // Deactivate device
        if ble.isConnected {
            ble.sendCommand(BLEConstants.deactivateCommand)
        }

        // Clear mode transient state but keep engine
        stimulationActive = false
        effectiveStrength = nil
        breathingPhase = nil
        activeChannel = .off
        persistSession()
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        isRunning = true

        // Accumulate paused duration
        if let pauseStart = pauseStartDate {
            accumulatedPauseTime += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }

        // Recalculate from wall clock after resume
        recalculateFromWallClock()

        // Re-activate with correct mode state
        if let engine {
            let cmds = engine.reconnectCommands(
                elapsed: elapsed,
                totalDuration: sessionTotalDuration,
                baseStrength: strength
            )
            ble.sendCommands(cmds)
        } else {
            ble.sendCommands([BLEConstants.activateCommand, BLEConstants.strengthCommand(strength)])
        }

        stimulationActive = true
        startCountdown()
        startKeepalive()
        persistSession()
    }

    @Published var debugActiveChannel: String = ""

    func sendDebugCommand(_ cmd: String) {
        guard ble.isConnected else { return }
        ble.sendCommand(cmd + "\n")
        debugActiveChannel = cmd
        if cmd != "0" {
            ble.sendCommand(BLEConstants.strengthCommand(strength))
        }
    }

    func increaseTimer() {
        if isRunning || isPaused {
            adjustRemainingTime(by: 60)
        } else {
            timerMinutes += 1
        }
    }

    func decreaseTimer() {
        if isRunning || isPaused {
            adjustRemainingTime(by: -60)
        } else {
            guard timerMinutes > 1 else { return }
            timerMinutes -= 1
        }
    }

    private func adjustRemainingTime(by seconds: Int) {
        let newRemaining = max(60, remainingSeconds + seconds)
        let delta = newRemaining - remainingSeconds
        remainingSeconds = newRemaining
        sessionTotalDuration += delta
    }

    func setStrength(_ value: Int) {
        let clamped = max(1, min(9, value))
        strength = clamped
        guard isRunning, ble.isConnected, stimulationActive else { return }
        ble.sendCommand(BLEConstants.strengthCommand(clamped))
    }

    // MARK: - Wall-Clock Recalculation

    private func recalculateFromWallClock() {
        guard let startDate = sessionStartDate else { return }

        let now = Date()
        let totalElapsed = now.timeIntervalSince(startDate)
        let activeElapsed = totalElapsed - accumulatedPauseTime
        let elapsedSeconds = Int(activeElapsed)
        let newRemaining = max(0, sessionTotalDuration - elapsedSeconds)

        if newRemaining <= 0 {
            stop()
            return
        }

        remainingSeconds = newRemaining
        processTick()
    }

    // MARK: - Scene Phase

    func scenePhaseHandler(from oldPhase: Any, to newPhase: Any) {
        // Import SwiftUI's ScenePhase values via string comparison to avoid
        // importing SwiftUI in this ViewModel. The caller passes ScenePhase values.
        scenePhaseTransition(wentToBackground: "\(newPhase)" == "background",
                             returnedToForeground: "\(oldPhase)" == "background" && "\(newPhase)" != "background")
    }

    func handleBackgroundTransition() {
        scenePhaseTransition(wentToBackground: true, returnedToForeground: false)
    }

    func handleForegroundTransition() {
        scenePhaseTransition(wentToBackground: false, returnedToForeground: true)
    }

    private func scenePhaseTransition(wentToBackground: Bool, returnedToForeground: Bool) {
        if wentToBackground {
            guard isRunning else { return }
            backgroundEntryDate = Date()
            // Stop the countdown timer — it won't fire reliably in background.
            // Keepalive continues via DispatchSourceTimer + bluetooth-central background mode.
            stopCountdown()
            persistSession()
        }

        if returnedToForeground {
            backgroundEntryDate = nil
            guard isRunning else { return }
            // Recalculate elapsed time from wall clock.
            // This may call stop() if the session expired while backgrounded.
            recalculateFromWallClock()
            // Only resume if the session is still active after recalculation.
            guard isRunning else { return }
            // Resend correct BLE commands to device
            resumeSessionOnDevice()
            // Restart UI countdown timer
            startCountdown()
        }
    }

    // MARK: - Timers

    private func startCountdown() {
        stopCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.recalculateFromWallClock()
            }
        }
    }

    private func processTick() {
        guard var engine else { return }

        let result = engine.tick(
            elapsed: elapsed,
            totalDuration: sessionTotalDuration,
            baseStrength: strength
        )
        self.engine = engine

        // Send BLE commands
        if ble.isConnected, !result.commands.isEmpty {
            ble.sendCommands(result.commands)
        }

        // Update published state
        stimulationActive = result.isStimulationActive
        effectiveStrength = result.effectiveStrength
        breathingPhase = result.breathingPhase
        activeChannel = result.activeChannel
        modeStatus = result.statusText
    }

    private func stopCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
    }

    private nonisolated func sendKeepalive() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.isRunning, self.ble.isConnected else { return }
            guard self.stimulationActive else { return }
            let s = self.effectiveStrength ?? self.strength
            self.ble.sendCommand(BLEConstants.strengthCommand(s))
        }
    }

    private func startKeepalive() {
        stopKeepalive()
        let source = DispatchSource.makeTimerSource(queue: .global())
        source.schedule(deadline: .now() + BLEConstants.keepaliveInterval,
                        repeating: BLEConstants.keepaliveInterval)
        source.setEventHandler { [weak self] in
            self?.sendKeepalive()
        }
        source.resume()
        keepaliveSource = source
    }

    private func stopKeepalive() {
        keepaliveSource?.cancel()
        keepaliveSource = nil
    }

    private func startStatusPoll() {
        stopStatusPoll()
        statusPollTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.statusPollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.queryStatus()
            }
        }
    }

    private func stopStatusPoll() {
        statusPollTimer?.invalidate()
        statusPollTimer = nil
    }

    private func queryStatus() {
        ble.sendCommand(BLEConstants.batteryQueryCommand)
        ble.sendCommand(BLEConstants.chargingQueryCommand)
    }

    // MARK: - Reconnection

    private func handleDisconnect() {
        stopKeepalive()
        stopStatusPoll()
        // Session keeps running — countdown continues
        // BLE manager owns reconnection via scheduleRetry()
    }

    private func resumeSessionOnDevice() {
        guard isRunning, remainingSeconds > 0 else { return }

        if let engine {
            let cmds = engine.reconnectCommands(
                elapsed: elapsed,
                totalDuration: sessionTotalDuration,
                baseStrength: strength
            )
            ble.sendCommands(cmds)
        } else {
            // Custom mode
            ble.sendCommands([BLEConstants.activateCommand, BLEConstants.strengthCommand(strength)])
        }

        startKeepalive()
    }

    // MARK: - Session Persistence

    let defaults: UserDefaults
    private enum PersistKey {
        static let startDate = "session.startDate"
        static let totalDuration = "session.totalDuration"
        static let pauseTime = "session.accumulatedPauseTime"
        static let pauseStartDate = "session.pauseStartDate"
        static let isPaused = "session.isPaused"
        static let mode = "session.mode"
        static let feeling = "session.feeling"
        static let strength = "session.strength"
    }

    private func persistSession() {
        let d = defaults
        d.set(sessionStartDate?.timeIntervalSince1970, forKey: PersistKey.startDate)
        d.set(sessionTotalDuration, forKey: PersistKey.totalDuration)
        d.set(accumulatedPauseTime, forKey: PersistKey.pauseTime)
        d.set(pauseStartDate?.timeIntervalSince1970, forKey: PersistKey.pauseStartDate)
        d.set(isPaused, forKey: PersistKey.isPaused)
        d.set(selectedMode.rawValue, forKey: PersistKey.mode)
        d.set(selectedFeeling?.rawValue, forKey: PersistKey.feeling)
        d.set(strength, forKey: PersistKey.strength)
    }

    private func clearPersistedSession() {
        let d = defaults
        for key in [PersistKey.startDate, PersistKey.totalDuration, PersistKey.pauseTime,
                    PersistKey.pauseStartDate, PersistKey.isPaused, PersistKey.mode,
                    PersistKey.feeling, PersistKey.strength] {
            d.removeObject(forKey: key)
        }
    }

    private func restoreSessionIfNeeded() {
        let d = defaults
        guard let startTimestamp = d.object(forKey: PersistKey.startDate) as? TimeInterval else { return }

        let startDate = Date(timeIntervalSince1970: startTimestamp)
        let totalDuration = d.integer(forKey: PersistKey.totalDuration)
        guard totalDuration > 0 else { clearPersistedSession(); return }

        let pauseTime = d.double(forKey: PersistKey.pauseTime)
        let wasPaused = d.bool(forKey: PersistKey.isPaused)

        // Restore mode/feeling
        if let modeRaw = d.string(forKey: PersistKey.mode),
           let mode = StimulationMode(rawValue: modeRaw) {
            selectedMode = mode
        }
        if let feelingRaw = d.string(forKey: PersistKey.feeling),
           let feeling = AutonomicState(rawValue: feelingRaw) {
            selectedFeeling = feeling
        }
        strength = d.integer(forKey: PersistKey.strength)
        if strength == 0 { strength = 5 }

        // Restore wall-clock state
        sessionStartDate = startDate
        sessionTotalDuration = totalDuration
        accumulatedPauseTime = pauseTime

        if wasPaused {
            // Restore paused state — accumulate time from pause start to now
            if let pauseTimestamp = d.object(forKey: PersistKey.pauseStartDate) as? TimeInterval {
                pauseStartDate = Date(timeIntervalSince1970: pauseTimestamp)
            } else {
                pauseStartDate = Date()
            }
            // Recalculate remaining without the current pause duration
            let totalElapsed = Date().timeIntervalSince(startDate)
            let activeElapsed = totalElapsed - pauseTime - Date().timeIntervalSince(pauseStartDate ?? Date())
            let remaining = max(0, totalDuration - Int(activeElapsed))
            if remaining <= 0 {
                clearPersistedSession()
                return
            }
            remainingSeconds = remaining
            isPaused = true
            isRunning = false
            engine = selectedMode.makeEngine()
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            // Restore running state — recalculate from wall clock
            let totalElapsed = Date().timeIntervalSince(startDate)
            let activeElapsed = totalElapsed - pauseTime
            let remaining = max(0, totalDuration - Int(activeElapsed))
            if remaining <= 0 {
                clearPersistedSession()
                return
            }
            remainingSeconds = remaining
            isRunning = true
            engine = selectedMode.makeEngine()
            // Start the engine so its internal state is initialized
            if var engine {
                _ = engine.start(baseStrength: strength, totalDuration: totalDuration)
                self.engine = engine
            }
            UIApplication.shared.isIdleTimerDisabled = true
            stimulationActive = true

            // Catch up engine state to current elapsed
            processTick()

            startCountdown()
            startKeepalive()
        }
    }
}

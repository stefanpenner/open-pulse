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
        return Double(remainingSeconds) / Double(sessionTotalDuration)
    }

    private var countdownTimer: Timer?
    private var keepaliveTimer: Timer?
    private var statusPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private var engine: ModeEngine?
    private var sessionTotalDuration = 0
    private var elapsed: Int { sessionTotalDuration - remainingSeconds }

    init() {
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
        guard ble.isReady else { return }

        isRunning = true
        sessionTotalDuration = timerMinutes * 60
        remainingSeconds = sessionTotalDuration
        UIApplication.shared.isIdleTimerDisabled = true

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
            modeStatus = "Bilateral · Continuous"
        }

        startCountdown()
        startKeepalive()
    }

    func stop() {
        isRunning = false
        isPaused = false
        remainingSeconds = 0
        sessionTotalDuration = 0
        UIApplication.shared.isIdleTimerDisabled = false

        // Clear engine state
        engine = nil
        stimulationActive = false
        effectiveStrength = nil
        breathingPhase = nil
        activeChannel = .off
        modeStatus = ""

        stopCountdown()
        stopKeepalive()

        if ble.isConnected {
            ble.sendCommand(BLEConstants.deactivateCommand)
            queryStatus()
        }
    }

    func pause() {
        guard isRunning else { return }
        isPaused = true
        isRunning = false

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
    }

    func resume() {
        guard isPaused, ble.isReady else { return }
        isPaused = false
        isRunning = true

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
    }

    func scan() {
        ble.scan()
    }

    func stopScan() {
        ble.stopScan()
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
        guard !isRunning, !isPaused else { return }
        timerMinutes += 1
    }

    func decreaseTimer() {
        guard !isRunning, !isPaused, timerMinutes > 1 else { return }
        timerMinutes -= 1
    }

    func setStrength(_ value: Int) {
        let clamped = max(1, min(9, value))
        strength = clamped
        guard isRunning, ble.isConnected, stimulationActive else { return }
        ble.sendCommand(BLEConstants.strengthCommand(clamped))
    }

    // MARK: - Timers

    private func startCountdown() {
        stopCountdown()
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.remainingSeconds <= 1 {
                    self.stop()
                } else {
                    self.remainingSeconds -= 1
                    self.processTick()
                }
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

    private func startKeepalive() {
        stopKeepalive()
        keepaliveTimer = Timer.scheduledTimer(withTimeInterval: BLEConstants.keepaliveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.ble.isConnected else { return }
                guard self.stimulationActive else { return }
                let s = self.effectiveStrength ?? self.strength
                self.ble.sendCommand(BLEConstants.strengthCommand(s))
            }
        }
    }

    private func stopKeepalive() {
        keepaliveTimer?.invalidate()
        keepaliveTimer = nil
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
        Task {
            try? await Task.sleep(for: .seconds(BLEConstants.reconnectDelay))
            ble.scan()
        }
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
}

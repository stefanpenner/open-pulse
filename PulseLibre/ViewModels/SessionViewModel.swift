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
    @Published var stimulationActive = false
    @Published var effectiveStrength: Int? = nil
    @Published var breathingPhase: BreathingPhase? = nil
    @Published var modeStatus: String = ""

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
        timerMinutes = mode.defaultDurationMinutes
        strength = mode.defaultStrength
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
            for cmd in cmds {
                ble.sendCommand(cmd)
            }
            // Set initial state from engine
            stimulationActive = true
            if selectedMode == .calm {
                // Calm starts with inhale (stim off)
                stimulationActive = false
                breathingPhase = .inhale(progress: 0)
                modeStatus = "Inhale · Paused"
            } else {
                modeStatus = "Starting"
            }
        } else {
            // Custom mode: original behavior
            ble.sendCommand(BLEConstants.activateCommand)
            ble.sendCommand(BLEConstants.strengthCommand(strength))
            stimulationActive = true
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
            for cmd in cmds {
                ble.sendCommand(cmd)
            }
        } else {
            ble.sendCommand(BLEConstants.activateCommand)
            ble.sendCommand(BLEConstants.strengthCommand(strength))
        }

        stimulationActive = true
        startCountdown()
        startKeepalive()
    }

    func scan() {
        ble.scan()
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
        if isRunning, ble.isConnected, stimulationActive {
            ble.sendCommand(BLEConstants.strengthCommand(clamped))
        }
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
        if ble.isConnected {
            for cmd in result.commands {
                ble.sendCommand(cmd)
            }
        }

        // Update published state
        stimulationActive = result.isStimulationActive
        effectiveStrength = result.effectiveStrength
        breathingPhase = result.breathingPhase
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
            for cmd in cmds {
                ble.sendCommand(cmd)
            }
        } else {
            // Custom mode
            ble.sendCommand(BLEConstants.activateCommand)
            ble.sendCommand(BLEConstants.strengthCommand(strength))
        }

        startKeepalive()
    }
}

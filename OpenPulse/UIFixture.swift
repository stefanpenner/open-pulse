import SwiftUI

/// Screen states for UI review. Launch with `-uiState <name>` in a Debug build.
/// A Release build has no fixture: `current` is always nil.
enum UIFixture: String, CaseIterable {
    case idle, bluetoothOff, running, paused, settings, history, mode

    enum Sheet { case settings, history, mode }

    static let current: UIFixture? = {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-uiState"), i + 1 < args.count else { return nil }
        return UIFixture(rawValue: args[i + 1])
        #else
        return nil
        #endif
    }()

    var sheet: Sheet? {
        switch self {
        case .settings: .settings
        case .history: .history
        case .mode: .mode
        default: nil
        }
    }

    /// A view model on a fake device and a clean, throwaway defaults suite.
    @MainActor
    func makeViewModel() -> SessionViewModel {
        let defaults = UserDefaults(suiteName: "ui-fixture")!
        defaults.removePersistentDomain(forName: "ui-fixture")
        seedHistory(defaults)
        let vm = SessionViewModel(
            defaults: defaults,
            ble: FixtureDevice(bluetoothOff: self == .bluetoothOff),
            ambientAudio: NullAmbientAudio()
        )
        if self == .running || self == .paused { vm.start() }
        if self == .paused { vm.pause() }
        return vm
    }

    private func seedHistory(_ defaults: UserDefaults) {
        let day: TimeInterval = 86_400
        let rows: [(StimulationMode, Int, TimeInterval)] = [
            (.stressRelief, 360, -2 * day), (.sleep, 600, -day), (.stressRelief, 240, -3_600),
        ]
        for (mode, seconds, offset) in rows {
            SessionHistory.append(
                mode: mode, durationSeconds: seconds, strength: 5, completed: true,
                defaults: defaults, now: Date().addingTimeInterval(offset)
            )
        }
    }
}

/// A device that is always linked and ready, or Bluetooth off. It confirms every write and sends nothing.
@MainActor
private final class FixtureDevice: DeviceState {
    init(bluetoothOff: Bool) {
        super.init()
        isBluetoothOff = bluetoothOff
        guard !bluetoothOff else { return }
        isConnected = true
        isReady = true
        batteryPercentage = 80
        batterySampleConfirmed = true
        linkQuality = .good
        deviceName = "Pulsetto"
        firmwareVersion = "1.0"
    }

    /// Confirm each write on the next main-actor turn, as a real link does.
    override func sendCommand(_ command: String) {
        super.sendCommand(command)
        Task { @MainActor [weak self] in self?.onWriteSucceeded?(command) }
    }
}

import Foundation
import Combine

/// Shared BLE link surface for production (`BluetoothManager`) and tests (`MockDeviceTransport`).
/// Views keep reading `vm.ble.*`; inject any subclass into `SessionViewModel`.
@MainActor
class DeviceState: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var isReady = false
    @Published var batteryPercentage: Int?
    @Published var batteryVoltage: Double?
    @Published var isCharging: Bool?
    @Published var isBluetoothOff = false
    /// True after a Batt: reply on the current link. Cached % after disconnect is unconfirmed.
    @Published var batterySampleConfirmed = false

    var onDisconnect: (@MainActor () -> Void)?
    var onCommandSent: ((String) -> Void)?
    var onNotification: (@MainActor () -> Void)?
    var onWriteFailed: (@MainActor (String) -> Void)?
    var onWriteSucceeded: (@MainActor (String) -> Void)?

    /// True while a withResponse write is in-flight or queued.
    var hasPendingWrites: Bool { false }

    /// True while channel/strength program traffic is outstanding (excludes status queries).
    var hasPendingProgramWrites: Bool { false }

    func sendCommand(_ command: String) {
        onCommandSent?(command)
    }

    func sendCommands(_ commands: [String]) {
        for cmd in commands {
            sendCommand(cmd)
        }
    }

    /// Drop waiting non-deactivate commands. Never abandons in-flight withResponse.
    func cancelProgramWrites() {}
}

extension DeviceState: DeviceTransport {}

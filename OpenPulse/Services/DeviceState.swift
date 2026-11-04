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
    /// Signal level from RSSI reads on the current link. Nil when no link.
    @Published var linkQuality: LinkQuality?

    /// Last known from the `v` and `i` replies. Kept after a disconnect: the device is the same
    /// paired unit, and the footer only shows identity. The next link overwrites them.
    @Published var firmwareVersion: String?
    @Published var deviceName: String?

    /// Last "mode:" the pack reported on this link. Nil until seen; cleared on disconnect.
    @Published var deviceMode: DeviceMode?

    var onModeReport: (@MainActor (DeviceMode) -> Void)?
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

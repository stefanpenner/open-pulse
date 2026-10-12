import Foundation

/// Abstraction over BLE command delivery for testability and SessionBLE layering.
/// Concrete inject type: `DeviceState` (`BluetoothManager` / `MockDeviceTransport`).
@MainActor
protocol DeviceTransport: AnyObject {
    var isConnected: Bool { get }
    var isReady: Bool { get }
    var isBluetoothOff: Bool { get }
    /// True while a withResponse write is in-flight or queued.
    var hasPendingWrites: Bool { get }
    /// True while channel/strength program traffic is still outstanding (excludes status queries).
    var hasPendingProgramWrites: Bool { get }
    func sendCommand(_ command: String)
    func sendCommands(_ commands: [String])
    /// Drop queued non-deactivate commands (safety off path). Never abandons in-flight write.
    func cancelProgramWrites()
}

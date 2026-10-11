@preconcurrency import CoreBluetooth

enum BLEConstants {
    // Nordic UART Service
    nonisolated(unsafe) static let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let uartRXCharUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Write
    nonisolated(unsafe) static let uartTXCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Notify

    // Device discovery
    static let deviceNamePrefix = "Pulsetto"
    static let scanTimeout: TimeInterval = 10

    /// CoreBluetooth state restoration ID (must stay stable across launches).
    /// Lets iOS relaunch/reattach after jetsam while a session may still be open.
    static let centralRestoreIdentifier = "io.github.stefanpenner.OpenPulse.central"

    // Battery voltage thresholds
    static let batteryFullVoltage: Double = 3.95
    static let batteryEmptyVoltage: Double = 2.5

    // Intervals
    static let keepaliveInterval: TimeInterval = 10
    static let statusPollInterval: TimeInterval = 30
    static let reconnectDelay: TimeInterval = 1
    static let scanRetryDelay: TimeInterval = 3

    /// Hard ceiling for any session (wellness safety / battery comfort).
    static let maxSessionMinutes = 60
    /// Battery % at/below which UI warns the user.
    static let lowBatteryThresholdPercent = 15

    // Commands (verified on device)
    // 0 = off, A = left only, B = ramp-up to intensity, C = right only, D = bilateral
    static let activateCommand = "D\n"       // bilateral
    static let leftChannelCommand = "A\n"    // left only
    static let rightChannelCommand = "C\n"   // right only
    static let rampCommand = "B\n"           // gradual ramp to set intensity
    static let deactivateCommand = "0\n"
    static let batteryQueryCommand = "Q\n"
    static let chargingQueryCommand = "u\n"

    /// Clamps to device range 1…9 before formatting.
    static func strengthCommand(_ level: Int) -> String {
        let clamped = max(1, min(9, level))
        return "\(clamped)\n"
    }

    // Battery calculation
    static func batteryPercentage(fromVoltage voltage: Double) -> Int {
        if voltage >= batteryFullVoltage { return 100 }
        if voltage <= batteryEmptyVoltage { return 0 }
        return Int(((voltage - batteryEmptyVoltage) / (batteryFullVoltage - batteryEmptyVoltage)) * 100)
    }
}

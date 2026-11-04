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
    // Official Pulsetto app curve (PulseLibre App.js, pulse-libre-desktop main.py):
    // 3.5 V = 0 %, 3.9 V = 100 %, linear between.
    static let batteryFullVoltage: Double = 3.9
    static let batteryEmptyVoltage: Double = 3.5
    /// Below this the pack is dead and reads 0 %. Between this and
    /// `batteryEmptyVoltage` the pack is low but usable and reads 1 %.
    static let batteryDeadVoltage: Double = 3.4

    // Intervals
    static let keepaliveInterval: TimeInterval = 10
    static let statusPollInterval: TimeInterval = 30
    static let reconnectDelay: TimeInterval = 1
    static let scanRetryDelay: TimeInterval = 3

    /// Hard ceiling for any session (wellness safety / battery comfort).
    static let maxSessionMinutes = 60

    // Commands (verified on device)
    // 0 = off, A = left only, B = ramp-up to intensity, C = right only, D = bilateral
    static let activateCommand = "D\n"       // bilateral
    static let leftChannelCommand = "A\n"    // left only
    static let rightChannelCommand = "C\n"   // right only
    static let rampCommand = "B\n"           // gradual ramp to set intensity
    static let deactivateCommand = "0\n"
    static let batteryQueryCommand = "Q\n"
    static let chargingQueryCommand = "u\n"
    static let firmwareQueryCommand = "v\n"     // reply "fw:1.1.22"
    static let deviceNameQueryCommand = "i\n"   // reply "Pulsetto_ST_02"

    /// Clamps to device range 1…9 before formatting.
    static func strengthCommand(_ level: Int) -> String {
        "\(StrengthPresentation.clamp(level))\n"
    }

    /// Pure voltage-to-percent map. Linear 3.5…3.9 V, clamped to 0…100.
    /// 0 means dead (below 3.4 V) and blocks Start, so a usable pack at
    /// 3.4…3.5 V floors at 1.
    static func batteryPercentage(fromVoltage voltage: Double) -> Int {
        if voltage >= batteryFullVoltage { return 100 }
        if voltage < batteryDeadVoltage { return 0 }
        let span = batteryFullVoltage - batteryEmptyVoltage
        let linear = Int((((voltage - batteryEmptyVoltage) / span) * 100).rounded())
        return max(1, linear)
    }
}

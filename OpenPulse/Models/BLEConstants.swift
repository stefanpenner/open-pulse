@preconcurrency import CoreBluetooth

enum BLEConstants {
    // Nordic UART Service
    nonisolated(unsafe) static let uartServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    nonisolated(unsafe) static let uartRXCharUUID  = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E") // Write
    nonisolated(unsafe) static let uartTXCharUUID  = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E") // Notify

    // Device discovery
    static let deviceNamePrefix = "Pulsetto"
    static let scanTimeout: TimeInterval = 10

    // Battery voltage thresholds
    static let batteryFullVoltage: Double = 3.95
    static let batteryEmptyVoltage: Double = 2.5

    // Intervals
    static let keepaliveInterval: TimeInterval = 10
    static let statusPollInterval: TimeInterval = 30
    static let reconnectDelay: TimeInterval = 1

    // Commands
    static let activateCommand = "D\n"       // bilateral
    static let leftChannelCommand = "A\n"    // left only
    static let rightChannelCommand = "C\n"   // right only
    static let deactivateCommand = "0\n"
    static let batteryQueryCommand = "Q\n"
    static let chargingQueryCommand = "u\n"

    static func strengthCommand(_ level: Int) -> String {
        "\(level)\n"
    }

    // Battery calculation
    static func batteryPercentage(fromVoltage voltage: Double) -> Int {
        if voltage >= batteryFullVoltage { return 100 }
        if voltage <= batteryEmptyVoltage { return 0 }
        return Int(((voltage - batteryEmptyVoltage) / (batteryFullVoltage - batteryEmptyVoltage)) * 100)
    }
}

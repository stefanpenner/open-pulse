import Foundation
@testable import OpenPulse

/// In-memory `DeviceState` for unit tests (no CoreBluetooth).
@MainActor
final class MockDeviceTransport: DeviceState {
    private(set) var commands: [String] = []
    private(set) var cancelProgramWritesCount = 0
    private var pendingWrites = false
    private var pendingProgramWrites = false

    override init() {
        super.init()
        // Known pack by default — Start-gate grace must not block unrelated tests
        batteryPercentage = 80
        batterySampleConfirmed = true
    }

    override var hasPendingWrites: Bool { pendingWrites }
    override var hasPendingProgramWrites: Bool { pendingProgramWrites }

    override func sendCommand(_ command: String) {
        onCommandSent?(command)
        commands.append(command)
    }

    override func sendCommands(_ commands: [String]) {
        for cmd in commands {
            sendCommand(cmd)
        }
    }

    override func cancelProgramWrites() {
        cancelProgramWritesCount += 1
        commands.removeAll { $0 != BLEConstants.deactivateCommand && !$0.hasPrefix("0") }
    }

    func setPendingProgramWrites(_ value: Bool) {
        pendingProgramWrites = value
        pendingWrites = value || pendingWrites
    }

    func setPendingWrites(_ value: Bool) {
        pendingWrites = value
    }

    /// Simulate withResponse completion for pending-off / safety tests.
    func completeWrite(_ command: String, success: Bool = true) {
        if success {
            onWriteSucceeded?(command)
        } else {
            onWriteFailed?(command)
        }
    }

    /// Raise ready edge (fires `@Published` → VM ready sink).
    /// Default confirms battery so session Start tests stay green; pass `false` to test first-Q gate.
    func becomeReady(confirmBattery: Bool = true) {
        isBluetoothOff = false
        isConnected = true
        batterySampleConfirmed = confirmBattery
        isReady = true
    }

    /// Clear command log only (keeps ready/connected for mid-test assertions).
    func reset() {
        commands = []
        cancelProgramWritesCount = 0
    }
}

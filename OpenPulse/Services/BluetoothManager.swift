import Foundation
@preconcurrency import CoreBluetooth
import os

@MainActor
final class BluetoothManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var isScanning = false
    @Published var isReady = false
    @Published var batteryPercentage: Int?
    @Published var batteryVoltage: Double?
    @Published var isCharging: Bool?

    var onDisconnect: (@MainActor () -> Void)?
    var onCommandSent: ((String) -> Void)?

    private let logger = Logger(subsystem: "io.github.stefanpenner.OpenPulse", category: "BLE")
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    private var scanTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    func scan() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan — Bluetooth not powered on")
            return
        }
        guard !isScanning, !isConnected else { return }

        logger.info("Starting scan...")
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(BLEConstants.scanTimeout))
            guard !Task.isCancelled, let self, self.isScanning else { return }
            self.logger.info("Scan timed out")
            self.stopScan()
        }
    }

    func disconnect() {
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    func sendCommand(_ command: String) {
        onCommandSent?(command)
        guard let peripheral, let rxCharacteristic,
              let data = command.data(using: .utf8) else {
            logger.warning("Cannot send — not ready")
            return
        }
        peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)
        logger.debug("Sent: \(command.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    // MARK: - Private

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
    }

    private func cleanup() {
        rxCharacteristic = nil
        peripheral = nil
        isConnected = false
        isReady = false
        batteryPercentage = nil
        batteryVoltage = nil
        isCharging = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            logger.info("Bluetooth state: \(central.state.rawValue)")
            if central.state == .poweredOn {
                scan()
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        Task { @MainActor in
            guard let name = peripheral.name,
                  name.hasPrefix(BLEConstants.deviceNamePrefix) else { return }

            logger.info("Found device: \(name)")
            stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            logger.info("Connected to \(peripheral.name ?? "unknown")")
            isConnected = true
            peripheral.discoverServices([BLEConstants.uartServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
            cleanup()
            try? await Task.sleep(for: .seconds(BLEConstants.reconnectDelay))
            scan()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.info("Disconnected: \(error?.localizedDescription ?? "clean")")
            cleanup()
            onDisconnect?()
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.uartServiceUUID }) else {
                logger.error("UART service not found")
                return
            }
            peripheral.discoverCharacteristics(
                [BLEConstants.uartRXCharUUID, BLEConstants.uartTXCharUUID],
                for: service
            )
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard let characteristics = service.characteristics else { return }

            for char in characteristics {
                if char.uuid == BLEConstants.uartRXCharUUID {
                    rxCharacteristic = char
                    logger.info("RX characteristic found")
                } else if char.uuid == BLEConstants.uartTXCharUUID {
                    peripheral.setNotifyValue(true, for: char)
                    logger.info("TX characteristic found, subscribing")
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == BLEConstants.uartTXCharUUID, error == nil else {
                logger.error("Notification subscription failed: \(error?.localizedDescription ?? "unknown")")
                return
            }
            logger.info("TX notifications active")
            guard rxCharacteristic != nil else { return }
            isReady = true
            sendCommand(BLEConstants.batteryQueryCommand)
            try? await Task.sleep(for: .milliseconds(200))
            sendCommand(BLEConstants.chargingQueryCommand)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEConstants.uartTXCharUUID,
              let data = characteristic.value else { return }

        let bytes = [UInt8](data)

        // Charging status: [0x75, 0x01, 0x30/0x31]
        if bytes.count >= 3, bytes[0] == 0x75, bytes[1] == 0x01 {
            let charging = bytes[2] == 0x31
            Task { @MainActor in
                self.isCharging = charging
            }
            return
        }

        // Battery response: "Batt: 3.95" or "Batt:3.95V"
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           str.hasPrefix("Batt:") {
            let raw = str.replacingOccurrences(of: "Batt:", with: "").trimmingCharacters(in: .whitespaces)
            // Extract leading numeric portion (like JS parseFloat)
            let numericChars = raw.prefix(while: { $0.isNumber || $0 == "." })
            if let voltage = Double(numericChars), voltage > 0 {
                let pct = BLEConstants.batteryPercentage(fromVoltage: voltage)
                Task { @MainActor in
                    self.batteryVoltage = voltage
                    self.batteryPercentage = pct
                }
            }
        }
    }
}

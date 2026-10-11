import Foundation
@preconcurrency import CoreBluetooth
import os

/// Bridges non-Sendable CoreBluetooth values across isolation (queue is `.main`).
private struct BLEUncheckedBox<T>: @unchecked Sendable {
    let value: T
}

@MainActor
final class BluetoothManager: DeviceState {
    private let logger = Logger(subsystem: "io.github.stefanpenner.OpenPulse", category: "BLE")
    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?
    /// Pure single-flight queue (see `SerialBLEWriteQueue` / BLEWriteQueue.tla).
    private var serialQueue = SerialBLEWriteQueue()
    /// Invalidates stale didWrite after cleanup (does not rely on abandoned callbacks arriving).
    private var writeFence = WriteEpochFence()
    private var scanTimeoutTask: Task<Void, Never>?
    private var autoScanTask: Task<Void, Never>?
    private var scanWhenReady = false
    private var retryCount = 0
    private var intentionalDisconnect = false
    private var connectTimeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        // State restoration: re-attach UART after jetsam so pending-off / session
        // reassert can run (Session.tla KillRestoreExpire + bluetooth-central).
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.centralRestoreIdentifier
            ]
        )
    }

    // MARK: - Public API

    func scan() {
        guard !isScanning, !isConnected else { return }

        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan — Bluetooth not powered on, will scan when ready")
            scanWhenReady = true
            isBluetoothOff = centralManager.state != .unknown
            return
        }

        logger.info("Starting scan...")
        scanWhenReady = false
        isBluetoothOff = false
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(BLEConstants.scanTimeout))
            guard !Task.isCancelled, let self, self.isScanning else { return }
            self.logger.info("Scan timed out, will retry (attempt \(self.retryCount + 1))")
            self.stopScan()
            self.scheduleRetry()
        }
    }

    func disconnect() {
        intentionalDisconnect = true
        if let peripheral {
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    override func sendCommand(_ command: String) {
        // Notify first so unit tests can observe intent without a live peripheral.
        onCommandSent?(command)
        guard peripheral != nil, rxCharacteristic != nil else {
            logger.warning("Cannot send — not ready")
            return
        }
        serialQueue.enqueue(command)
        pumpWriteQueue()
    }

    /// Drop waiting program/status cmds before a safety off.
    /// Never abandons in-flight withResponse — CB single-flight (BLEWriteQueue.tla).
    override func cancelProgramWrites() {
        serialQueue.cancelProgramWrites()
    }

    override func sendCommands(_ commands: [String]) {
        guard !commands.isEmpty else { return }
        for cmd in commands {
            sendCommand(cmd)
        }
    }

    private func pumpWriteQueue() {
        guard let peripheral, let rxCharacteristic else {
            writeFence.invalidate()
            serialQueue.clear()
            return
        }
        guard let command = serialQueue.beginWrite() else { return }
        guard let data = command.data(using: .utf8) else {
            _ = serialQueue.finishWrite()
            writeFence.finish()
            pumpWriteQueue()
            return
        }
        writeFence.beginWrite()
        peripheral.writeValue(data, for: rxCharacteristic, type: .withResponse)
        logger.debug("Sent: \(command.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    private func clearWriteQueue() {
        // Invalidate first so any late didWrite cannot finish a post-reconnect write
        writeFence.invalidate()
        serialQueue.clear()
    }

    override var hasPendingWrites: Bool {
        serialQueue.hasPending
    }

    override var hasPendingProgramWrites: Bool {
        serialQueue.hasPendingProgramWrites
    }

    // MARK: - Private

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
    }

    func stopAutoScan() {
        stopScan()
        autoScanTask?.cancel()
        autoScanTask = nil
        retryCount = 0
    }

    private func scheduleRetry() {
        autoScanTask?.cancel()
        retryCount += 1
        let delay = retryCount <= 1 ? 0.0 : min(Double(retryCount) * BLEConstants.scanRetryDelay, 10.0)
        autoScanTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            self.scan()
        }
    }

    private func cleanup() {
        clearWriteQueue()
        // Drop delegate so late CB callbacks cannot finish a new session's in-flight write
        peripheral?.delegate = nil
        rxCharacteristic = nil
        peripheral = nil
        isConnected = false
        isReady = false
        // Keep last battery % for empty-state honesty while searching
        // Sample is stale until next Batt: on the new link
        batterySampleConfirmed = false
        // Clear charge truth — stale "charging" must not bypass empty start gate after reconnect
        isCharging = nil
        batteryVoltage = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    nonisolated func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        // CBCentralManager was created with queue: .main, so this callback is on main.
        // CoreBluetooth types are not Sendable — box for the isolation boundary.
        let box = BLEUncheckedBox(
            value: dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        )
        MainActor.assumeIsolated {
            self.handleRestoredPeripherals(box.value)
        }
    }

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            logger.info("Bluetooth state: \(central.state.rawValue)")
            let poweredOn = central.state == .poweredOn
            isBluetoothOff = !poweredOn
            if poweredOn {
                // Do not clobber a restored/connecting peripheral with a fresh scan
                if self.peripheral == nil {
                    scan()
                }
            } else {
                // Tear down stale ready/connected so UI never shows Connected while BT is off
                stopScan()
                connectTimeoutTask?.cancel()
                connectTimeoutTask = nil
                let hadLink = isConnected || isReady || peripheral != nil
                cleanup()
                // Radio off — drop last pack reading (cache is only for mid-search honesty)
                batteryPercentage = nil
                isCharging = nil
                if hadLink {
                    onDisconnect?()
                }
            }
        }
    }

    /// Re-bind UART after iOS relaunches the app for bluetooth-central restore.
    @MainActor
    private func handleRestoredPeripherals(_ peripherals: [CBPeripheral]) {
        guard !peripherals.isEmpty else {
            logger.info("BLE restore: no peripherals in state")
            return
        }
        // Prefer named Pulsetto; otherwise first restored peripheral
        let match = peripherals.first(where: { name in
            let n = name.name ?? ""
            return n.hasPrefix(BLEConstants.deviceNamePrefix)
        }) ?? peripherals.first
        guard let match else { return }

        logger.info("BLE restore: reattaching \(match.name ?? match.identifier.uuidString)")
        stopScan()
        scanWhenReady = false
        peripheral = match
        match.delegate = self
        intentionalDisconnect = false

        switch match.state {
        case .connected:
            isConnected = true
            retryCount = 0
            match.discoverServices([BLEConstants.uartServiceUUID])
            armConnectTimeout()
        case .connecting:
            isConnected = false
            armConnectTimeout()
        case .disconnected, .disconnecting:
            isConnected = false
            isReady = false
            centralManager.connect(match, options: nil)
            armConnectTimeout()
        @unknown default:
            centralManager.connect(match, options: nil)
            armConnectTimeout()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                     advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Extract name before MainActor hop (Swift 6: advertisementData is not Sendable).
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let peripheralName = peripheral.name
        let name = advertised ?? peripheralName
        guard let name, name.hasPrefix(BLEConstants.deviceNamePrefix) else { return }

        Task { @MainActor in
            // Avoid multi-connect race: ignore further discoveries while connecting.
            guard self.peripheral == nil, !self.isConnected else { return }

            logger.info("Found device: \(name)")
            stopScan()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
            self.armConnectTimeout()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            logger.info("Connected to \(peripheral.name ?? "unknown")")
            // Keep timeout armed until isReady — hang in GATT discovery must still recover
            isConnected = true
            retryCount = 0
            autoScanTask?.cancel()
            autoScanTask = nil
            peripheral.discoverServices([BLEConstants.uartServiceUUID])
            armConnectTimeout()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown")")
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            cleanup()
            scheduleRetry()
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            logger.info("Disconnected: \(error?.localizedDescription ?? "clean")")
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            let wasIntentional = intentionalDisconnect
            intentionalDisconnect = false
            cleanup()
            onDisconnect?()
            if !wasIntentional {
                scheduleRetry()
            }
        }
    }

    /// Avoid stuck connecting forever when peripheral never completes handshake.
    private func armConnectTimeout() {
        connectTimeoutTask?.cancel()
        connectTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(BLEConstants.scanTimeout))
            guard !Task.isCancelled, let self else { return }
            guard !self.isReady else { return }
            self.logger.warning("Connect/handshake timed out — retrying")
            if let peripheral = self.peripheral {
                self.intentionalDisconnect = false
                self.centralManager.cancelPeripheralConnection(peripheral)
            } else {
                self.cleanup()
                self.scheduleRetry()
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard let service = peripheral.services?.first(where: { $0.uuid == BLEConstants.uartServiceUUID }) else {
                logger.error("UART service not found — disconnecting to retry")
                // Stuck "Connected / not ready" is worse than a clean retry.
                intentionalDisconnect = false
                centralManager.cancelPeripheralConnection(peripheral)
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
            if let error {
                logger.error("Characteristic discovery failed: \(error.localizedDescription)")
                intentionalDisconnect = false
                centralManager.cancelPeripheralConnection(peripheral)
                return
            }
            guard let characteristics = service.characteristics else {
                intentionalDisconnect = false
                centralManager.cancelPeripheralConnection(peripheral)
                return
            }

            var txChar: CBCharacteristic?
            for char in characteristics {
                if char.uuid == BLEConstants.uartRXCharUUID {
                    rxCharacteristic = char
                    logger.info("RX characteristic found")
                } else if char.uuid == BLEConstants.uartTXCharUUID {
                    txChar = char
                    // Restore footgun: notify may already be on — setNotify may not re-callback
                    if char.isNotifying {
                        logger.info("TX already notifying (restore) — marking ready")
                    } else {
                        peripheral.setNotifyValue(true, for: char)
                        logger.info("TX characteristic found, subscribing")
                    }
                }
            }

            if rxCharacteristic == nil {
                logger.error("RX characteristic missing — disconnecting to retry")
                intentionalDisconnect = false
                centralManager.cancelPeripheralConnection(peripheral)
                return
            }

            // CB restore: isNotifying already true → no didUpdateNotificationState
            if let tx = txChar, tx.isNotifying, !isReady {
                batterySampleConfirmed = false
                isReady = true
                connectTimeoutTask?.cancel()
                connectTimeoutTask = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    guard self.isReady else { return }
                    self.sendCommand(BLEConstants.batteryQueryCommand)
                    self.sendCommand(BLEConstants.chargingQueryCommand)
                }
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard characteristic.uuid == BLEConstants.uartTXCharUUID else { return }
            if let error {
                logger.error("Notification subscription failed: \(error.localizedDescription)")
                intentionalDisconnect = false
                centralManager.cancelPeripheralConnection(peripheral)
                return
            }
            logger.info("TX notifications active")
            guard rxCharacteristic != nil else {
                intentionalDisconnect = false
                centralManager.cancelPeripheralConnection(peripheral)
                return
            }
            // Fresh link — cached % is unconfirmed until Batt: reply
            batterySampleConfirmed = false
            isReady = true
            connectTimeoutTask?.cancel()
            connectTimeoutTask = nil
            // Delay status queries so session safety (off / reconnect program) can enqueue first
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                guard self.isReady else { return }
                self.sendCommand(BLEConstants.batteryQueryCommand)
                self.sendCommand(BLEConstants.chargingQueryCommand)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEConstants.uartRXCharUUID else { return }
        // Capture before the hop. A later beginWrite must not adopt this callback.
        // Central queue is .main, so the fence read is on the main actor.
        let stamp = MainActor.assumeIsolated { self.writeFence.issuedStamp }
        Task { @MainActor in
            // Ignore stale callbacks from a previous peripheral instance
            guard peripheral === self.peripheral else { return }
            guard self.writeFence.accepts(stamp) else { return }
            guard self.serialQueue.inFlight != nil else {
                self.writeFence.finish()
                return
            }

            let cmd = self.serialQueue.finishWrite() ?? ""
            self.writeFence.finish()
            if let error {
                self.logger.error("Write failed: \(error.localizedDescription) cmd=\(cmd.trimmingCharacters(in: .whitespacesAndNewlines))")
                self.onWriteFailed?(cmd)
            } else if !cmd.isEmpty {
                self.onWriteSucceeded?(cmd)
            }
            self.pumpWriteQueue()
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == BLEConstants.uartTXCharUUID,
              let data = characteristic.value else { return }

        Task { @MainActor in
            self.onNotification?()
        }

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
                    self.batterySampleConfirmed = true
                }
            }
        }
    }
}

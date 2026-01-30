import Foundation
import CoreBluetooth
import Combine

enum BLEConnectionState {
    case disconnected
    case scanning
    case connecting
    case connected
    case ready
}

struct DiscoveredDevice: Identifiable, Equatable {
    let id: UUID
    let peripheral: CBPeripheral
    let name: String
    let rssi: Int
    let services: [CBUUID]

    var isTrainer: Bool {
        // Check advertised services
        if services.contains(BLEConstants.ftmsServiceUUID) ||
           services.contains(BLEConstants.cyclingPowerServiceUUID) ||
           services.contains(BLEConstants.fecServiceUUID) {
            return true
        }
        // Also recognize known trainer brands by name (they don't always advertise services)
        let lowercaseName = name.lowercased()
        let knownTrainerNames = ["tacx", "neo", "kickr", "wahoo", "elite", "saris", "cyclops", "bkool", "trainer"]
        return knownTrainerNames.contains { lowercaseName.contains($0) }
    }

    var isHeartRate: Bool {
        if services.contains(BLEConstants.heartRateServiceUUID) {
            return true
        }
        // Recognize known HRM brands by name
        let lowercaseName = name.lowercased()
        let knownHRMNames = ["hrm", "heart", "polar", "garmin", "tickr", "coospo", "magene"]
        return knownHRMNames.contains { lowercaseName.contains($0) }
    }

    var isCadence: Bool {
        services.contains(BLEConstants.cscServiceUUID)
    }

    static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class BLEManager: NSObject, ObservableObject {
    @Published var centralState: CBManagerState = .unknown
    @Published var discoveredDevices: [DiscoveredDevice] = []
    @Published var isScanning = false

    @Published var trainerDevice: TrainerDevice?
    @Published var heartRateDevice: HeartRateDevice?

    @Published var trainerConnectionState: BLEConnectionState = .disconnected {
        didSet {
            print("BLEManager: trainerConnectionState changed from \(oldValue) to \(trainerConnectionState)")
            Thread.callStackSymbols.prefix(8).forEach { print("  \($0)") }
        }
    }
    @Published var heartRateConnectionState: BLEConnectionState = .disconnected

    private var centralManager: CBCentralManager!
    private var reconnectWorkItems: [UUID: DispatchWorkItem] = [:]
    private var reconnectAttempts: [UUID: Int] = [:]

    private let maxReconnectAttempts = 6
    private let baseReconnectDelay: TimeInterval = 1.0

    // UserDefaults keys for storing known device UUIDs
    private let lastTrainerUUIDKey = "lastConnectedTrainerUUID"
    private let lastTrainerNameKey = "lastConnectedTrainerName"
    private let lastHRMUUIDKey = "lastConnectedHRMUUID"
    private let lastHRMNameKey = "lastConnectedHRMName"

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: BLEConstants.centralManagerRestoreIdentifier
            ]
        )
    }

    func startScanning() {
        guard centralState == .poweredOn else { return }
        discoveredDevices.removeAll()
        isScanning = true

        // Retrieve previously known devices by their stored UUIDs
        retrieveKnownDevices()

        // Then scan for new devices
        centralManager.scanForPeripherals(
            withServices: nil,  // Scan for all devices to find Tacx FE-C
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    private func retrieveKnownDevices() {
        var knownUUIDs: [UUID] = []

        // Get stored trainer UUID
        if let trainerUUIDString = UserDefaults.standard.string(forKey: lastTrainerUUIDKey),
           let trainerUUID = UUID(uuidString: trainerUUIDString) {
            knownUUIDs.append(trainerUUID)
        }

        // Get stored HRM UUID
        if let hrmUUIDString = UserDefaults.standard.string(forKey: lastHRMUUIDKey),
           let hrmUUID = UUID(uuidString: hrmUUIDString) {
            knownUUIDs.append(hrmUUID)
        }

        guard !knownUUIDs.isEmpty else { return }

        // Retrieve peripherals by their UUIDs (works even when not advertising)
        let knownPeripherals = centralManager.retrievePeripherals(withIdentifiers: knownUUIDs)

        for peripheral in knownPeripherals {
            let isTrainer = UserDefaults.standard.string(forKey: lastTrainerUUIDKey) == peripheral.identifier.uuidString
            let storedName: String?
            let services: [CBUUID]

            if isTrainer {
                storedName = UserDefaults.standard.string(forKey: lastTrainerNameKey)
                services = [BLEConstants.fecServiceUUID]  // Assume FE-C for stored trainers
            } else {
                storedName = UserDefaults.standard.string(forKey: lastHRMNameKey)
                services = [BLEConstants.heartRateServiceUUID]
            }

            let name = peripheral.name ?? storedName ?? "Known Device"
            print("BLEManager: Retrieved known device: \(name) (\(peripheral.identifier))")

            let device = DiscoveredDevice(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: name,
                rssi: -50,
                services: services
            )

            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device)
            }
        }
    }

    private func saveTrainerUUID(_ uuid: UUID, name: String?) {
        UserDefaults.standard.set(uuid.uuidString, forKey: lastTrainerUUIDKey)
        if let name = name {
            UserDefaults.standard.set(name, forKey: lastTrainerNameKey)
        }
        print("BLEManager: Saved trainer UUID: \(uuid)")
    }

    private func saveHRMUUID(_ uuid: UUID, name: String?) {
        UserDefaults.standard.set(uuid.uuidString, forKey: lastHRMUUIDKey)
        if let name = name {
            UserDefaults.standard.set(name, forKey: lastHRMNameKey)
        }
        print("BLEManager: Saved HRM UUID: \(uuid)")
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func connectTrainer(_ device: DiscoveredDevice) {
        stopScanning()
        trainerConnectionState = .connecting
        let trainer = TrainerDevice(peripheral: device.peripheral)
        trainer.delegate = self
        trainerDevice = trainer
        centralManager.connect(device.peripheral, options: nil)
    }

    func connectHeartRate(_ device: DiscoveredDevice) {
        stopScanning()
        heartRateConnectionState = .connecting
        let hrDevice = HeartRateDevice(peripheral: device.peripheral)
        hrDevice.delegate = self
        heartRateDevice = hrDevice
        centralManager.connect(device.peripheral, options: nil)
    }

    func disconnectTrainer() {
        guard let trainer = trainerDevice else { return }
        let peripheral = trainer.peripheral

        print("BLEManager: disconnectTrainer() - peripheral state: \(peripheral.state.rawValue)")

        cancelReconnect(for: peripheral.identifier)

        // Release trainer control first (sends Reset command for FTMS, 0W for FE-C)
        // This prevents "zombie" connections where the trainer stays locked
        trainer.releaseControl()

        // Then cancel the BLE connection
        if centralState == .poweredOn {
            print("BLEManager: Calling cancelPeripheralConnection for trainer")
            centralManager.cancelPeripheralConnection(peripheral)
        }

        trainerDevice = nil
        trainerConnectionState = .disconnected
    }

    func disconnectHeartRate() {
        guard let hr = heartRateDevice else { return }
        let peripheral = hr.peripheral

        print("BLEManager: disconnectHeartRate() - peripheral state: \(peripheral.state.rawValue)")

        cancelReconnect(for: peripheral.identifier)

        // Always try to cancel the connection, regardless of current peripheral state
        if centralState == .poweredOn {
            print("BLEManager: Calling cancelPeripheralConnection for heart rate monitor")
            centralManager.cancelPeripheralConnection(peripheral)
        }

        heartRateDevice = nil
        heartRateConnectionState = .disconnected
    }

    func disconnectAll() {
        print("BLEManager: disconnectAll() called, centralState: \(centralState.rawValue)")
        guard centralState == .poweredOn else {
            print("BLEManager: disconnectAll() skipped - Bluetooth not powered on")
            return
        }
        disconnectTrainer()
        disconnectHeartRate()
    }

    private func scheduleReconnect(for peripheral: CBPeripheral) {
        let uuid = peripheral.identifier
        let attempt = (reconnectAttempts[uuid] ?? 0) + 1

        guard attempt <= maxReconnectAttempts else {
            reconnectAttempts[uuid] = 0
            return
        }

        reconnectAttempts[uuid] = attempt
        let delay = baseReconnectDelay * pow(2.0, Double(attempt - 1))

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.centralManager.connect(peripheral, options: nil)
            }
        }

        reconnectWorkItems[uuid] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelReconnect(for uuid: UUID) {
        reconnectWorkItems[uuid]?.cancel()
        reconnectWorkItems[uuid] = nil
        reconnectAttempts[uuid] = 0
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.centralState = central.state

            if central.state == .poweredOn {
                // Clean up any orphaned connections from previous app sessions
                self.cleanupOrphanedConnections()
            }
        }
    }

    private func cleanupOrphanedConnections() {
        print("BLEManager: cleanupOrphanedConnections called")
        print("BLEManager: Current trainerDevice: \(trainerDevice?.peripheral.identifier.uuidString ?? "nil")")
        print("BLEManager: Current heartRateDevice: \(heartRateDevice?.peripheral.identifier.uuidString ?? "nil")")

        // Find any peripherals that iOS still has connected from a previous session
        let connectedTrainers = centralManager.retrieveConnectedPeripherals(withServices: [
            BLEConstants.ftmsServiceUUID,
            BLEConstants.fecServiceUUID,
            BLEConstants.cyclingPowerServiceUUID
        ])

        let connectedHRMs = centralManager.retrieveConnectedPeripherals(withServices: [
            BLEConstants.heartRateServiceUUID
        ])

        print("BLEManager: Found \(connectedTrainers.count) connected trainers, \(connectedHRMs.count) connected HRMs")

        // Disconnect any that we're not actively using
        for peripheral in connectedTrainers {
            if trainerDevice?.peripheral.identifier != peripheral.identifier {
                print("BLEManager: Disconnecting orphaned trainer: \(peripheral.name ?? "Unknown") (\(peripheral.identifier))")
                centralManager.cancelPeripheralConnection(peripheral)
            } else {
                print("BLEManager: Keeping active trainer: \(peripheral.name ?? "Unknown")")
            }
        }

        for peripheral in connectedHRMs {
            if heartRateDevice?.peripheral.identifier != peripheral.identifier {
                print("BLEManager: Disconnecting orphaned HRM: \(peripheral.name ?? "Unknown") (\(peripheral.identifier))")
                centralManager.cancelPeripheralConnection(peripheral)
            } else {
                print("BLEManager: Keeping active HRM: \(peripheral.name ?? "Unknown")")
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
            let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []

            let device = DiscoveredDevice(
                id: peripheral.identifier,
                peripheral: peripheral,
                name: name,
                rssi: RSSI.intValue,
                services: serviceUUIDs
            )

            if let index = self.discoveredDevices.firstIndex(where: { $0.id == device.id }) {
                self.discoveredDevices[index] = device
            } else {
                self.discoveredDevices.append(device)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            print("BLEManager: didConnect for \(peripheral.name ?? "unknown")")
            self.cancelReconnect(for: peripheral.identifier)

            if peripheral.identifier == self.trainerDevice?.peripheral.identifier {
                print("BLEManager: Trainer connected, starting service discovery...")
                self.trainerConnectionState = .connected
                self.saveTrainerUUID(peripheral.identifier, name: peripheral.name)
                self.trainerDevice?.discoverServices()
            } else if peripheral.identifier == self.heartRateDevice?.peripheral.identifier {
                print("BLEManager: Heart rate monitor connected, starting service discovery...")
                self.heartRateConnectionState = .connected
                self.saveHRMUUID(peripheral.identifier, name: peripheral.name)
                self.heartRateDevice?.discoverServices()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            print("BLEManager: didDisconnectPeripheral - \(peripheral.name ?? "unknown"), error: \(error?.localizedDescription ?? "none")")

            if peripheral.identifier == self.trainerDevice?.peripheral.identifier {
                print("BLEManager: Trainer disconnected callback received")
                self.trainerConnectionState = .disconnected
                if error != nil {
                    self.scheduleReconnect(for: peripheral)
                }
            } else if peripheral.identifier == self.heartRateDevice?.peripheral.identifier {
                print("BLEManager: Heart rate monitor disconnected callback received")
                self.heartRateConnectionState = .disconnected
                if error != nil {
                    self.scheduleReconnect(for: peripheral)
                }
            } else {
                print("BLEManager: Unknown peripheral disconnected: \(peripheral.identifier)")
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task { @MainActor in
            print("BLEManager: didFailToConnect - \(peripheral.name ?? "unknown"), error: \(error?.localizedDescription ?? "none")")

            if peripheral.identifier == self.trainerDevice?.peripheral.identifier {
                print("BLEManager: Trainer connection failed, scheduling reconnect")
                self.trainerConnectionState = .disconnected
                self.scheduleReconnect(for: peripheral)
            } else if peripheral.identifier == self.heartRateDevice?.peripheral.identifier {
                print("BLEManager: Heart rate monitor connection failed, scheduling reconnect")
                self.heartRateConnectionState = .disconnected
                self.scheduleReconnect(for: peripheral)
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] else {
            return
        }

        Task { @MainActor in
            for peripheral in peripherals {
                let isTrainer = peripheral.services?.contains(where: {
                    $0.uuid == BLEConstants.ftmsServiceUUID ||
                    $0.uuid == BLEConstants.fecServiceUUID ||
                    $0.uuid == BLEConstants.cyclingPowerServiceUUID
                }) == true

                if isTrainer {
                    let trainer = TrainerDevice(peripheral: peripheral)
                    trainer.delegate = self
                    self.trainerDevice = trainer
                    self.trainerConnectionState = peripheral.state == .connected ? .connected : .disconnected
                }
            }
        }
    }
}

// MARK: - TrainerDeviceDelegate

nonisolated extension BLEManager: TrainerDeviceDelegate {
    func trainerDeviceDidBecomeReady(_ device: TrainerDevice) {
        Task { @MainActor in trainerConnectionState = .ready }
    }

    func trainerDevice(_ device: TrainerDevice, didUpdatePower power: Int) {
        // Power updates are handled by subscribers to the device
    }

    func trainerDevice(_ device: TrainerDevice, didUpdateCadence cadence: Int) {
        // Cadence updates are handled by subscribers to the device
    }

    func trainerDevice(_ device: TrainerDevice, didReceiveControlPointResponse success: Bool, opCode: UInt8) {
        // Handle control point responses
    }

    func trainerDevice(_ device: TrainerDevice, didEncounterError error: Error) {
        // Handle errors
    }
}

// MARK: - HeartRateDeviceDelegate

nonisolated extension BLEManager: HeartRateDeviceDelegate {
    func heartRateDeviceDidBecomeReady(_ device: HeartRateDevice) {
        Task { @MainActor in heartRateConnectionState = .ready }
    }

    func heartRateDevice(_ device: HeartRateDevice, didUpdateHeartRate heartRate: Int) {
        // HR updates are handled by subscribers to the device
    }

    func heartRateDevice(_ device: HeartRateDevice, didEncounterError error: Error) {
        // Handle errors
    }
}


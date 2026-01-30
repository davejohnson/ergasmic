import Foundation
import CoreBluetooth
import Combine

protocol TrainerDeviceDelegate: AnyObject {
    func trainerDeviceDidBecomeReady(_ device: TrainerDevice)
    func trainerDevice(_ device: TrainerDevice, didUpdatePower power: Int)
    func trainerDevice(_ device: TrainerDevice, didUpdateCadence cadence: Int)
    func trainerDevice(_ device: TrainerDevice, didReceiveControlPointResponse success: Bool, opCode: UInt8)
    func trainerDevice(_ device: TrainerDevice, didEncounterError error: Error)
}

enum TrainerProtocol {
    case unknown
    case ftms      // Standard FTMS (Wahoo, etc.)
    case fec       // FE-C over BLE (Tacx, Garmin)
}

class TrainerDevice: NSObject, ObservableObject {
    let peripheral: CBPeripheral

    @Published var currentPower: Int = 0
    @Published var currentCadence: Int = 0
    @Published var currentSpeed: Double = 0
    @Published var targetPower: Int = 0
    @Published var hasControl: Bool = false
    @Published var isReady: Bool = false

    weak var delegate: TrainerDeviceDelegate?

    // Protocol detection
    private(set) var trainerProtocol: TrainerProtocol = .unknown

    // FTMS characteristics
    private var ftmsService: CBService?
    private var ftmsControlPointCharacteristic: CBCharacteristic?
    private var ftmsIndoorBikeDataCharacteristic: CBCharacteristic?

    // FE-C characteristics
    private var fecService: CBService?
    private var fecWriteCharacteristic: CBCharacteristic?
    private var fecNotifyCharacteristic: CBCharacteristic?

    // FE-C requires periodic target updates
    private var fecTargetTimer: Timer?
    private var fecWriteEnabled = true

    // For calculating cadence from crank revolutions (Cycling Power service)
    private var lastCrankRevolutions: UInt16 = 0
    private var lastCrankEventTime: UInt16 = 0
    private var hasLastCrankData = false

    private let parser = FTMSParser()

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    func discoverServices() {
        print("TrainerDevice: Discovering services...")
        print("TrainerDevice: Peripheral state: \(peripheral.state.rawValue), delegate set: \(peripheral.delegate != nil)")
        // Discover ALL services - we'll check for both FTMS and FE-C
        peripheral.discoverServices(nil)
    }

    // MARK: - Control Commands

    func requestControl() {
        switch trainerProtocol {
        case .ftms:
            requestControlFTMS()
        case .fec:
            // FE-C doesn't require explicit control request
            print("TrainerDevice: FE-C protocol - no control request needed")
            hasControl = true
            isReady = true
            delegate?.trainerDeviceDidBecomeReady(self)
        case .unknown:
            print("TrainerDevice: requestControl failed - protocol unknown")
        }
    }

    private func requestControlFTMS() {
        // Don't request control if we already have it
        guard !hasControl else {
            print("TrainerDevice: Already have control, skipping request")
            return
        }
        guard peripheral.state == .connected else {
            print("TrainerDevice: requestControl failed - peripheral not connected")
            return
        }
        guard let characteristic = ftmsControlPointCharacteristic else {
            print("TrainerDevice: requestControl failed - no FTMS control point characteristic")
            return
        }
        print("TrainerDevice: Requesting FTMS control...")
        let data = Data([BLEConstants.FTMSOpCode.requestControl.rawValue])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func startTraining() {
        guard trainerProtocol == .ftms else { return }
        guard let characteristic = ftmsControlPointCharacteristic else {
            print("TrainerDevice: startTraining failed - no control point characteristic")
            return
        }
        print("TrainerDevice: Starting training mode...")
        let data = Data([BLEConstants.FTMSOpCode.startOrResume.rawValue])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func stopTraining() {
        switch trainerProtocol {
        case .ftms:
            guard let characteristic = ftmsControlPointCharacteristic else { return }
            // First stop training
            let data = Data([BLEConstants.FTMSOpCode.stopOrPause.rawValue, 0x01])
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
            // Then release control to prevent zombie connection
            releaseControlFTMS()
        case .fec:
            // Stop the periodic timer and send 0W to release resistance
            stopFECTargetTimer()
            if let characteristic = fecWriteCharacteristic {
                sendFECTargetPower(0, to: characteristic)
            }
        case .unknown:
            break
        }
    }

    func pauseTraining() {
        switch trainerProtocol {
        case .ftms:
            guard let characteristic = ftmsControlPointCharacteristic else { return }
            let data = Data([BLEConstants.FTMSOpCode.stopOrPause.rawValue, 0x02])
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        case .fec:
            // FE-C doesn't have pause - stop the timer to stop sending targets
            // The trainer will hold the last resistance
            stopFECTargetTimer()
        case .unknown:
            break
        }
    }

    deinit {
        stopFECTargetTimer()
    }

    func resumeTraining() {
        switch trainerProtocol {
        case .ftms:
            startTraining()
        case .fec:
            // Resume sending target power
            if targetPower > 0 {
                setTargetPowerFEC(targetPower)
            }
        case .unknown:
            break
        }
    }

    func setTargetPower(_ watts: Int) {
        let clampedWatts = max(0, min(2000, watts))
        targetPower = clampedWatts

        switch trainerProtocol {
        case .ftms:
            setTargetPowerFTMS(clampedWatts)
        case .fec:
            setTargetPowerFEC(clampedWatts)
        case .unknown:
            print("TrainerDevice: setTargetPower failed - protocol unknown")
        }
    }

    private func setTargetPowerFTMS(_ watts: Int) {
        guard peripheral.state == .connected else {
            print("TrainerDevice: setTargetPower failed - peripheral not connected")
            return
        }
        guard let characteristic = ftmsControlPointCharacteristic else {
            print("TrainerDevice: setTargetPower failed - no FTMS control point characteristic")
            return
        }

        // Request control if we don't have it yet
        if !hasControl {
            print("TrainerDevice: No control yet, requesting control first (target: \(watts)W)")
            requestControlFTMS()
            return
        }

        // Check buffer before writing to prevent overflow (Tacx Neo is sensitive to this)
        guard peripheral.canSendWriteWithoutResponse else {
            print("TrainerDevice: Cannot send - BLE buffer full, skipping this update")
            return
        }

        print("TrainerDevice: Setting FTMS target power to \(watts)W")
        let lowByte = UInt8(watts & 0xFF)
        let highByte = UInt8((watts >> 8) & 0xFF)
        let data = Data([BLEConstants.FTMSOpCode.setTargetPower.rawValue, lowByte, highByte])
        // Use writeWithoutResponse for power commands (per FTMS spec - frequent updates)
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    private func setTargetPowerFEC(_ watts: Int) {
        guard let characteristic = fecWriteCharacteristic else {
            print("TrainerDevice: setTargetPower failed - no FE-C write characteristic")
            return
        }

        print("TrainerDevice: Setting FE-C target power to \(watts)W (ERG mode)")

        sendFECTargetPower(watts, to: characteristic)

        // Start periodic resend timer for FE-C (required by protocol)
        startFECTargetTimer(watts: watts)
    }

    private func sendFECTargetPower(_ watts: Int, to characteristic: CBCharacteristic) {
        // Make sure peripheral is connected before writing
        guard peripheral.state == .connected else {
            print("TrainerDevice: Cannot write - peripheral state is \(peripheral.state.rawValue), not connected")
            return
        }

        // FE-C Target Power page (0x31) - This automatically enables ERG mode
        // Power is in 0.25W resolution
        let powerUnits = UInt16(Double(watts) / 0.25)
        let lowByte = UInt8(powerUnits & 0xFF)
        let highByte = UInt8((powerUnits >> 8) & 0xFF)

        // Build ANT+ message per Tacx FE-C over BLE spec (from official Tacx iOS example)
        // Format: [sync][len][type][channel][page][padding x5][power LSB][power MSB][checksum]
        var antMessage: [UInt8] = [
            0xA4,           // Sync byte
            0x09,           // Length (9 bytes follow before checksum)
            0x4F,           // Message type: Acknowledged (0x4F, NOT 0x4E broadcast)
            0x05,           // Channel number
            BLEConstants.FECPage.targetPower.rawValue,  // 0x31 - Page 49 (target power)
            0xFF,           // Padding
            0xFF,           // Padding
            0xFF,           // Padding
            0xFF,           // Padding
            0xFF,           // Padding
            lowByte,        // Target power LSB
            highByte        // Target power MSB
        ]

        // Calculate checksum (XOR of all bytes)
        var checksum: UInt8 = 0
        for byte in antMessage {
            checksum ^= byte
        }
        antMessage.append(checksum)

        let data = Data(antMessage)
        print("TrainerDevice: Sending FE-C ANT+ message: \(data.map { String(format: "%02X", $0) }.joined(separator: " "))")

        // Use writeWithoutResponse to avoid blocking
        if characteristic.properties.contains(.writeWithoutResponse) {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        } else if characteristic.properties.contains(.write) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        } else {
            print("TrainerDevice: FE-C Write characteristic doesn't support any write type!")
        }
    }

    private func startFECTargetTimer(watts: Int) {
        stopFECTargetTimer()
        fecWriteEnabled = true  // Reset on new target

        // FE-C protocol requires target within 2 seconds to maintain control
        // Use 500ms interval to balance responsiveness and avoid flooding
        fecTargetTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.fecWriteEnabled,
                  let characteristic = self.fecWriteCharacteristic else { return }
            self.sendFECTargetPower(self.targetPower, to: characteristic)
        }
    }

    private func stopFECTargetTimer() {
        fecTargetTimer?.invalidate()
        fecTargetTimer = nil
    }

    func reset() {
        guard trainerProtocol == .ftms else { return }
        guard let characteristic = ftmsControlPointCharacteristic else { return }
        let data = Data([BLEConstants.FTMSOpCode.reset.rawValue])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    func releaseControl() {
        switch trainerProtocol {
        case .ftms:
            releaseControlFTMS()
        case .fec:
            // FE-C: send 0W and stop timer
            stopFECTargetTimer()
            if let characteristic = fecWriteCharacteristic {
                sendFECTargetPower(0, to: characteristic)
            }
        case .unknown:
            break
        }
        hasControl = false
        isReady = false
    }

    private func releaseControlFTMS() {
        guard let characteristic = ftmsControlPointCharacteristic else { return }
        print("TrainerDevice: Releasing FTMS control (sending Reset)")
        let data = Data([BLEConstants.FTMSOpCode.reset.rawValue])
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - CBPeripheralDelegate

extension TrainerDevice: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        print("TrainerDevice: didDiscoverServices called, error: \(error?.localizedDescription ?? "none")")

        if let error = error {
            delegate?.trainerDevice(self, didEncounterError: error)
            return
        }

        guard let services = peripheral.services else {
            print("TrainerDevice: No services found!")
            return
        }

        print("TrainerDevice: Found \(services.count) services: \(services.map { $0.uuid.uuidString })")

        for service in services {
            // Check for FTMS (preferred)
            if service.uuid == BLEConstants.ftmsServiceUUID {
                print("TrainerDevice: Found FTMS service, discovering characteristics...")
                ftmsService = service
                trainerProtocol = .ftms
                peripheral.discoverCharacteristics([
                    BLEConstants.ftmsControlPointUUID,
                    BLEConstants.ftmsIndoorBikeDataUUID
                ], for: service)
            }
            // Check for FE-C (Tacx, Garmin)
            else if service.uuid == BLEConstants.fecServiceUUID {
                print("TrainerDevice: Found FE-C service, discovering characteristics...")
                fecService = service
                if trainerProtocol == .unknown {
                    trainerProtocol = .fec
                }
                peripheral.discoverCharacteristics([
                    BLEConstants.fecWriteUUID,
                    BLEConstants.fecNotifyUUID
                ], for: service)
            }
            // Also get Cycling Power for power data (as backup)
            else if service.uuid == BLEConstants.cyclingPowerServiceUUID {
                print("TrainerDevice: Found Cycling Power service, discovering characteristics...")
                peripheral.discoverCharacteristics(nil, for: service)  // Discover ALL characteristics
            }
            // Check for unknown/proprietary services that might have control
            else {
                print("TrainerDevice: Found other service \(service.uuid.uuidString), discovering all characteristics...")
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("TrainerDevice: Error discovering characteristics: \(error.localizedDescription)")
            delegate?.trainerDevice(self, didEncounterError: error)
            return
        }

        guard let characteristics = service.characteristics else {
            print("TrainerDevice: No characteristics found for service \(service.uuid)")
            return
        }

        print("TrainerDevice: Found \(characteristics.count) characteristics for service \(service.uuid.uuidString)")

        for characteristic in characteristics {
            print("TrainerDevice: - Characteristic: \(characteristic.uuid.uuidString)")

            switch characteristic.uuid {
            // FTMS characteristics
            case BLEConstants.ftmsControlPointUUID:
                print("TrainerDevice: Found FTMS Control Point characteristic")
                ftmsControlPointCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)

            case BLEConstants.ftmsIndoorBikeDataUUID:
                print("TrainerDevice: Found Indoor Bike Data characteristic")
                ftmsIndoorBikeDataCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)

            // FE-C characteristics - assign based on actual properties, not UUID
            // (Tacx Neo has these swapped compared to spec)
            case BLEConstants.fecWriteUUID, BLEConstants.fecNotifyUUID:
                let props = characteristicPropertiesDescription(characteristic.properties)
                print("TrainerDevice: Found FE-C characteristic \(characteristic.uuid.uuidString) - properties: \(props)")

                // Assign based on what the characteristic actually supports
                if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                    print("TrainerDevice: -> Using as WRITE characteristic")
                    fecWriteCharacteristic = characteristic
                }
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    print("TrainerDevice: -> Using as NOTIFY characteristic")
                    fecNotifyCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }

            // Cycling Power characteristics
            case BLEConstants.cyclingPowerMeasurementUUID:
                print("TrainerDevice: Found Cycling Power Measurement characteristic")
                peripheral.setNotifyValue(true, for: characteristic)

            default:
                break
            }
        }

        // Check if we're ready based on protocol
        checkReadyState()
    }

    private func characteristicPropertiesDescription(_ properties: CBCharacteristicProperties) -> String {
        var props: [String] = []
        if properties.contains(.read) { props.append("read") }
        if properties.contains(.write) { props.append("write") }
        if properties.contains(.writeWithoutResponse) { props.append("writeWithoutResponse") }
        if properties.contains(.notify) { props.append("notify") }
        if properties.contains(.indicate) { props.append("indicate") }
        if properties.contains(.authenticatedSignedWrites) { props.append("authenticatedSignedWrites") }
        if properties.contains(.extendedProperties) { props.append("extendedProperties") }
        return props.joined(separator: ", ")
    }

    private func checkReadyState() {
        // Don't re-trigger ready logic if already ready
        guard !isReady else { return }

        switch trainerProtocol {
        case .ftms:
            if ftmsControlPointCharacteristic != nil && ftmsIndoorBikeDataCharacteristic != nil {
                print("TrainerDevice: FTMS ready, requesting control...")
                requestControlFTMS()
            }
        case .fec:
            if fecWriteCharacteristic != nil && fecNotifyCharacteristic != nil {
                print("TrainerDevice: FE-C ready!")
                hasControl = true
                isReady = true
                delegate?.trainerDeviceDidBecomeReady(self)
                // Send pending target power if any
                if targetPower > 0 {
                    print("TrainerDevice: Sending pending target power: \(targetPower)W")
                    setTargetPowerFEC(targetPower)
                }
            }
        case .unknown:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            delegate?.trainerDevice(self, didEncounterError: error)
            return
        }

        guard let data = characteristic.value else { return }

        switch characteristic.uuid {
        // FTMS data
        case BLEConstants.ftmsIndoorBikeDataUUID:
            let bikeData = parser.parseIndoorBikeData(data)
            if let power = bikeData.instantaneousPower {
                currentPower = power
                delegate?.trainerDevice(self, didUpdatePower: power)
            }
            if let cadence = bikeData.instantaneousCadence {
                currentCadence = Int(cadence)
                delegate?.trainerDevice(self, didUpdateCadence: Int(cadence))
            }
            if let speed = bikeData.instantaneousSpeed {
                currentSpeed = speed
            }

        case BLEConstants.ftmsControlPointUUID:
            handleFTMSControlPointResponse(data)

        // FE-C data
        case BLEConstants.fecNotifyUUID:
            handleFECData(data)

        // Cycling Power data
        case BLEConstants.cyclingPowerMeasurementUUID:
            handleCyclingPowerData(data)

        default:
            // Fallback: check if this is our stored FE-C notify characteristic
            // (handles devices with different UUID assignments)
            if let fecNotify = fecNotifyCharacteristic, characteristic.uuid == fecNotify.uuid {
                handleFECData(data)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("TrainerDevice: Write error for \(characteristic.uuid): \(error.localizedDescription)")
            // Stop flooding errors if FE-C writes are failing
            if characteristic.uuid == BLEConstants.fecWriteUUID {
                fecWriteEnabled = false
                stopFECTargetTimer()
                print("TrainerDevice: FE-C writes disabled due to errors")
            }
            delegate?.trainerDevice(self, didEncounterError: error)
        } else {
            print("TrainerDevice: Write successful for \(characteristic.uuid.uuidString)")
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("TrainerDevice: Notification error for \(characteristic.uuid): \(error.localizedDescription)")
            delegate?.trainerDevice(self, didEncounterError: error)
        } else {
            print("TrainerDevice: Notifications enabled for \(characteristic.uuid.uuidString)")
        }
    }

    // MARK: - Response Handlers

    private func handleFTMSControlPointResponse(_ data: Data) {
        guard data.count >= 3,
              data[0] == BLEConstants.FTMSOpCode.responseCode.rawValue else {
            print("TrainerDevice: Invalid FTMS control point response: \(data.map { String(format: "%02X", $0) }.joined())")
            return
        }

        let requestOpCode = data[1]
        let resultCode = data[2]
        let success = resultCode == BLEConstants.FTMSResultCode.success.rawValue

        print("TrainerDevice: FTMS response - opCode: \(requestOpCode), result: \(resultCode), success: \(success)")

        if requestOpCode == BLEConstants.FTMSOpCode.requestControl.rawValue && success {
            print("TrainerDevice: FTMS control granted!")
            hasControl = true
            startTraining()
        } else if requestOpCode == BLEConstants.FTMSOpCode.startOrResume.rawValue && success {
            print("TrainerDevice: FTMS training started!")
            isReady = true
            delegate?.trainerDeviceDidBecomeReady(self)
            if targetPower > 0 {
                print("TrainerDevice: Sending pending target power: \(targetPower)W")
                setTargetPowerFTMS(targetPower)
            }
        } else if requestOpCode == BLEConstants.FTMSOpCode.setTargetPower.rawValue {
            print("TrainerDevice: FTMS target power \(success ? "accepted" : "rejected")")
        }

        delegate?.trainerDevice(self, didReceiveControlPointResponse: success, opCode: requestOpCode)
    }

    private func handleFECData(_ data: Data) {
        guard data.count >= 1 else { return }

        // FE-C over BLE wraps ANT+ messages: [A4] [len] [type] [channel] [8-byte payload] [checksum]
        // Check if this is ANT+ framed data (starts with sync byte 0xA4)
        let payload: Data
        if data[0] == 0xA4 && data.count >= 13 {
            // Extract the 8-byte FE-C payload from ANT+ frame (bytes 4-11)
            payload = data.subdata(in: 4..<12)
        } else if data.count >= 8 {
            // Raw FE-C payload (no ANT+ framing)
            payload = data
        } else {
            return
        }

        let pageNumber = payload[0]

        switch pageNumber {
        case BLEConstants.FECPage.generalFEData.rawValue:  // 0x10 - General FE Data
            // Byte 0: Page (0x10)
            // Byte 1: Equipment type
            // Byte 2: Elapsed time (0.25s increments)
            // Byte 3: Distance traveled (m)
            // Byte 4-5: Speed (0.001 m/s, little endian)
            // Byte 6: Heart rate (0xFF = invalid)
            // Byte 7: Capabilities + FE State
            let speedRaw = Int(payload[4]) | (Int(payload[5]) << 8)
            if speedRaw != 0xFFFF {
                currentSpeed = Double(speedRaw) * 0.001 * 3.6  // Convert to km/h
            }
            let feState = payload[7] & 0x70 >> 4  // Bits 4-6 = FE State
            print("TrainerDevice: FE-C General Data - speed: \(String(format: "%.1f", currentSpeed)) km/h, state: \(feState)")

        case BLEConstants.FECPage.trainerData.rawValue:  // 0x19 - Specific Trainer Data
            // Byte 0: Page (0x19)
            // Byte 1: Update event count
            // Byte 2: Instantaneous cadence (0xFF = invalid)
            // Byte 3-4: Accumulated power (little endian)
            // Byte 5: Instantaneous power LSB (bits 0-7)
            // Byte 6: Bits 0-3 = power bits 8-11; Bits 4-7 = trainer status
            // Byte 7: Flags and target power status
            let cadence = Int(payload[2])
            if cadence != 0xFF {
                currentCadence = cadence
                delegate?.trainerDevice(self, didUpdateCadence: cadence)
            }

            // Instantaneous power: byte 5 + lower 4 bits of byte 6
            let powerLSB = Int(payload[5])
            let powerMSB = Int(payload[6] & 0x0F)
            let power = powerLSB | (powerMSB << 8)
            if power != 0xFFF {  // 0xFFF = invalid
                currentPower = power
                delegate?.trainerDevice(self, didUpdatePower: power)
            }

            let trainerStatus = (payload[6] & 0xF0) >> 4
            let targetPowerStatus = payload[7] & 0x03  // Bits 0-1
            print("TrainerDevice: FE-C Trainer Data - power: \(power)W, cadence: \(cadence), status: \(trainerStatus), targetStatus: \(targetPowerStatus)")

        case BLEConstants.FECPage.commandStatus.rawValue:  // 0x47 - Command Status
            let lastCommand = payload[1]
            let status = payload[3]
            let statusText: String
            switch status {
            case 0: statusText = "pass"
            case 1: statusText = "fail"
            case 2: statusText = "not supported"
            case 3: statusText = "rejected"
            case 4: statusText = "pending"
            case 255: statusText = "uninitialized"
            default: statusText = "unknown(\(status))"
            }
            print("TrainerDevice: FE-C Command Status - lastCmd: 0x\(String(format: "%02X", lastCommand)), status: \(statusText)")

        default:
            break
        }
    }

    private func handleCyclingPowerData(_ data: Data) {
        guard data.count >= 4 else { return }

        // Flags are in bytes 0-1 (little endian)
        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)

        // Instantaneous power is in bytes 2-3 (little endian)
        let power = Int(data[2]) | (Int(data[3]) << 8)
        currentPower = power
        delegate?.trainerDevice(self, didUpdatePower: power)

        var offset = 4

        // Check for pedal power balance (bit 0)
        if flags & 0x0001 != 0 {
            offset += 1
        }

        // Check for accumulated torque (bit 2)
        if flags & 0x0004 != 0 {
            offset += 2
        }

        // Check for wheel revolution data (bit 4)
        if flags & 0x0010 != 0 {
            offset += 6  // cumulative wheel revs (4) + last wheel event time (2)
        }

        // Check for crank revolution data (bit 5)
        if flags & 0x0020 != 0 && data.count >= offset + 4 {
            let crankRevolutions = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            let crankEventTime = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)

            if hasLastCrankData {
                // Calculate cadence from crank revolution data
                let revDiff = crankRevolutions &- lastCrankRevolutions  // Handle rollover
                let timeDiff = crankEventTime &- lastCrankEventTime      // Handle rollover

                if timeDiff > 0 && revDiff > 0 && revDiff < 10 {
                    // Time is in 1/1024 second units
                    let timeSeconds = Double(timeDiff) / 1024.0
                    let cadence = Int(Double(revDiff) / timeSeconds * 60.0)

                    if cadence > 0 && cadence < 200 {
                        currentCadence = cadence
                        delegate?.trainerDevice(self, didUpdateCadence: cadence)
                    }
                }
            }

            lastCrankRevolutions = crankRevolutions
            lastCrankEventTime = crankEventTime
            hasLastCrankData = true
        }
    }
}

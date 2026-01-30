import Foundation
import CoreBluetooth
import Combine

protocol HeartRateDeviceDelegate: AnyObject {
    func heartRateDeviceDidBecomeReady(_ device: HeartRateDevice)
    func heartRateDevice(_ device: HeartRateDevice, didUpdateHeartRate heartRate: Int)
    func heartRateDevice(_ device: HeartRateDevice, didEncounterError error: Error)
}

class HeartRateDevice: NSObject, ObservableObject {
    let peripheral: CBPeripheral

    @Published var currentHeartRate: Int = 0
    @Published var isReady: Bool = false

    weak var delegate: HeartRateDeviceDelegate?

    private var heartRateService: CBService?
    private var heartRateMeasurementCharacteristic: CBCharacteristic?

    init(peripheral: CBPeripheral) {
        self.peripheral = peripheral
        super.init()
        peripheral.delegate = self
    }

    func discoverServices() {
        peripheral.discoverServices([BLEConstants.heartRateServiceUUID])
    }
}

// MARK: - CBPeripheralDelegate

extension HeartRateDevice: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            delegate?.heartRateDevice(self, didEncounterError: error)
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == BLEConstants.heartRateServiceUUID {
                heartRateService = service
                peripheral.discoverCharacteristics([
                    BLEConstants.heartRateMeasurementUUID
                ], for: service)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            delegate?.heartRateDevice(self, didEncounterError: error)
            return
        }

        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == BLEConstants.heartRateMeasurementUUID {
                heartRateMeasurementCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                isReady = true
                delegate?.heartRateDeviceDidBecomeReady(self)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            delegate?.heartRateDevice(self, didEncounterError: error)
            return
        }

        guard let data = characteristic.value,
              characteristic.uuid == BLEConstants.heartRateMeasurementUUID else {
            return
        }

        let heartRate = parseHeartRate(from: data)
        currentHeartRate = heartRate
        delegate?.heartRateDevice(self, didUpdateHeartRate: heartRate)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            delegate?.heartRateDevice(self, didEncounterError: error)
        }
    }

    private func parseHeartRate(from data: Data) -> Int {
        guard !data.isEmpty else { return 0 }

        let flags = data[0]
        let is16Bit = (flags & 0x01) != 0

        if is16Bit && data.count >= 3 {
            return Int(data[1]) | (Int(data[2]) << 8)
        } else if data.count >= 2 {
            return Int(data[1])
        }

        return 0
    }
}

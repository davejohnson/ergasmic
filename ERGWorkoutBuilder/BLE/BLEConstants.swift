import CoreBluetooth

enum BLEConstants {
    // MARK: - FTMS (Fitness Machine Service)
    static let ftmsServiceUUID = CBUUID(string: "1826")
    static let ftmsIndoorBikeDataUUID = CBUUID(string: "2AD2")
    static let ftmsControlPointUUID = CBUUID(string: "2AD9")
    static let ftmsMachineStatusUUID = CBUUID(string: "2ADA")
    static let ftmsSupportedPowerRangeUUID = CBUUID(string: "2AD8")

    // MARK: - Heart Rate Service
    static let heartRateServiceUUID = CBUUID(string: "180D")
    static let heartRateMeasurementUUID = CBUUID(string: "2A37")

    // MARK: - Cycling Speed and Cadence Service
    static let cscServiceUUID = CBUUID(string: "1816")
    static let cscMeasurementUUID = CBUUID(string: "2A5B")
    static let cscFeatureUUID = CBUUID(string: "2A5C")

    // MARK: - Cycling Power Service
    static let cyclingPowerServiceUUID = CBUUID(string: "1818")
    static let cyclingPowerMeasurementUUID = CBUUID(string: "2A63")

    // MARK: - FE-C over BLE (Tacx/Garmin trainers)
    static let fecServiceUUID = CBUUID(string: "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E")
    // FEC2 = RX/Notify (data from trainer), FEC3 = TX/Write (commands to trainer)
    static let fecNotifyUUID = CBUUID(string: "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E")
    static let fecWriteUUID = CBUUID(string: "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E")

    // MARK: - FE-C Data Pages
    enum FECPage: UInt8 {
        case generalFEData = 0x10          // 16 - General FE Data
        case generalSettings = 0x11        // 17 - General Settings
        case trainerData = 0x19            // 25 - Specific Trainer Data
        case basicResistance = 0x30        // 48 - Basic Resistance
        case targetPower = 0x31            // 49 - Target Power
        case windResistance = 0x32         // 50 - Wind Resistance
        case trackResistance = 0x33        // 51 - Track Resistance
        case commandStatus = 0x47          // 71 - Command Status
        case userConfiguration = 0x37      // 55 - User Configuration
        case requestDataPage = 0x46        // 70 - Request Data Page
    }

    // MARK: - FTMS Control Point OpCodes
    enum FTMSOpCode: UInt8 {
        case requestControl = 0x00
        case reset = 0x01
        case setTargetSpeed = 0x02
        case setTargetInclination = 0x03
        case setTargetResistanceLevel = 0x04
        case setTargetPower = 0x05
        case setTargetHeartRate = 0x06
        case startOrResume = 0x07
        case stopOrPause = 0x08
        case setTargetedExpendedEnergy = 0x09
        case setTargetedNumberOfSteps = 0x0A
        case setTargetedNumberOfStrides = 0x0B
        case setTargetedDistance = 0x0C
        case setTargetedTrainingTime = 0x0D
        case setIndoorBikeSimulation = 0x11
        case setWheelCircumference = 0x12
        case spinDownControl = 0x13
        case setTargetedCadence = 0x14
        case responseCode = 0x80
    }

    // MARK: - FTMS Result Codes
    enum FTMSResultCode: UInt8 {
        case success = 0x01
        case opCodeNotSupported = 0x02
        case invalidParameter = 0x03
        case operationFailed = 0x04
        case controlNotPermitted = 0x05
    }

    // MARK: - State Restoration
    static let centralManagerRestoreIdentifier = "com.ergworkoutbuilder.centralmanager"

    // MARK: - Scan Services
    static var scanServiceUUIDs: [CBUUID] {
        [ftmsServiceUUID, heartRateServiceUUID, cscServiceUUID, cyclingPowerServiceUUID]
    }
}

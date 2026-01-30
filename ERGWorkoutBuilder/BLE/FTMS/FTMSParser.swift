import Foundation

struct IndoorBikeData {
    var instantaneousSpeed: Double?     // km/h
    var averageSpeed: Double?           // km/h
    var instantaneousCadence: Double?   // rpm
    var averageCadence: Double?         // rpm
    var totalDistance: Int?             // meters
    var resistanceLevel: Int?
    var instantaneousPower: Int?        // watts
    var averagePower: Int?              // watts
    var totalEnergy: Int?               // kcal
    var energyPerHour: Int?             // kcal
    var energyPerMinute: Int?           // kcal
    var heartRate: Int?                 // bpm
    var metabolicEquivalent: Double?
    var elapsedTime: Int?               // seconds
    var remainingTime: Int?             // seconds
}

class FTMSParser {

    // MARK: - Indoor Bike Data Flags (from FTMS spec)
    private struct Flags {
        static let moreData: UInt16               = 0x0001
        static let averageSpeedPresent: UInt16    = 0x0002
        static let instantCadencePresent: UInt16  = 0x0004
        static let averageCadencePresent: UInt16  = 0x0008
        static let totalDistancePresent: UInt16   = 0x0010
        static let resistanceLevelPresent: UInt16 = 0x0020
        static let instantPowerPresent: UInt16    = 0x0040
        static let averagePowerPresent: UInt16    = 0x0080
        static let expendedEnergyPresent: UInt16  = 0x0100
        static let heartRatePresent: UInt16       = 0x0200
        static let metabolicEquivPresent: UInt16  = 0x0400
        static let elapsedTimePresent: UInt16     = 0x0800
        static let remainingTimePresent: UInt16   = 0x1000
    }

    func parseIndoorBikeData(_ data: Data) -> IndoorBikeData {
        var result = IndoorBikeData()
        guard data.count >= 2 else { return result }

        let flags = UInt16(data[0]) | (UInt16(data[1]) << 8)
        var offset = 2

        // Instantaneous Speed (always present unless "More Data" flag is set)
        if (flags & Flags.moreData) == 0 {
            if offset + 2 <= data.count {
                let speedRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                result.instantaneousSpeed = Double(speedRaw) / 100.0
                offset += 2
            }
        }

        // Average Speed
        if (flags & Flags.averageSpeedPresent) != 0 {
            if offset + 2 <= data.count {
                let speedRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                result.averageSpeed = Double(speedRaw) / 100.0
                offset += 2
            }
        }

        // Instantaneous Cadence
        if (flags & Flags.instantCadencePresent) != 0 {
            if offset + 2 <= data.count {
                let cadenceRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                result.instantaneousCadence = Double(cadenceRaw) / 2.0
                offset += 2
            }
        }

        // Average Cadence
        if (flags & Flags.averageCadencePresent) != 0 {
            if offset + 2 <= data.count {
                let cadenceRaw = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                result.averageCadence = Double(cadenceRaw) / 2.0
                offset += 2
            }
        }

        // Total Distance
        if (flags & Flags.totalDistancePresent) != 0 {
            if offset + 3 <= data.count {
                let distance = Int(data[offset]) |
                               (Int(data[offset + 1]) << 8) |
                               (Int(data[offset + 2]) << 16)
                result.totalDistance = distance
                offset += 3
            }
        }

        // Resistance Level
        if (flags & Flags.resistanceLevelPresent) != 0 {
            if offset + 2 <= data.count {
                let resistance = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                result.resistanceLevel = Int(resistance)
                offset += 2
            }
        }

        // Instantaneous Power
        if (flags & Flags.instantPowerPresent) != 0 {
            if offset + 2 <= data.count {
                let power = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                result.instantaneousPower = Int(power)
                offset += 2
            }
        }

        // Average Power
        if (flags & Flags.averagePowerPresent) != 0 {
            if offset + 2 <= data.count {
                let power = Int16(bitPattern: UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8))
                result.averagePower = Int(power)
                offset += 2
            }
        }

        // Expended Energy (Total, Per Hour, Per Minute)
        if (flags & Flags.expendedEnergyPresent) != 0 {
            if offset + 5 <= data.count {
                let total = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                let perHour = UInt16(data[offset + 2]) | (UInt16(data[offset + 3]) << 8)
                let perMinute = data[offset + 4]
                result.totalEnergy = Int(total)
                result.energyPerHour = Int(perHour)
                result.energyPerMinute = Int(perMinute)
                offset += 5
            }
        }

        // Heart Rate
        if (flags & Flags.heartRatePresent) != 0 {
            if offset + 1 <= data.count {
                result.heartRate = Int(data[offset])
                offset += 1
            }
        }

        // Metabolic Equivalent
        if (flags & Flags.metabolicEquivPresent) != 0 {
            if offset + 1 <= data.count {
                result.metabolicEquivalent = Double(data[offset]) / 10.0
                offset += 1
            }
        }

        // Elapsed Time
        if (flags & Flags.elapsedTimePresent) != 0 {
            if offset + 2 <= data.count {
                let time = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                result.elapsedTime = Int(time)
                offset += 2
            }
        }

        // Remaining Time
        if (flags & Flags.remainingTimePresent) != 0 {
            if offset + 2 <= data.count {
                let time = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
                result.remainingTime = Int(time)
            }
        }

        return result
    }
}

import Foundation

struct FTMSControlPointResponse {
    let requestOpCode: UInt8
    let resultCode: UInt8
    let responseParameter: Data?

    var isSuccess: Bool {
        resultCode == BLEConstants.FTMSResultCode.success.rawValue
    }

    var resultDescription: String {
        switch resultCode {
        case BLEConstants.FTMSResultCode.success.rawValue:
            return "Success"
        case BLEConstants.FTMSResultCode.opCodeNotSupported.rawValue:
            return "OpCode not supported"
        case BLEConstants.FTMSResultCode.invalidParameter.rawValue:
            return "Invalid parameter"
        case BLEConstants.FTMSResultCode.operationFailed.rawValue:
            return "Operation failed"
        case BLEConstants.FTMSResultCode.controlNotPermitted.rawValue:
            return "Control not permitted"
        default:
            return "Unknown result: \(resultCode)"
        }
    }

    static func parse(_ data: Data) -> FTMSControlPointResponse? {
        guard data.count >= 3,
              data[0] == BLEConstants.FTMSOpCode.responseCode.rawValue else {
            return nil
        }

        let responseParameter = data.count > 3 ? data.subdata(in: 3..<data.count) : nil

        return FTMSControlPointResponse(
            requestOpCode: data[1],
            resultCode: data[2],
            responseParameter: responseParameter
        )
    }
}

// MARK: - Command Builders

enum FTMSCommand {
    static func requestControl() -> Data {
        Data([BLEConstants.FTMSOpCode.requestControl.rawValue])
    }

    static func reset() -> Data {
        Data([BLEConstants.FTMSOpCode.reset.rawValue])
    }

    static func setTargetPower(watts: Int) -> Data {
        let clampedWatts = max(0, min(4094, watts))
        let lowByte = UInt8(clampedWatts & 0xFF)
        let highByte = UInt8((clampedWatts >> 8) & 0xFF)
        return Data([BLEConstants.FTMSOpCode.setTargetPower.rawValue, lowByte, highByte])
    }

    static func setTargetResistance(level: Double) -> Data {
        let rawLevel = Int16(level * 10)
        let lowByte = UInt8(rawLevel & 0xFF)
        let highByte = UInt8((rawLevel >> 8) & 0xFF)
        return Data([BLEConstants.FTMSOpCode.setTargetResistanceLevel.rawValue, lowByte, highByte])
    }

    static func startOrResume() -> Data {
        Data([BLEConstants.FTMSOpCode.startOrResume.rawValue])
    }

    static func stop() -> Data {
        Data([BLEConstants.FTMSOpCode.stopOrPause.rawValue, 0x01])
    }

    static func pause() -> Data {
        Data([BLEConstants.FTMSOpCode.stopOrPause.rawValue, 0x02])
    }

    static func setIndoorBikeSimulation(
        windSpeed: Double = 0,      // m/s
        grade: Double = 0,          // percentage
        crr: Double = 0.004,        // rolling resistance coefficient
        cw: Double = 0.51           // wind resistance coefficient (kg/m)
    ) -> Data {
        let windSpeedRaw = Int16(windSpeed * 1000)
        let gradeRaw = Int16(grade * 100)
        let crrRaw = UInt8(crr * 10000)
        let cwRaw = UInt8(cw * 100)

        return Data([
            BLEConstants.FTMSOpCode.setIndoorBikeSimulation.rawValue,
            UInt8(windSpeedRaw & 0xFF),
            UInt8((windSpeedRaw >> 8) & 0xFF),
            UInt8(gradeRaw & 0xFF),
            UInt8((gradeRaw >> 8) & 0xFF),
            crrRaw,
            cwRaw
        ])
    }
}

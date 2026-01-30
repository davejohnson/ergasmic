import Foundation

enum RideStatus: String, Codable {
    case completed
    case abandoned
    case inProgress
}

struct Ride: Identifiable, Equatable {
    let id: UUID
    let workoutId: UUID?
    let workoutName: String
    let startedAt: Date
    var endedAt: Date?
    let ftpUsed: Int
    var status: RideStatus
    var avgPower: Int?
    var avgHeartRate: Int?
    var avgCadence: Int?
    var durationSec: Int
    var normalizedPower: Int?
    var intensityFactor: Double?
    var tss: Double?

    init(
        id: UUID = UUID(),
        workoutId: UUID? = nil,
        workoutName: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        ftpUsed: Int,
        status: RideStatus = .inProgress,
        avgPower: Int? = nil,
        avgHeartRate: Int? = nil,
        avgCadence: Int? = nil,
        durationSec: Int = 0,
        normalizedPower: Int? = nil,
        intensityFactor: Double? = nil,
        tss: Double? = nil
    ) {
        self.id = id
        self.workoutId = workoutId
        self.workoutName = workoutName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.ftpUsed = ftpUsed
        self.status = status
        self.avgPower = avgPower
        self.avgHeartRate = avgHeartRate
        self.avgCadence = avgCadence
        self.durationSec = durationSec
        self.normalizedPower = normalizedPower
        self.intensityFactor = intensityFactor
        self.tss = tss
    }

    var formattedDuration: String {
        formatDuration(durationSec)
    }
}

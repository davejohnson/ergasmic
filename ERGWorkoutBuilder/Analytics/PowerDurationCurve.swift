import Foundation
import CoreData

/// Represents best power efforts at standard durations
struct PowerDurationRecord {
    let duration: Int  // seconds
    let power: Int     // watts
    let recordedAt: Date
    let rideId: UUID?
}

/// Tracks best power efforts across standard durations
class PowerDurationCurve: ObservableObject {
    private let context: NSManagedObjectContext

    // Standard durations for power curve (in seconds)
    static let standardDurations = [5, 30, 60, 300, 600, 1200, 1800, 3600]

    @Published private(set) var records: [Int: PowerDurationRecord] = [:]

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
        loadRecords()
    }

    // MARK: - Load Records

    func loadRecords() {
        let request: NSFetchRequest<PowerRecordEntity> = PowerRecordEntity.fetchRequest()

        do {
            let entities = try context.fetch(request)
            var loadedRecords: [Int: PowerDurationRecord] = [:]

            for entity in entities {
                let duration = Int(entity.duration)
                let record = PowerDurationRecord(
                    duration: duration,
                    power: Int(entity.power),
                    recordedAt: entity.recordedAt ?? Date(),
                    rideId: entity.rideId
                )

                // Keep only the best power for each duration
                if let existing = loadedRecords[duration] {
                    if record.power > existing.power {
                        loadedRecords[duration] = record
                    }
                } else {
                    loadedRecords[duration] = record
                }
            }

            DispatchQueue.main.async {
                self.records = loadedRecords
            }
        } catch {
            print("Error loading power records: \(error)")
        }
    }

    // MARK: - Update Records from Ride

    func updateFromSamples(_ samples: [TelemetrySample], rideId: UUID) {
        guard !samples.isEmpty else { return }

        var newRecords: [PowerDurationRecord] = []

        for duration in Self.standardDurations {
            if let bestPower = calculateBestPower(for: duration, from: samples) {
                // Check if this is a new record
                if let existing = records[duration] {
                    if bestPower > existing.power {
                        newRecords.append(PowerDurationRecord(
                            duration: duration,
                            power: bestPower,
                            recordedAt: Date(),
                            rideId: rideId
                        ))
                    }
                } else {
                    newRecords.append(PowerDurationRecord(
                        duration: duration,
                        power: bestPower,
                        recordedAt: Date(),
                        rideId: rideId
                    ))
                }
            }
        }

        // Save new records
        for record in newRecords {
            saveRecord(record)
        }

        loadRecords()
    }

    // MARK: - Calculate Best Power

    private func calculateBestPower(for durationSec: Int, from samples: [TelemetrySample]) -> Int? {
        guard samples.count >= durationSec else { return nil }

        var maxAvg = 0
        for i in 0...(samples.count - durationSec) {
            let window = samples[i..<(i + durationSec)]
            let sum = window.reduce(0) { $0 + $1.power }
            let avg = sum / durationSec
            maxAvg = max(maxAvg, avg)
        }
        return maxAvg > 0 ? maxAvg : nil
    }

    // MARK: - Save Record

    private func saveRecord(_ record: PowerDurationRecord) {
        // First, delete existing record for this duration
        let deleteRequest: NSFetchRequest<PowerRecordEntity> = PowerRecordEntity.fetchRequest()
        deleteRequest.predicate = NSPredicate(format: "duration == %d", record.duration)

        do {
            let existing = try context.fetch(deleteRequest)
            for entity in existing {
                context.delete(entity)
            }

            // Create new record
            let entity = PowerRecordEntity(context: context)
            entity.id = UUID()
            entity.duration = Int32(record.duration)
            entity.power = Int16(record.power)
            entity.recordedAt = record.recordedAt
            entity.rideId = record.rideId

            try context.save()
        } catch {
            print("Error saving power record: \(error)")
        }
    }

    // MARK: - Query Methods

    func bestPower(forDuration duration: Int) -> Int? {
        records[duration]?.power
    }

    func allRecords() -> [PowerDurationRecord] {
        Self.standardDurations.compactMap { records[$0] }
    }

    // MARK: - Formatted Output

    static func formatDuration(_ seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            return "\(seconds / 60)min"
        } else {
            return "\(seconds / 3600)h"
        }
    }
}

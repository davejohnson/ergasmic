import Foundation
import CoreData

class RideRepository: ObservableObject {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - CRUD Operations

    func fetchAll() -> [Ride] {
        let request: NSFetchRequest<RideEntity> = RideEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RideEntity.startedAt, ascending: false)]

        do {
            let entities = try context.fetch(request)
            return entities.map { toRide($0) }
        } catch {
            print("Error fetching rides: \(error)")
            return []
        }
    }

    func fetchRecent(limit: Int = 10) -> [Ride] {
        let request: NSFetchRequest<RideEntity> = RideEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \RideEntity.startedAt, ascending: false)]
        request.fetchLimit = limit

        do {
            let entities = try context.fetch(request)
            return entities.map { toRide($0) }
        } catch {
            print("Error fetching rides: \(error)")
            return []
        }
    }

    func save(_ ride: Ride) {
        let entity = findOrCreateEntity(for: ride.id)
        updateEntity(entity, from: ride)

        do {
            try context.save()
        } catch {
            print("Error saving ride: \(error)")
        }
    }

    func save(_ ride: Ride, withSamples samples: [TelemetrySample]) {
        let entity = findOrCreateEntity(for: ride.id)
        updateEntity(entity, from: ride)

        // Save telemetry samples
        for sample in samples {
            let sampleEntity = TelemetrySampleEntity(context: context)
            sampleEntity.id = UUID()
            sampleEntity.timestamp = sample.timestamp
            sampleEntity.elapsedSec = Int32(sample.elapsedSec)
            sampleEntity.power = Int16(sample.power)
            sampleEntity.heartRate = Int16(sample.heartRate ?? 0)
            sampleEntity.cadence = Int16(sample.cadence ?? 0)
            sampleEntity.ride = entity
        }

        do {
            try context.save()
        } catch {
            print("Error saving ride with samples: \(error)")
        }
    }

    func fetchSamples(for rideId: UUID) -> [TelemetrySample] {
        let request: NSFetchRequest<TelemetrySampleEntity> = TelemetrySampleEntity.fetchRequest()
        request.predicate = NSPredicate(format: "ride.id == %@", rideId as CVarArg)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \TelemetrySampleEntity.elapsedSec, ascending: true)]

        do {
            let entities = try context.fetch(request)
            return entities.map { entity in
                TelemetrySample(
                    timestamp: entity.timestamp ?? Date(),
                    elapsedSec: Int(entity.elapsedSec),
                    power: Int(entity.power),
                    heartRate: entity.heartRate > 0 ? Int(entity.heartRate) : nil,
                    cadence: entity.cadence > 0 ? Int(entity.cadence) : nil
                )
            }
        } catch {
            print("Error fetching samples: \(error)")
            return []
        }
    }

    func delete(_ ride: Ride) {
        let request: NSFetchRequest<RideEntity> = RideEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", ride.id as CVarArg)

        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            try context.save()
        } catch {
            print("Error deleting ride: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func findOrCreateEntity(for id: UUID) -> RideEntity {
        let request: NSFetchRequest<RideEntity> = RideEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let entity = RideEntity(context: context)
        entity.id = id
        return entity
    }

    private func updateEntity(_ entity: RideEntity, from ride: Ride) {
        entity.workoutId = ride.workoutId
        entity.workoutName = ride.workoutName
        entity.startedAt = ride.startedAt
        entity.endedAt = ride.endedAt
        entity.ftpUsed = Int32(ride.ftpUsed)
        entity.status = ride.status.rawValue
        entity.avgPower = Int32(ride.avgPower ?? 0)
        entity.avgHeartRate = Int32(ride.avgHeartRate ?? 0)
        entity.avgCadence = Int32(ride.avgCadence ?? 0)
        entity.durationSec = Int32(ride.durationSec)
        entity.normalizedPower = Int32(ride.normalizedPower ?? 0)
        entity.intensityFactor = ride.intensityFactor ?? 0
        entity.tss = ride.tss ?? 0
    }

    private func toRide(_ entity: RideEntity) -> Ride {
        Ride(
            id: entity.id ?? UUID(),
            workoutId: entity.workoutId,
            workoutName: entity.workoutName ?? "Unknown",
            startedAt: entity.startedAt ?? Date(),
            endedAt: entity.endedAt,
            ftpUsed: Int(entity.ftpUsed),
            status: RideStatus(rawValue: entity.status ?? "completed") ?? .completed,
            avgPower: entity.avgPower > 0 ? Int(entity.avgPower) : nil,
            avgHeartRate: entity.avgHeartRate > 0 ? Int(entity.avgHeartRate) : nil,
            avgCadence: entity.avgCadence > 0 ? Int(entity.avgCadence) : nil,
            durationSec: Int(entity.durationSec),
            normalizedPower: entity.normalizedPower > 0 ? Int(entity.normalizedPower) : nil,
            intensityFactor: entity.intensityFactor > 0 ? entity.intensityFactor : nil,
            tss: entity.tss > 0 ? entity.tss : nil
        )
    }
}

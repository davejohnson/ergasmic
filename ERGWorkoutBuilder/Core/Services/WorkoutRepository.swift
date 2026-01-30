import Foundation
import CoreData

class WorkoutRepository: ObservableObject {
    private let context: NSManagedObjectContext

    init(context: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.context = context
    }

    // MARK: - CRUD Operations

    func fetchAll() -> [Workout] {
        let request: NSFetchRequest<WorkoutEntity> = WorkoutEntity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \WorkoutEntity.updatedAt, ascending: false)]

        do {
            let entities = try context.fetch(request)
            return entities.map { toWorkout($0) }
        } catch {
            print("Error fetching workouts: \(error)")
            return []
        }
    }

    func fetch(id: UUID) -> Workout? {
        let request: NSFetchRequest<WorkoutEntity> = WorkoutEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        do {
            let entities = try context.fetch(request)
            return entities.first.map { toWorkout($0) }
        } catch {
            print("Error fetching workout: \(error)")
            return nil
        }
    }

    func save(_ workout: Workout) {
        let entity = findOrCreateEntity(for: workout.id)
        updateEntity(entity, from: workout)

        do {
            try context.save()
        } catch {
            print("Error saving workout: \(error)")
        }
    }

    func delete(_ workout: Workout) {
        let request: NSFetchRequest<WorkoutEntity> = WorkoutEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", workout.id as CVarArg)

        do {
            let entities = try context.fetch(request)
            for entity in entities {
                context.delete(entity)
            }
            try context.save()
        } catch {
            print("Error deleting workout: \(error)")
        }
    }

    func duplicate(_ workout: Workout) -> Workout {
        var newWorkout = workout
        newWorkout = Workout(
            id: UUID(),
            name: "\(workout.name) (Copy)",
            notes: workout.notes,
            steps: workout.steps.map { duplicateStep($0) },
            createdAt: Date(),
            updatedAt: Date()
        )
        save(newWorkout)
        return newWorkout
    }

    // MARK: - Private Helpers

    private func findOrCreateEntity(for id: UUID) -> WorkoutEntity {
        let request: NSFetchRequest<WorkoutEntity> = WorkoutEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let entity = WorkoutEntity(context: context)
        entity.id = id
        return entity
    }

    private func updateEntity(_ entity: WorkoutEntity, from workout: Workout) {
        entity.name = workout.name
        entity.notes = workout.notes
        entity.createdAt = workout.createdAt
        entity.updatedAt = Date()

        // Remove existing steps
        if let existingSteps = entity.steps?.array as? [WorkoutStepEntity] {
            for step in existingSteps {
                context.delete(step)
            }
        }

        // Add new steps
        let orderedSteps = NSMutableOrderedSet()
        for (index, step) in workout.steps.enumerated() {
            let stepEntity = createStepEntity(from: step, orderIndex: index)
            stepEntity.workout = entity
            orderedSteps.add(stepEntity)
        }
        entity.steps = orderedSteps
    }

    private func createStepEntity(from step: WorkoutStep, orderIndex: Int) -> WorkoutStepEntity {
        let entity = WorkoutStepEntity(context: context)
        entity.id = step.id
        entity.orderIndex = Int32(orderIndex)
        entity.type = step.type.rawValue
        entity.durationSec = Int32(step.durationSec)
        entity.intensityPct = Int32(step.intensityPct)
        entity.startPct = Int32(step.startPct)
        entity.endPct = Int32(step.endPct)
        entity.repeatCount = Int32(step.repeatCount)

        // Handle children for repeat blocks
        if step.type == .repeats {
            let orderedChildren = NSMutableOrderedSet()
            for (childIndex, child) in step.children.enumerated() {
                let childEntity = createStepEntity(from: child, orderIndex: childIndex)
                childEntity.parent = entity
                orderedChildren.add(childEntity)
            }
            entity.children = orderedChildren
        }

        return entity
    }

    private func toWorkout(_ entity: WorkoutEntity) -> Workout {
        let steps = (entity.steps?.array as? [WorkoutStepEntity])?.map { toWorkoutStep($0) } ?? []

        return Workout(
            id: entity.id ?? UUID(),
            name: entity.name ?? "Untitled",
            notes: entity.notes ?? "",
            steps: steps,
            createdAt: entity.createdAt ?? Date(),
            updatedAt: entity.updatedAt ?? Date()
        )
    }

    private func toWorkoutStep(_ entity: WorkoutStepEntity) -> WorkoutStep {
        let type = StepType(rawValue: entity.type ?? "steady") ?? .steady
        let children = (entity.children?.array as? [WorkoutStepEntity])?.map { toWorkoutStep($0) } ?? []

        return WorkoutStep(
            id: entity.id ?? UUID(),
            type: type,
            durationSec: Int(entity.durationSec),
            intensityPct: Int(entity.intensityPct),
            startPct: Int(entity.startPct),
            endPct: Int(entity.endPct),
            repeatCount: Int(entity.repeatCount),
            children: children
        )
    }

    private func duplicateStep(_ step: WorkoutStep) -> WorkoutStep {
        WorkoutStep(
            id: UUID(),
            type: step.type,
            durationSec: step.durationSec,
            intensityPct: step.intensityPct,
            startPct: step.startPct,
            endPct: step.endPct,
            repeatCount: step.repeatCount,
            children: step.children.map { duplicateStep($0) }
        )
    }
}

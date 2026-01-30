import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "ERGWorkoutBuilder")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: - Preview Support

    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Create sample workouts for preview
        for i in 1...3 {
            let workout = WorkoutEntity(context: context)
            workout.id = UUID()
            workout.name = "Sample Workout \(i)"
            workout.notes = "A sample workout for preview"
            workout.createdAt = Date()
            workout.updatedAt = Date()

            let step1 = WorkoutStepEntity(context: context)
            step1.id = UUID()
            step1.orderIndex = 0
            step1.type = "steady"
            step1.durationSec = 300
            step1.intensityPct = 50
            step1.workout = workout

            let step2 = WorkoutStepEntity(context: context)
            step2.id = UUID()
            step2.orderIndex = 1
            step2.type = "ramp"
            step2.durationSec = 600
            step2.startPct = 50
            step2.endPct = 100
            step2.workout = workout

            let step3 = WorkoutStepEntity(context: context)
            step3.id = UUID()
            step3.orderIndex = 2
            step3.type = "steady"
            step3.durationSec = 300
            step3.intensityPct = 50
            step3.workout = workout
        }

        do {
            try context.save()
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return controller
    }()

    // MARK: - Save Context

    func save() {
        let context = container.viewContext
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                let nsError = error as NSError
                print("Error saving context: \(nsError), \(nsError.userInfo)")
            }
        }
    }
}

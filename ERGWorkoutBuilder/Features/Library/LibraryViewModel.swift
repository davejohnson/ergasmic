import Foundation
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let repository = WorkoutRepository()

    func loadWorkouts() {
        isLoading = true
        seedDefaultWorkoutsIfNeeded()
        workouts = repository.fetchAll()
        isLoading = false
    }

    private func seedDefaultWorkoutsIfNeeded() {
        let key = "hasSeededDefaultWorkouts"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        for workout in DefaultWorkouts.all {
            repository.save(workout)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    func save(_ workout: Workout) {
        repository.save(workout)
        loadWorkouts()
    }

    func delete(_ workout: Workout) {
        repository.delete(workout)
        loadWorkouts()
    }

    func duplicate(_ workout: Workout) {
        _ = repository.duplicate(workout)
        loadWorkouts()
    }
}

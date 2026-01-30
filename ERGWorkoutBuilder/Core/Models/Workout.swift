import Foundation

struct Workout: Identifiable, Equatable {
    let id: UUID
    var name: String
    var notes: String
    var steps: [WorkoutStep]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "New Workout",
        notes: String = "",
        steps: [WorkoutStep] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        self.steps = steps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var totalDurationSec: Int {
        steps.reduce(0) { $0 + $1.totalDurationSec }
    }

    var formattedDuration: String {
        formatDuration(totalDurationSec)
    }
}

func formatDuration(_ seconds: Int) -> String {
    let hours = seconds / 3600
    let minutes = (seconds % 3600) / 60
    let secs = seconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else {
        return String(format: "%d:%02d", minutes, secs)
    }
}

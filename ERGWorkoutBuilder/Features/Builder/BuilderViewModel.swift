import Foundation
import Combine

@MainActor
class BuilderViewModel: ObservableObject {
    @Published var name: String
    @Published var notes: String
    @Published var steps: [WorkoutStep]
    @Published var showStepEditor = false
    @Published var showChildEditor = false
    @Published var editingStepIndex: Int?
    @Published var editingChildIndex: Int?

    let isNew: Bool
    private let originalId: UUID
    private let createdAt: Date

    init(workout: Workout) {
        self.originalId = workout.id
        self.name = workout.name
        self.notes = workout.notes
        self.steps = workout.steps
        self.isNew = workout.steps.isEmpty
        self.createdAt = workout.createdAt
    }

    // MARK: - Templates

    enum WorkoutTemplate: String, CaseIterable, Identifiable {
        case blank = "Blank"
        case endurance = "Endurance"
        case sweetSpot = "Sweet Spot"
        case vo2max = "VO2max Intervals"
        case threshold = "Threshold"
        case recovery = "Recovery"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .blank: return "plus"
            case .endurance: return "figure.outdoor.cycle"
            case .sweetSpot: return "flame"
            case .vo2max: return "bolt.fill"
            case .threshold: return "gauge.with.dots.needle.33percent"
            case .recovery: return "leaf"
            }
        }

        var description: String {
            switch self {
            case .blank: return "Start from scratch"
            case .endurance: return "60 min zone 2"
            case .sweetSpot: return "3×10 min at 88-94%"
            case .vo2max: return "5×3 min at 120%"
            case .threshold: return "2×20 min at 100%"
            case .recovery: return "30 min easy spin"
            }
        }
    }

    func applyTemplate(_ template: WorkoutTemplate) {
        switch template {
        case .blank:
            name = "New Workout"
            steps = []

        case .endurance:
            name = "Endurance Ride"
            steps = [
                .ramp(durationSec: 600, startPct: 40, endPct: 65),
                .steady(durationSec: 2400, intensityPct: 65),
                .steady(durationSec: 600, intensityPct: 50),
            ]

        case .sweetSpot:
            name = "Sweet Spot"
            steps = [
                .ramp(durationSec: 600, startPct: 40, endPct: 70),
                .repeats(count: 3, children: [
                    .steady(durationSec: 600, intensityPct: 90),
                    .steady(durationSec: 300, intensityPct: 50),
                ]),
                .steady(durationSec: 300, intensityPct: 40),
            ]

        case .vo2max:
            name = "VO2max Intervals"
            steps = [
                .ramp(durationSec: 600, startPct: 40, endPct: 75),
                .steady(durationSec: 300, intensityPct: 90),
                .steady(durationSec: 120, intensityPct: 50),
                .repeats(count: 5, children: [
                    .steady(durationSec: 180, intensityPct: 120),
                    .steady(durationSec: 180, intensityPct: 50),
                ]),
                .steady(durationSec: 300, intensityPct: 40),
            ]

        case .threshold:
            name = "Threshold Intervals"
            steps = [
                .ramp(durationSec: 600, startPct: 40, endPct: 75),
                .repeats(count: 2, children: [
                    .steady(durationSec: 1200, intensityPct: 100),
                    .steady(durationSec: 300, intensityPct: 50),
                ]),
                .steady(durationSec: 300, intensityPct: 40),
            ]

        case .recovery:
            name = "Recovery Spin"
            steps = [
                .steady(durationSec: 300, intensityPct: 40),
                .steady(durationSec: 1200, intensityPct: 50),
                .steady(durationSec: 300, intensityPct: 40),
            ]
        }
    }

    // MARK: - Computed Properties

    var totalDuration: String {
        let totalSec = steps.reduce(0) { $0 + $1.totalDurationSec }
        return formatDuration(totalSec)
    }

    var isValid: Bool {
        validationError == nil
    }

    var validationError: String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Workout name is required"
        }

        if steps.isEmpty {
            return "Add at least one step"
        }

        let totalSec = steps.reduce(0) { $0 + $1.totalDurationSec }
        if totalSec > 3 * 60 * 60 {
            return "Total duration cannot exceed 3 hours"
        }

        for step in steps {
            if let error = step.validate() {
                return error.localizedDescription
            }
        }

        return nil
    }

    // MARK: - Actions

    func addSteadyStep() {
        let step = WorkoutStep.steady(durationSec: 300, intensityPct: 100)
        steps.append(step)
    }

    func addRampStep() {
        let step = WorkoutStep.ramp(durationSec: 300, startPct: 50, endPct: 100)
        steps.append(step)
    }

    func addRepeatBlock() {
        let interval = WorkoutStep.steady(durationSec: 60, intensityPct: 120)
        let recovery = WorkoutStep.steady(durationSec: 60, intensityPct: 50)
        let step = WorkoutStep.repeats(count: 5, children: [interval, recovery])
        steps.append(step)
    }

    func addHRTargetStep() {
        let step = WorkoutStep.hrTarget(durationSec: 600, lowBpm: 130, highBpm: 150)
        steps.append(step)
    }

    func buildWorkout() -> Workout? {
        guard isValid else { return nil }

        return Workout(
            id: originalId,
            name: name.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces),
            steps: steps,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

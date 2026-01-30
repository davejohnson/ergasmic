import Foundation
import CoreData
import Combine

/// Performance Condition: A real-time metric showing if you're performing above or below
/// your expected power output for a given heart rate, similar to Garmin's Performance Condition.
///
/// Range: -20 to +20
/// - Positive: Performing better than expected (fresher, more power at same HR)
/// - Negative: Performing worse than expected (fatigued, less power at same HR)
/// - Zero: Performing as expected

struct PerformanceConditionResult {
    let value: Int  // -20 to +20
    let isAvailable: Bool
    let reason: String?

    static let unavailable = PerformanceConditionResult(
        value: 0,
        isAvailable: false,
        reason: "Not enough data"
    )

    static let buildingBaseline = PerformanceConditionResult(
        value: 0,
        isAvailable: false,
        reason: "Building baseline..."
    )

    static let needsMoreWorkouts = PerformanceConditionResult(
        value: 0,
        isAvailable: false,
        reason: "Need 5+ workouts with HR data"
    )

    static let waitingForData = PerformanceConditionResult(
        value: 0,
        isAvailable: false,
        reason: "Warming up (6+ min needed)"
    )
}

/// HR:Power baseline data point
struct HRPowerDataPoint {
    let hrPercent: Int   // % of max HR (e.g., 70, 80, 90)
    let avgPower: Int    // Average power observed at this HR level
    let sampleCount: Int // Number of samples contributing to this average
}

/// Analyzes performance in real-time during workouts
class PerformanceAnalyzer: ObservableObject {
    private let context: NSManagedObjectContext
    private let settingsService: SettingsService

    // Minimum workouts with HR data before showing performance condition
    static let minimumBaselineWorkouts = 5

    @Published private(set) var baseline: [Int: HRPowerDataPoint] = [:]  // Keyed by HR percent
    @Published private(set) var baselineWorkoutCount: Int = 0

    private var cancellables = Set<AnyCancellable>()

    init(
        context: NSManagedObjectContext = PersistenceController.shared.container.viewContext,
        settingsService: SettingsService
    ) {
        self.context = context
        self.settingsService = settingsService
        loadBaseline()
    }

    // MARK: - Baseline Management

    func loadBaseline() {
        let request: NSFetchRequest<HRPowerBaselineEntity> = HRPowerBaselineEntity.fetchRequest()

        do {
            let entities = try context.fetch(request)
            var loadedBaseline: [Int: HRPowerDataPoint] = [:]

            for entity in entities {
                let hrPercent = Int(entity.hrPercent)
                loadedBaseline[hrPercent] = HRPowerDataPoint(
                    hrPercent: hrPercent,
                    avgPower: Int(entity.avgPower),
                    sampleCount: Int(entity.sampleCount)
                )
            }

            DispatchQueue.main.async {
                self.baseline = loadedBaseline
                self.baselineWorkoutCount = self.countBaselineWorkouts()
            }
        } catch {
            print("Error loading HR:Power baseline: \(error)")
        }
    }

    private func countBaselineWorkouts() -> Int {
        // Count rides with HR data
        let request: NSFetchRequest<RideEntity> = RideEntity.fetchRequest()
        request.predicate = NSPredicate(format: "avgHeartRate > 0")

        do {
            return try context.count(for: request)
        } catch {
            return 0
        }
    }

    // MARK: - Update Baseline from Ride

    func updateBaseline(from samples: [TelemetrySample], maxHR: Int) {
        guard maxHR > 0 else { return }

        // Group samples by HR percent (rounded to nearest 5%)
        var hrPowerGroups: [Int: [Int]] = [:]

        for sample in samples {
            guard let hr = sample.heartRate, hr > 0 else { continue }

            let hrPercent = Int(Double(hr) / Double(maxHR) * 100.0)
            // Round to nearest 5%
            let roundedHRPercent = (hrPercent / 5) * 5

            if hrPowerGroups[roundedHRPercent] == nil {
                hrPowerGroups[roundedHRPercent] = []
            }
            hrPowerGroups[roundedHRPercent]?.append(sample.power)
        }

        // Update baseline with new data
        for (hrPercent, powers) in hrPowerGroups {
            let avgPower = powers.reduce(0, +) / powers.count
            let sampleCount = powers.count

            updateBaselineDataPoint(hrPercent: hrPercent, avgPower: avgPower, sampleCount: sampleCount)
        }

        loadBaseline()
    }

    private func updateBaselineDataPoint(hrPercent: Int, avgPower: Int, sampleCount: Int) {
        let request: NSFetchRequest<HRPowerBaselineEntity> = HRPowerBaselineEntity.fetchRequest()
        request.predicate = NSPredicate(format: "hrPercent == %d", hrPercent)
        request.fetchLimit = 1

        do {
            let existing = try context.fetch(request).first

            if let entity = existing {
                // Update with weighted average
                let totalSamples = Int(entity.sampleCount) + sampleCount
                let weightedAvg = (Int(entity.avgPower) * Int(entity.sampleCount) + avgPower * sampleCount) / totalSamples

                entity.avgPower = Int16(weightedAvg)
                entity.sampleCount = Int32(totalSamples)
                entity.updatedAt = Date()
            } else {
                // Create new baseline point
                let entity = HRPowerBaselineEntity(context: context)
                entity.id = UUID()
                entity.hrPercent = Int16(hrPercent)
                entity.avgPower = Int16(avgPower)
                entity.sampleCount = Int32(sampleCount)
                entity.updatedAt = Date()
            }

            try context.save()
        } catch {
            print("Error updating baseline: \(error)")
        }
    }

    // MARK: - Real-Time Performance Condition

    func calculatePerformanceCondition(
        currentPower: Int,
        currentHR: Int,
        rolling5MinPower: Int?,
        rolling5MinHR: Int?,
        elapsedSeconds: Int
    ) -> PerformanceConditionResult {

        // Check if we have enough baseline data
        guard baselineWorkoutCount >= Self.minimumBaselineWorkouts else {
            return .needsMoreWorkouts
        }

        // Need at least 6 minutes of workout data
        guard elapsedSeconds >= 360 else {
            return .waitingForData
        }

        // Need rolling averages
        guard let avgPower = rolling5MinPower,
              let avgHR = rolling5MinHR else {
            return .unavailable
        }

        let maxHR = settingsService.maxHR
        guard maxHR > 0 else { return .unavailable }

        // Calculate expected power for current HR
        let hrPercent = Int(Double(avgHR) / Double(maxHR) * 100.0)
        let roundedHRPercent = (hrPercent / 5) * 5

        guard let expectedPowerPoint = findExpectedPower(forHRPercent: roundedHRPercent) else {
            return .unavailable
        }

        let expectedPower = expectedPowerPoint.avgPower
        guard expectedPower > 0 else { return .unavailable }

        // Calculate deviation as percentage
        let deviation = Double(avgPower - expectedPower) / Double(expectedPower) * 100.0

        // Scale to -20 to +20 range (roughly 2x the percentage deviation)
        let rawValue = deviation * 2.0
        let clampedValue = max(-20.0, min(20.0, rawValue))

        return PerformanceConditionResult(
            value: Int(clampedValue.rounded()),
            isAvailable: true,
            reason: nil
        )
    }

    private func findExpectedPower(forHRPercent targetPercent: Int) -> HRPowerDataPoint? {
        // Try exact match first
        if let exact = baseline[targetPercent] {
            return exact
        }

        // Find nearest available data point
        let availablePercents = baseline.keys.sorted()
        guard !availablePercents.isEmpty else { return nil }

        // Find closest
        let closest = availablePercents.min { abs($0 - targetPercent) < abs($1 - targetPercent) }
        return closest.flatMap { baseline[$0] }
    }

    // MARK: - Baseline Access

    /// Returns baseline data points sorted by HR percent ascending, for LTHR detection.
    func getBaselineDataPoints() -> [HRPowerDataPoint] {
        baseline.values.sorted { $0.hrPercent < $1.hrPercent }
    }

    // MARK: - Status Helpers

    var isBaselineReady: Bool {
        baselineWorkoutCount >= Self.minimumBaselineWorkouts
    }

    var baselineProgress: Double {
        min(1.0, Double(baselineWorkoutCount) / Double(Self.minimumBaselineWorkouts))
    }

    var baselineStatusText: String {
        if isBaselineReady {
            return "Baseline ready"
        } else {
            return "\(baselineWorkoutCount)/\(Self.minimumBaselineWorkouts) workouts"
        }
    }
}

// MARK: - Performance Condition Display Helpers

extension PerformanceConditionResult {
    var displayText: String {
        guard isAvailable else {
            return reason ?? "N/A"
        }
        return value >= 0 ? "+\(value)" : "\(value)"
    }

    var color: String {
        guard isAvailable else { return "secondary" }

        if value >= 5 {
            return "green"
        } else if value <= -5 {
            return "red"
        } else {
            return "yellow"
        }
    }

    var icon: String {
        guard isAvailable else { return "minus" }

        if value >= 5 {
            return "arrow.up"
        } else if value <= -5 {
            return "arrow.down"
        } else {
            return "minus"
        }
    }
}

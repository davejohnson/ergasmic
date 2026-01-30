import Foundation
import HealthKit

/// Represents a sleep sample from HealthKit
struct SleepSample {
    let startDate: Date
    let endDate: Date
    let value: HKCategoryValueSleepAnalysis

    var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    var isAsleep: Bool {
        switch value {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        default:
            return false
        }
    }
}

/// Represents a heart rate sample from HealthKit
struct HRSample {
    let date: Date
    let value: Double  // bpm
}

/// Represents an HRV sample from HealthKit
struct HRVSample {
    let date: Date
    let value: Double  // SDNN in milliseconds
}

/// Represents an external cycling workout from HealthKit (e.g., Garmin outdoor ride)
struct ExternalWorkout: Identifiable {
    let id: UUID
    let startDate: Date
    let endDate: Date
    let duration: TimeInterval
    let totalDistance: Double?  // meters
    let totalEnergyBurned: Double?  // kcal
    let averageHeartRate: Double?
    let averagePower: Double?  // watts, if available
    let sourceName: String  // e.g., "Garmin Connect"
    let activityType: String  // e.g., "Cycling", "Soccer", "Cross Country Skiing"

    var durationMinutes: Int {
        Int(duration / 60)
    }

    var distanceKm: Double? {
        guard let meters = totalDistance else { return nil }
        return meters / 1000.0
    }

    var distanceMiles: Double? {
        guard let meters = totalDistance else { return nil }
        return meters / 1609.34
    }

    /// Estimate TSS from the workout if we have power, otherwise estimate from HR and duration
    func estimatedTSS(ftp: Int, restingHR: Int, maxHR: Int) -> Double? {
        if let avgPower = averagePower, ftp > 0 {
            // TSS = (duration_seconds * NP * IF) / (FTP * 3600) * 100
            // Simplified: assume NP ≈ avgPower for external rides
            let intensityFactor = avgPower / Double(ftp)
            return (duration * avgPower * intensityFactor) / (Double(ftp) * 3600) * 100
        } else if let avgHR = averageHeartRate {
            // Estimate TSS from HR using TRIMP-like calculation
            let hrReserve = Double(maxHR - restingHR)
            guard hrReserve > 0 else { return nil }
            let hrRatio = (avgHR - Double(restingHR)) / hrReserve
            // Rough estimation: 1 hour at 70% HRR ≈ 50 TSS
            let hoursRidden = duration / 3600.0
            return hoursRidden * hrRatio * 70
        }
        return nil
    }
}

/// Sleep summary for a night
struct SleepSummary {
    let date: Date
    let totalSleepDuration: TimeInterval
    let deepSleepDuration: TimeInterval?
    let remSleepDuration: TimeInterval?
    let awakenings: Int

    var totalSleepHours: Double {
        totalSleepDuration / 3600.0
    }

    var sleepQuality: SleepQuality {
        let hours = totalSleepHours
        if hours >= 7.5 {
            return .good
        } else if hours >= 6.0 {
            return .fair
        } else {
            return .poor
        }
    }

    enum SleepQuality: String {
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"
    }
}

/// Manages all HealthKit interactions
class HealthKitManager: ObservableObject {
    private let healthStore = HKHealthStore()

    @Published private(set) var isAuthorized = false
    @Published private(set) var authorizationError: String?

    // Types we want to read
    private let readTypes: Set<HKObjectType> = {
        var types: Set<HKObjectType> = []

        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        if let restingHRType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) {
            types.insert(restingHRType)
        }
        if let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) {
            types.insert(hrvType)
        }
        if let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) {
            types.insert(activeEnergyType)
        }
        if let hrType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(hrType)
        }

        // Cycling workouts (for importing outdoor rides from Garmin, etc.)
        types.insert(HKObjectType.workoutType())

        return types
    }()

    // MARK: - Authorization

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: readTypes)
            await MainActor.run {
                self.isAuthorized = true
                self.authorizationError = nil
            }
        } catch {
            await MainActor.run {
                self.isAuthorized = false
                self.authorizationError = error.localizedDescription
            }
            throw error
        }
    }

    // MARK: - Sleep Data

    func fetchSleepData(for dateRange: DateInterval) async throws -> [SleepSample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: dateRange.start,
            end: dateRange.end,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let sleepSamples = (samples as? [HKCategorySample])?.compactMap { sample -> SleepSample? in
                    guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else {
                        return nil
                    }
                    return SleepSample(
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        value: value
                    )
                } ?? []

                continuation.resume(returning: sleepSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchLastNightSleep() async throws -> SleepSummary? {
        let now = Date()
        let calendar = Calendar.current

        // Look for sleep from yesterday evening to this morning
        guard let lastNightStart = calendar.date(byAdding: .hour, value: -24, to: now) else {
            return nil
        }

        let samples = try await fetchSleepData(for: DateInterval(start: lastNightStart, end: now))

        // Filter to only actual sleep samples
        let sleepSamples = samples.filter { $0.isAsleep }
        guard !sleepSamples.isEmpty else { return nil }

        let totalSleep = sleepSamples.reduce(0.0) { $0 + $1.duration }

        let deepSleep = sleepSamples
            .filter { $0.value == .asleepDeep }
            .reduce(0.0) { $0 + $1.duration }

        let remSleep = sleepSamples
            .filter { $0.value == .asleepREM }
            .reduce(0.0) { $0 + $1.duration }

        // Count awakenings
        let awakeCount = samples.filter { $0.value == .awake }.count

        return SleepSummary(
            date: lastNightStart,
            totalSleepDuration: totalSleep,
            deepSleepDuration: deepSleep > 0 ? deepSleep : nil,
            remSleepDuration: remSleep > 0 ? remSleep : nil,
            awakenings: awakeCount
        )
    }

    // MARK: - Resting Heart Rate

    func fetchRestingHR(for dateRange: DateInterval) async throws -> [HRSample] {
        guard let hrType = HKObjectType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: dateRange.start,
            end: dateRange.end,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let hrSamples = (samples as? [HKQuantitySample])?.map { sample in
                    HRSample(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    )
                } ?? []

                continuation.resume(returning: hrSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchLatestRestingHR() async throws -> HRSample? {
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        let samples = try await fetchRestingHR(for: DateInterval(start: oneWeekAgo, end: now))
        return samples.last
    }

    // MARK: - HRV (SDNN)

    func fetchHRV(for dateRange: DateInterval) async throws -> [HRVSample] {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: dateRange.start,
            end: dateRange.end,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: hrvType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let hrvSamples = (samples as? [HKQuantitySample])?.map { sample in
                    HRVSample(
                        date: sample.startDate,
                        value: sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                    )
                } ?? []

                continuation.resume(returning: hrvSamples)
            }

            healthStore.execute(query)
        }
    }

    func fetchLatestHRV() async throws -> HRVSample? {
        let now = Date()
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now

        let samples = try await fetchHRV(for: DateInterval(start: oneWeekAgo, end: now))
        return samples.last
    }

    func fetchHRVTrend(days: Int = 7) async throws -> (current: Double?, trend: HRVTrend) {
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        let samples = try await fetchHRV(for: DateInterval(start: startDate, end: now))
        guard samples.count >= 2 else {
            return (samples.first?.value, .unknown)
        }

        let midpoint = samples.count / 2
        let firstHalf = samples.prefix(midpoint)
        let secondHalf = samples.suffix(samples.count - midpoint)

        let firstAvg = firstHalf.reduce(0.0) { $0 + $1.value } / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0.0) { $0 + $1.value } / Double(secondHalf.count)

        let percentChange = (secondAvg - firstAvg) / firstAvg * 100.0

        let trend: HRVTrend
        if percentChange > 5 {
            trend = .improving
        } else if percentChange < -5 {
            trend = .declining
        } else {
            trend = .stable
        }

        return (samples.last?.value, trend)
    }

    enum HRVTrend: String {
        case improving = "Improving"
        case stable = "Stable"
        case declining = "Declining"
        case unknown = "Unknown"
    }

    // MARK: - Active Calories

    func fetchActiveCalories(for date: Date) async throws -> Double {
        guard let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.typeNotAvailable
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? date

        let predicate = HKQuery.predicateForSamples(
            withStart: startOfDay,
            end: endOfDay,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let calories = statistics?.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? 0
                continuation.resume(returning: calories)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Cycling Workouts (External rides from Garmin, etc.)

    func fetchCyclingWorkouts(for dateRange: DateInterval) async throws -> [ExternalWorkout] {
        let workoutType = HKObjectType.workoutType()

        // Filter for cycling workouts only
        let cyclingPredicate = HKQuery.predicateForWorkouts(with: .cycling)
        let datePredicate = HKQuery.predicateForSamples(
            withStart: dateRange.start,
            end: dateRange.end,
            options: .strictStartDate
        )
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [cyclingPredicate, datePredicate])

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout])?.map { workout -> ExternalWorkout in
                    let sourceName = workout.sourceRevision.source.name

                    // Extract statistics if available
                    let avgHR = workout.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?
                        .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

                    let avgPower = workout.statistics(for: HKQuantityType(.cyclingPower))?
                        .averageQuantity()?
                        .doubleValue(for: HKUnit.watt())

                    return ExternalWorkout(
                        id: workout.uuid,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        totalDistance: workout.totalDistance?.doubleValue(for: HKUnit.meter()),
                        totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()),
                        averageHeartRate: avgHR,
                        averagePower: avgPower,
                        sourceName: sourceName,
                        activityType: Self.activityTypeName(workout.workoutActivityType)
                    )
                } ?? []

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    func fetchRecentCyclingWorkouts(days: Int = 7) async throws -> [ExternalWorkout] {
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now

        return try await fetchCyclingWorkouts(for: DateInterval(start: startDate, end: now))
    }

    func fetchWeeklyCyclingTSS(ftp: Int, restingHR: Int, maxHR: Int) async throws -> Double {
        let workouts = try await fetchRecentCyclingWorkouts(days: 7)

        return workouts.compactMap { workout in
            workout.estimatedTSS(ftp: ftp, restingHR: restingHR, maxHR: maxHR)
        }.reduce(0.0, +)
    }

    // MARK: - All Workouts (all activity types)

    func fetchAllWorkouts(for dateRange: DateInterval) async throws -> [ExternalWorkout] {
        let workoutType = HKObjectType.workoutType()

        let datePredicate = HKQuery.predicateForSamples(
            withStart: dateRange.start,
            end: dateRange.end,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: workoutType,
                predicate: datePredicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = (samples as? [HKWorkout])?.map { workout -> ExternalWorkout in
                    let sourceName = workout.sourceRevision.source.name

                    let avgHR = workout.statistics(for: HKQuantityType(.heartRate))?
                        .averageQuantity()?
                        .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))

                    let avgPower: Double?
                    if workout.workoutActivityType == .cycling {
                        avgPower = workout.statistics(for: HKQuantityType(.cyclingPower))?
                            .averageQuantity()?
                            .doubleValue(for: HKUnit.watt())
                    } else {
                        avgPower = nil
                    }

                    return ExternalWorkout(
                        id: workout.uuid,
                        startDate: workout.startDate,
                        endDate: workout.endDate,
                        duration: workout.duration,
                        totalDistance: workout.totalDistance?.doubleValue(for: HKUnit.meter()),
                        totalEnergyBurned: workout.totalEnergyBurned?.doubleValue(for: HKUnit.kilocalorie()),
                        averageHeartRate: avgHR,
                        averagePower: avgPower,
                        sourceName: sourceName,
                        activityType: Self.activityTypeName(workout.workoutActivityType)
                    )
                } ?? []

                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    func fetchRecentAllWorkouts(days: Int = 7) async throws -> [ExternalWorkout] {
        let now = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        return try await fetchAllWorkouts(for: DateInterval(start: startDate, end: now))
    }

    static func activityTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .crossCountrySkiing: return "Nordic Skiing"
        case .downhillSkiing: return "Downhill Skiing"
        case .soccer: return "Soccer"
        case .yoga: return "Yoga"
        case .functionalStrengthTraining: return "Strength Training"
        case .traditionalStrengthTraining: return "Strength Training"
        case .coreTraining: return "Core Training"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .highIntensityIntervalTraining: return "HIIT"
        case .dance: return "Dance"
        case .tennis: return "Tennis"
        case .basketball: return "Basketball"
        case .snowboarding: return "Snowboarding"
        default: return "Workout"
        }
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case typeNotAvailable
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .typeNotAvailable:
            return "The requested health data type is not available"
        case .unauthorized:
            return "HealthKit access has not been authorized"
        }
    }
}

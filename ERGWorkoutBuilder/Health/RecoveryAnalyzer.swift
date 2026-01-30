import Foundation
import Combine

/// Recovery status based on multiple factors
struct RecoveryStatus {
    let score: Int  // 1-100
    let level: RecoveryLevel
    let factors: [RecoveryFactor]
    let suggestedIntensity: SuggestedIntensity

    enum RecoveryLevel: String {
        case excellent = "Excellent"
        case good = "Good"
        case fair = "Fair"
        case poor = "Poor"

        var color: String {
            switch self {
            case .excellent: return "green"
            case .good: return "blue"
            case .fair: return "yellow"
            case .poor: return "red"
            }
        }
    }

    enum SuggestedIntensity: String {
        case high = "Ready for high intensity"
        case moderate = "Moderate intensity recommended"
        case low = "Low intensity or rest recommended"
        case rest = "Rest day recommended"
    }
}

/// Individual factor contributing to recovery score
struct RecoveryFactor {
    let name: String
    let value: String
    let score: Int  // 0-100 contribution
    let weight: Double  // How much this factor matters
    let trend: Trend?

    enum Trend: String {
        case improving = "up"
        case stable = "stable"
        case declining = "down"
    }
}

/// Analyzes recovery status from HealthKit data and training load
class RecoveryAnalyzer: ObservableObject {
    private let healthKitManager: HealthKitManager
    private let rideRepository: RideRepository
    private let settingsService: SettingsService

    @Published private(set) var currentStatus: RecoveryStatus?
    @Published private(set) var isAnalyzing = false

    private var cancellables = Set<AnyCancellable>()

    init(
        healthKitManager: HealthKitManager,
        rideRepository: RideRepository,
        settingsService: SettingsService
    ) {
        self.healthKitManager = healthKitManager
        self.rideRepository = rideRepository
        self.settingsService = settingsService
    }

    // MARK: - Analysis

    @MainActor
    func analyze() async {
        isAnalyzing = true
        defer { isAnalyzing = false }

        var factors: [RecoveryFactor] = []

        // 1. Sleep factor (weight: 0.35)
        if let sleepFactor = await analyzeSleep() {
            factors.append(sleepFactor)
        }

        // 2. HRV factor (weight: 0.30)
        if let hrvFactor = await analyzeHRV() {
            factors.append(hrvFactor)
        }

        // 3. Resting HR factor (weight: 0.15)
        if let restingHRFactor = await analyzeRestingHR() {
            factors.append(restingHRFactor)
        }

        // 4. Training load factor (weight: 0.20) - includes external rides from HealthKit
        await fetchExternalTrainingLoad()
        let trainingLoadFactor = analyzeTrainingLoad()
        factors.append(trainingLoadFactor)

        // Calculate overall score
        guard !factors.isEmpty else {
            currentStatus = nil
            return
        }

        let totalWeight = factors.reduce(0.0) { $0 + $1.weight }
        let weightedScore = factors.reduce(0.0) { sum, factor in
            sum + Double(factor.score) * factor.weight
        }
        let normalizedScore = Int((weightedScore / totalWeight).rounded())

        let level = determineLevel(from: normalizedScore)
        let intensity = determineSuggestedIntensity(from: normalizedScore, factors: factors)

        currentStatus = RecoveryStatus(
            score: normalizedScore,
            level: level,
            factors: factors,
            suggestedIntensity: intensity
        )
    }

    // MARK: - Individual Factor Analysis

    private func analyzeSleep() async -> RecoveryFactor? {
        do {
            guard let sleep = try await healthKitManager.fetchLastNightSleep() else {
                return nil
            }

            let hours = sleep.totalSleepHours
            let score: Int

            if hours >= 8.0 {
                score = 100
            } else if hours >= 7.0 {
                score = 80
            } else if hours >= 6.0 {
                score = 60
            } else if hours >= 5.0 {
                score = 40
            } else {
                score = 20
            }

            return RecoveryFactor(
                name: "Sleep",
                value: String(format: "%.1f hours", hours),
                score: score,
                weight: 0.35,
                trend: nil
            )
        } catch {
            print("Error analyzing sleep: \(error)")
            return nil
        }
    }

    private func analyzeHRV() async -> RecoveryFactor? {
        do {
            let (currentHRV, trend) = try await healthKitManager.fetchHRVTrend(days: 7)

            guard let hrv = currentHRV else { return nil }

            // Score based on absolute HRV value and trend
            // Higher HRV generally indicates better recovery
            // These thresholds are general and vary significantly by individual
            let baseScore: Int
            if hrv >= 60 {
                baseScore = 90
            } else if hrv >= 45 {
                baseScore = 75
            } else if hrv >= 30 {
                baseScore = 55
            } else {
                baseScore = 35
            }

            // Adjust for trend
            let trendAdjustment: Int
            switch trend {
            case .improving:
                trendAdjustment = 10
            case .stable:
                trendAdjustment = 0
            case .declining:
                trendAdjustment = -15
            case .unknown:
                trendAdjustment = 0
            }

            let finalScore = max(0, min(100, baseScore + trendAdjustment))

            let factorTrend: RecoveryFactor.Trend?
            switch trend {
            case .improving: factorTrend = .improving
            case .declining: factorTrend = .declining
            case .stable, .unknown: factorTrend = .stable
            }

            return RecoveryFactor(
                name: "HRV",
                value: String(format: "%.0f ms", hrv),
                score: finalScore,
                weight: 0.30,
                trend: factorTrend
            )
        } catch {
            print("Error analyzing HRV: \(error)")
            return nil
        }
    }

    private func analyzeRestingHR() async -> RecoveryFactor? {
        do {
            guard let latestRHR = try await healthKitManager.fetchLatestRestingHR() else {
                return nil
            }

            let rhr = latestRHR.value
            let baseline = Double(settingsService.restingHR)

            // Compare to baseline
            let percentAboveBaseline = (rhr - baseline) / baseline * 100.0

            let score: Int
            if percentAboveBaseline <= 0 {
                score = 100  // At or below baseline
            } else if percentAboveBaseline <= 5 {
                score = 80
            } else if percentAboveBaseline <= 10 {
                score = 60
            } else if percentAboveBaseline <= 15 {
                score = 40
            } else {
                score = 20  // Significantly elevated
            }

            return RecoveryFactor(
                name: "Resting HR",
                value: String(format: "%.0f bpm", rhr),
                score: score,
                weight: 0.15,
                trend: nil
            )
        } catch {
            print("Error analyzing resting HR: \(error)")
            return nil
        }
    }

    private func analyzeTrainingLoad() -> RecoveryFactor {
        // Calculate 7-day TSS load from in-app rides
        let recentRides = rideRepository.fetchRecent(limit: 30)
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let inAppTSS = recentRides
            .filter { $0.startedAt >= oneWeekAgo }
            .compactMap { $0.tss }
            .reduce(0.0, +)

        // External TSS will be added asynchronously
        let weeklyTSS = inAppTSS + (externalWeeklyTSS ?? 0)

        // Score based on weekly TSS
        // These are approximate guidelines - optimal varies by athlete
        let score: Int
        if weeklyTSS <= 200 {
            score = 90  // Light load
        } else if weeklyTSS <= 400 {
            score = 75  // Moderate load
        } else if weeklyTSS <= 600 {
            score = 55  // Heavy load
        } else {
            score = 30  // Very heavy load
        }

        return RecoveryFactor(
            name: "Training Load",
            value: String(format: "%.0f TSS/week", weeklyTSS),
            score: score,
            weight: 0.20,
            trend: nil
        )
    }

    // Store external TSS for use in training load calculation
    private var externalWeeklyTSS: Double?

    private func fetchExternalTrainingLoad() async {
        do {
            let externalTSS = try await healthKitManager.fetchWeeklyCyclingTSS(
                ftp: settingsService.ftp,
                restingHR: settingsService.restingHR,
                maxHR: settingsService.maxHR
            )
            externalWeeklyTSS = externalTSS
        } catch {
            print("Error fetching external training load: \(error)")
            externalWeeklyTSS = nil
        }
    }

    // MARK: - Helpers

    private func determineLevel(from score: Int) -> RecoveryStatus.RecoveryLevel {
        if score >= 80 {
            return .excellent
        } else if score >= 60 {
            return .good
        } else if score >= 40 {
            return .fair
        } else {
            return .poor
        }
    }

    private func determineSuggestedIntensity(
        from score: Int,
        factors: [RecoveryFactor]
    ) -> RecoveryStatus.SuggestedIntensity {
        // Check for any critical factors
        let hasCriticalFactor = factors.contains { $0.score < 30 }

        if hasCriticalFactor || score < 30 {
            return .rest
        } else if score < 50 {
            return .low
        } else if score < 70 {
            return .moderate
        } else {
            return .high
        }
    }
}

import Foundation
import Combine

/// Represents an AI-generated workout recommendation
struct WorkoutRecommendation: Identifiable {
    let id = UUID()
    let workout: Workout
    let reasoning: String
    let suggestedFTP: Int?
    let suggestedHRTargets: (low: Int, high: Int)?
    let durationScale: Double
}

/// Context gathered for AI recommendation
struct RecommendationContext {
    let recoveryStatus: RecoveryStatus?
    let recentRides: [Ride]
    let externalWorkouts: [ExternalWorkout]
    let weeklyTSS: Double
    let availableWorkouts: [Workout]
    let userFTP: Int
    let userMaxHR: Int
    let userRestingHR: Int
}

/// Service that provides AI-powered workout recommendations
class WorkoutRecommendationService: ObservableObject {
    private let claudeClient: ClaudeClient
    private let rideRepository: RideRepository
    private let recoveryAnalyzer: RecoveryAnalyzer
    private let workoutRepository: WorkoutRepository
    private let settingsService: SettingsService
    private let healthKitManager: HealthKitManager?
    private var hrZoneService: HRZoneService?

    @Published private(set) var isLoading = false

    init(
        claudeClient: ClaudeClient,
        rideRepository: RideRepository,
        recoveryAnalyzer: RecoveryAnalyzer,
        workoutRepository: WorkoutRepository,
        settingsService: SettingsService,
        healthKitManager: HealthKitManager? = nil,
        hrZoneService: HRZoneService? = nil
    ) {
        self.claudeClient = claudeClient
        self.rideRepository = rideRepository
        self.recoveryAnalyzer = recoveryAnalyzer
        self.workoutRepository = workoutRepository
        self.settingsService = settingsService
        self.healthKitManager = healthKitManager
        self.hrZoneService = hrZoneService
    }

    /// Get a workout recommendation based on user message and current context
    @MainActor
    func getRecommendation(userMessage: String) async throws -> WorkoutRecommendation {
        isLoading = true
        defer { isLoading = false }

        // 1. Gather context
        let context = await gatherContext()

        // 2. Build prompt with all context + user message
        let prompt = buildPrompt(userMessage: userMessage, context: context)

        // 3. Call Claude API for recommendation
        let response = try await claudeClient.recommendWorkout(prompt: prompt)

        // 4. Parse response and return structured recommendation
        return parseRecommendation(response: response, context: context)
    }

    // MARK: - Private Methods

    private func gatherContext() async -> RecommendationContext {
        // Fetch recovery status
        await recoveryAnalyzer.analyze()
        let recoveryStatus = recoveryAnalyzer.currentStatus

        // Fetch recent rides (last 7 days)
        let allRides = rideRepository.fetchRecent(limit: 20)
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recentRides = allRides.filter { $0.startedAt >= oneWeekAgo }

        // Fetch external workouts from HealthKit (Garmin, etc. — all activity types)
        var externalWorkouts: [ExternalWorkout] = []
        if settingsService.healthKitEnabled, let hkm = healthKitManager {
            externalWorkouts = (try? await hkm.fetchRecentAllWorkouts(days: 7)) ?? []
        }

        // Calculate weekly TSS (in-app + external from HealthKit)
        let inAppTSS = recentRides.compactMap { $0.tss }.reduce(0.0, +)
        let externalTSS = externalWorkouts.compactMap {
            $0.estimatedTSS(
                ftp: settingsService.ftp,
                restingHR: settingsService.restingHR,
                maxHR: settingsService.maxHR
            )
        }.reduce(0.0, +)
        let weeklyTSS = inAppTSS + externalTSS

        // Get available workouts (default + custom)
        var availableWorkouts = DefaultWorkouts.all
        let customWorkouts = workoutRepository.fetchAll()
        availableWorkouts.append(contentsOf: customWorkouts)

        return RecommendationContext(
            recoveryStatus: recoveryStatus,
            recentRides: recentRides,
            externalWorkouts: externalWorkouts,
            weeklyTSS: weeklyTSS,
            availableWorkouts: availableWorkouts,
            userFTP: settingsService.ftp,
            userMaxHR: settingsService.maxHR,
            userRestingHR: settingsService.restingHR
        )
    }

    private func buildPrompt(userMessage: String, context: RecommendationContext) -> String {
        var prompt = "USER MESSAGE: \(userMessage)\n\n"

        // Add recovery status
        if let recovery = context.recoveryStatus {
            prompt += "RECOVERY STATUS:\n"
            prompt += "- Score: \(recovery.score)/100 (\(recovery.level.rawValue))\n"
            prompt += "- Suggested intensity: \(recovery.suggestedIntensity.rawValue)\n"
            for factor in recovery.factors {
                var factorLine = "- \(factor.name): \(factor.value) (score: \(factor.score))"
                if let trend = factor.trend {
                    factorLine += " [trend: \(trend.rawValue)]"
                }
                prompt += factorLine + "\n"
            }
            prompt += "\n"
        } else {
            prompt += "RECOVERY STATUS: No data available\n\n"
        }

        // Add recent rides
        prompt += "RECENT RIDES (last 7 days):\n"
        if context.recentRides.isEmpty {
            prompt += "- No rides recorded\n"
        } else {
            for ride in context.recentRides.prefix(5) {
                let daysAgo = Calendar.current.dateComponents([.day], from: ride.startedAt, to: Date()).day ?? 0
                prompt += "- \(ride.workoutName): "
                if let tss = ride.tss {
                    prompt += "TSS \(String(format: "%.0f", tss)), "
                }
                if let ifactor = ride.intensityFactor {
                    prompt += "IF \(String(format: "%.2f", ifactor)), "
                }
                prompt += "\(ride.durationSec / 60) min"
                if daysAgo == 0 {
                    prompt += " (today)"
                } else if daysAgo == 1 {
                    prompt += " (yesterday)"
                } else {
                    prompt += " (\(daysAgo) days ago)"
                }
                prompt += "\n"
            }
        }

        // Add external workouts (Garmin, etc. — all activity types)
        if !context.externalWorkouts.isEmpty {
            prompt += "EXTERNAL WORKOUTS (synced from Apple Health):\n"
            for workout in context.externalWorkouts.prefix(10) {
                let daysAgo = Calendar.current.dateComponents([.day], from: workout.startDate, to: Date()).day ?? 0
                prompt += "- \(workout.activityType) (\(workout.sourceName)): \(workout.durationMinutes) min"
                if let dist = workout.distanceKm {
                    prompt += ", \(String(format: "%.1f", dist)) km"
                }
                if let avgHR = workout.averageHeartRate {
                    prompt += ", avg HR \(Int(avgHR))"
                }
                if let avgPow = workout.averagePower {
                    prompt += ", avg \(Int(avgPow))W"
                }
                if let tss = workout.estimatedTSS(ftp: context.userFTP, restingHR: context.userRestingHR, maxHR: context.userMaxHR) {
                    prompt += ", ~\(String(format: "%.0f", tss)) TSS"
                }
                if daysAgo == 0 {
                    prompt += " (today)"
                } else if daysAgo == 1 {
                    prompt += " (yesterday)"
                } else {
                    prompt += " (\(daysAgo) days ago)"
                }
                prompt += "\n"
            }
        }

        prompt += "Weekly TSS (all sources): \(String(format: "%.0f", context.weeklyTSS))\n\n"

        // Add user settings
        prompt += "USER SETTINGS:\n"
        prompt += "- FTP: \(context.userFTP)W\n"
        prompt += "- Max HR: \(context.userMaxHR) bpm\n"
        prompt += "- Resting HR: \(context.userRestingHR) bpm\n"

        if let hrZoneService = hrZoneService {
            let config = hrZoneService.currentConfig
            let zone2Range = hrZoneService.hrZoneBounds(zone: 2)
            prompt += "- Zone 2 HR range: \(zone2Range.lowerBound)-\(zone2Range.upperBound) bpm\n"

            if let lthr = config.lthr {
                prompt += "- LTHR: \(lthr) bpm (data-driven)\n"
            }
            prompt += "- HR zones: \(config.modelDescription)\n"
        } else {
            prompt += "- Zone 2 HR range: \(hrZone2Range(context)) bpm\n"
        }
        prompt += "\n"

        // Add available workouts
        prompt += "AVAILABLE WORKOUTS:\n"
        for (index, workout) in context.availableWorkouts.enumerated() {
            let mainIntensity = describeWorkoutIntensity(workout)
            prompt += "\(index + 1). \(workout.name) (\(workout.formattedDuration)) - \(workout.notes)"
            if !mainIntensity.isEmpty {
                prompt += " [Intensity: \(mainIntensity)]"
            }
            let hasHRTarget = workout.steps.contains { $0.type == .hrTarget }
            if hasHRTarget {
                prompt += " [HR-controlled]"
            }
            prompt += "\n"
        }

        return prompt
    }

    private func hrZone2Range(_ context: RecommendationContext) -> String {
        // Karvonen formula: THR = ((MaxHR - RestingHR) * %Intensity) + RestingHR
        // Zone 2 is typically 60-70% intensity
        let hrReserve = context.userMaxHR - context.userRestingHR
        let zone2Low = Int(Double(hrReserve) * 0.60) + context.userRestingHR
        let zone2High = Int(Double(hrReserve) * 0.70) + context.userRestingHR
        return "\(zone2Low)-\(zone2High)"
    }

    private func describeWorkoutIntensity(_ workout: Workout) -> String {
        var intensities: [Int] = []
        collectMainIntensities(from: workout.steps, into: &intensities)

        if intensities.isEmpty { return "" }

        let maxInt = intensities.max() ?? 0
        if maxInt >= 150 {
            return "VO2max"
        } else if maxInt >= 105 {
            return "Threshold+"
        } else if maxInt >= 88 {
            return "Sweet Spot"
        } else if maxInt >= 70 {
            return "Tempo"
        } else {
            return "Endurance"
        }
    }

    private func collectMainIntensities(from steps: [WorkoutStep], into array: inout [Int]) {
        for step in steps {
            switch step.type {
            case .steady:
                array.append(step.intensityPct)
            case .ramp:
                array.append(step.startPct)
                array.append(step.endPct)
            case .repeats:
                collectMainIntensities(from: step.children, into: &array)
            case .hrTarget:
                array.append(step.fallbackPct)
            }
        }
    }

    private func parseRecommendation(response: ClaudeRecommendationResponse, context: RecommendationContext) -> WorkoutRecommendation {
        // Find the recommended workout by name
        let recommendedWorkout = context.availableWorkouts.first {
            $0.name.lowercased() == response.workoutName.lowercased()
        } ?? context.availableWorkouts.first ?? DefaultWorkouts.zone2Endurance()

        // Parse HR targets if provided
        var hrTargets: (low: Int, high: Int)?
        if let low = response.hrTargetLow, let high = response.hrTargetHigh {
            hrTargets = (low: low, high: high)
        }

        return WorkoutRecommendation(
            workout: recommendedWorkout,
            reasoning: response.reasoning,
            suggestedFTP: response.suggestedFTP,
            suggestedHRTargets: hrTargets,
            durationScale: response.durationScale ?? 1.0
        )
    }
}


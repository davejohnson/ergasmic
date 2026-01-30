import Foundation
import Combine

/// Types of insights that can be generated
enum InsightType {
    case postWorkout
    case weeklyTrend
    case ftpRecommendation
    case recoveryAdvice
    case custom(query: String)
}

/// A generated insight from Claude
struct Insight: Identifiable {
    let id = UUID()
    let type: InsightType
    let content: String
    let generatedAt: Date
    let isLoading: Bool

    static func loading(type: InsightType) -> Insight {
        Insight(type: type, content: "", generatedAt: Date(), isLoading: true)
    }
}

/// Generates insights using Claude API
class InsightGenerator: ObservableObject {
    private let claudeClient: ClaudeClient
    private let rideRepository: RideRepository
    private let settingsService: SettingsService
    private let powerCurve: PowerDurationCurve
    private let ftpEstimator: FTPEstimator

    @Published private(set) var currentInsight: Insight?
    @Published private(set) var insightHistory: [Insight] = []
    @Published private(set) var error: String?

    private var cancellables = Set<AnyCancellable>()

    init(
        claudeClient: ClaudeClient,
        rideRepository: RideRepository,
        settingsService: SettingsService,
        powerCurve: PowerDurationCurve,
        ftpEstimator: FTPEstimator
    ) {
        self.claudeClient = claudeClient
        self.rideRepository = rideRepository
        self.settingsService = settingsService
        self.powerCurve = powerCurve
        self.ftpEstimator = ftpEstimator
    }

    // MARK: - Insight Generation

    @MainActor
    func generatePostWorkoutInsight(for ride: Ride, performanceCondition: Int? = nil) async {
        guard claudeClient.isConfigured else {
            error = "Claude API key not configured"
            return
        }

        currentInsight = .loading(type: .postWorkout)
        error = nil

        do {
            let response = try await claudeClient.analyzeWorkout(
                duration: ride.durationSec,
                avgPower: ride.avgPower,
                normalizedPower: ride.normalizedPower,
                intensityFactor: ride.intensityFactor,
                tss: ride.tss,
                ftp: ride.ftpUsed,
                performanceCondition: performanceCondition
            )

            let insight = Insight(
                type: .postWorkout,
                content: response,
                generatedAt: Date(),
                isLoading: false
            )

            currentInsight = insight
            insightHistory.insert(insight, at: 0)

        } catch {
            self.error = error.localizedDescription
            currentInsight = nil
        }
    }

    @MainActor
    func generateWeeklyInsight() async {
        guard claudeClient.isConfigured else {
            error = "Claude API key not configured"
            return
        }

        currentInsight = .loading(type: .weeklyTrend)
        error = nil

        // Gather weekly data
        let recentRides = rideRepository.fetchRecent(limit: 30)
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        let weeklyRides = recentRides.filter { $0.startedAt >= oneWeekAgo }

        let rideData: [(name: String, tss: Double, intensityFactor: Double, duration: Int)] = weeklyRides.compactMap { ride in
            guard let tss = ride.tss, let intF = ride.intensityFactor else { return nil }
            return (ride.workoutName, tss, intF, ride.durationSec)
        }

        let totalTSS = rideData.reduce(0.0) { $0 + $1.tss }

        do {
            let response = try await claudeClient.analyzeWeeklyTraining(
                rides: rideData,
                totalTSS: totalTSS,
                ftpTrend: nil  // Could add FTP history tracking
            )

            let insight = Insight(
                type: .weeklyTrend,
                content: response,
                generatedAt: Date(),
                isLoading: false
            )

            currentInsight = insight
            insightHistory.insert(insight, at: 0)

        } catch {
            self.error = error.localizedDescription
            currentInsight = nil
        }
    }

    @MainActor
    func generateFTPRecommendation() async {
        guard claudeClient.isConfigured else {
            error = "Claude API key not configured"
            return
        }

        currentInsight = .loading(type: .ftpRecommendation)
        error = nil

        let currentFTP = settingsService.ftp

        // Gather best efforts
        var bestEfforts: [(duration: Int, power: Int)] = []
        for duration in [60, 300, 1200] {  // 1min, 5min, 20min
            if let power = powerCurve.bestPower(forDuration: duration) {
                bestEfforts.append((duration, power))
            }
        }

        let estimatedFTP = ftpEstimator.getBestEstimate()?.estimatedFTP

        do {
            let response = try await claudeClient.suggestFTPUpdate(
                currentFTP: currentFTP,
                bestEfforts: bestEfforts,
                estimatedFTP: estimatedFTP
            )

            let insight = Insight(
                type: .ftpRecommendation,
                content: response,
                generatedAt: Date(),
                isLoading: false
            )

            currentInsight = insight
            insightHistory.insert(insight, at: 0)

        } catch {
            self.error = error.localizedDescription
            currentInsight = nil
        }
    }

    @MainActor
    func askQuestion(_ question: String) async {
        guard claudeClient.isConfigured else {
            error = "Claude API key not configured"
            return
        }

        currentInsight = .loading(type: .custom(query: question))
        error = nil

        // Build context about the athlete
        var context = "Athlete profile:\n"
        context += "- FTP: \(settingsService.ftp)W\n"
        context += "- Weight: \(settingsService.weight)kg\n"
        context += "- Max HR: \(settingsService.maxHR) bpm\n\n"

        // Add recent training context
        let recentRides = rideRepository.fetchRecent(limit: 5)
        if !recentRides.isEmpty {
            context += "Recent training:\n"
            for ride in recentRides {
                context += "- \(ride.workoutName): "
                if let tss = ride.tss {
                    context += "\(String(format: "%.0f", tss)) TSS, "
                }
                context += "\(ride.durationSec / 60) min\n"
            }
            context += "\n"
        }

        let prompt = context + "Question: " + question

        let systemPrompt = """
        You are a cycling coach helping an athlete with their training.
        Be helpful, specific, and data-driven when possible.
        Keep responses concise but informative.
        """

        do {
            let response = try await claudeClient.sendMessage(
                prompt: prompt,
                systemPrompt: systemPrompt
            )

            let insight = Insight(
                type: .custom(query: question),
                content: response,
                generatedAt: Date(),
                isLoading: false
            )

            currentInsight = insight
            insightHistory.insert(insight, at: 0)

        } catch {
            self.error = error.localizedDescription
            currentInsight = nil
        }
    }

    // MARK: - History Management

    func clearHistory() {
        insightHistory.removeAll()
    }

    func clearError() {
        error = nil
    }
}

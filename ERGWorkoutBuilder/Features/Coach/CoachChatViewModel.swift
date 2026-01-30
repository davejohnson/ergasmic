import Foundation
import Combine

/// Role in the chat conversation
enum ChatRole {
    case user
    case coach
}

/// A message in the coach chat
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
    var recommendation: WorkoutRecommendation?
    let timestamp: Date

    init(role: ChatRole, content: String, recommendation: WorkoutRecommendation? = nil) {
        self.role = role
        self.content = content
        self.recommendation = recommendation
        self.timestamp = Date()
    }
}

/// Configuration to apply when starting a workout from coach recommendation
struct WorkoutConfiguration {
    let workout: Workout
    let ftp: Int
    let hrTargetLow: Int?
    let hrTargetHigh: Int?
    let durationScale: Double
}

/// View model for the coach chat interface
@MainActor
class CoachChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isThinking = false
    @Published var workoutToStart: WorkoutConfiguration?
    @Published var error: String?

    private let recommendationService: WorkoutRecommendationService
    private let settingsService: SettingsService

    init(
        recommendationService: WorkoutRecommendationService,
        settingsService: SettingsService
    ) {
        self.recommendationService = recommendationService
        self.settingsService = settingsService
    }

    /// Send a message and get a recommendation
    func sendMessage(_ text: String) async {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        // Add user message
        messages.append(ChatMessage(role: .user, content: trimmedText))
        isThinking = true
        error = nil

        do {
            let recommendation = try await recommendationService.getRecommendation(userMessage: trimmedText)

            // Add coach response with recommendation
            messages.append(ChatMessage(
                role: .coach,
                content: recommendation.reasoning,
                recommendation: recommendation
            ))
        } catch {
            // Add error message from coach
            messages.append(ChatMessage(
                role: .coach,
                content: "I couldn't come up with a recommendation. Please check your Claude API key in Settings or try again."
            ))
            self.error = error.localizedDescription
        }

        isThinking = false
    }

    /// Accept a recommendation and prepare to start the workout
    func acceptRecommendation(_ recommendation: WorkoutRecommendation) {
        var adjustedWorkout = recommendation.workout

        // Apply duration scaling
        if recommendation.durationScale != 1.0 {
            adjustedWorkout.steps = adjustedWorkout.steps.map { step in
                scaleStepDuration(step, scale: recommendation.durationScale)
            }
        }

        // Apply HR targets if recommended and workout has HR target steps
        if let hrTargets = recommendation.suggestedHRTargets {
            adjustedWorkout.steps = adjustedWorkout.steps.map { step in
                applyHRTargets(step, low: hrTargets.low, high: hrTargets.high)
            }
        }

        // Determine FTP to use
        let ftpToUse = recommendation.suggestedFTP ?? settingsService.ftp

        workoutToStart = WorkoutConfiguration(
            workout: adjustedWorkout,
            ftp: ftpToUse,
            hrTargetLow: recommendation.suggestedHRTargets?.low,
            hrTargetHigh: recommendation.suggestedHRTargets?.high,
            durationScale: recommendation.durationScale
        )
    }

    /// Clear the chat and start fresh
    func clearChat() {
        messages.removeAll()
        error = nil
    }

    /// Quick action messages for common scenarios
    static let quickActions = [
        "Ready to ride",
        "Feeling tired today",
        "Want to push hard",
        "Need something easy"
    ]

    // MARK: - Private Helpers

    private func scaleStepDuration(_ step: WorkoutStep, scale: Double) -> WorkoutStep {
        var adjusted = step
        adjusted.durationSec = Int(Double(step.durationSec) * scale)

        if step.type == .repeats {
            adjusted.children = step.children.map { scaleStepDuration($0, scale: scale) }
        }

        return adjusted
    }

    private func applyHRTargets(_ step: WorkoutStep, low: Int, high: Int) -> WorkoutStep {
        var adjusted = step

        if step.type == .hrTarget {
            adjusted.targetHRLow = low
            adjusted.targetHRHigh = high
        } else if step.type == .repeats {
            adjusted.children = step.children.map { applyHRTargets($0, low: low, high: high) }
        }

        return adjusted
    }
}

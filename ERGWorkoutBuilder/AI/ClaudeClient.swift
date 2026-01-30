import Foundation

/// Response from Claude API
struct ClaudeResponse: Codable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model
        case stopReason = "stop_reason"
        case usage
    }

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }

    struct Usage: Codable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }
    }

    var textContent: String {
        content.compactMap { $0.text }.joined()
    }
}

/// Request to Claude API
struct ClaudeRequest: Codable {
    let model: String
    let maxTokens: Int
    let messages: [Message]
    let system: String?

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
    }

    struct Message: Codable {
        let role: String
        let content: String
    }
}

/// Structured response from Claude for workout recommendation
struct ClaudeRecommendationResponse {
    let workoutName: String
    let reasoning: String
    let suggestedFTP: Int?
    let hrTargetLow: Int?
    let hrTargetHigh: Int?
    let durationScale: Double?
}

/// Errors from Claude API
enum ClaudeError: LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case decodingError(Error)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your Claude API key in Settings."
        case .invalidURL:
            return "Invalid API URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiError(let statusCode, let message):
            return "API error (\(statusCode)): \(message)"
        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"
        case .emptyResponse:
            return "Empty response from API"
        }
    }
}

/// Client for interacting with Claude API
class ClaudeClient: ObservableObject {
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let defaultModel = "claude-opus-4-5-20251101"  // Use Opus 4.5 for highest quality recommendations
    private let apiVersion = "2023-06-01"

    @Published private(set) var isLoading = false

    private var apiKey: String?

    func configure(apiKey: String?) {
        self.apiKey = apiKey
    }

    var isConfigured: Bool {
        guard let key = apiKey, !key.isEmpty else { return false }
        return true
    }

    // MARK: - API Calls

    func sendMessage(
        prompt: String,
        systemPrompt: String? = nil,
        maxTokens: Int = 1024
    ) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw ClaudeError.noAPIKey
        }

        let request = ClaudeRequest(
            model: defaultModel,
            maxTokens: maxTokens,
            messages: [
                ClaudeRequest.Message(role: "user", content: prompt)
            ],
            system: systemPrompt
        )

        var urlRequest = URLRequest(url: baseURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        await MainActor.run { isLoading = true }
        defer { Task { @MainActor in isLoading = false } }

        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ClaudeError.networkError(NSError(domain: "ClaudeClient", code: -1))
            }

            if httpResponse.statusCode != 200 {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw ClaudeError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
            }

            let decoder = JSONDecoder()
            let claudeResponse = try decoder.decode(ClaudeResponse.self, from: data)

            guard !claudeResponse.textContent.isEmpty else {
                throw ClaudeError.emptyResponse
            }

            return claudeResponse.textContent

        } catch let error as ClaudeError {
            throw error
        } catch let error as DecodingError {
            throw ClaudeError.decodingError(error)
        } catch {
            throw ClaudeError.networkError(error)
        }
    }

    // MARK: - Convenience Methods

    func analyzeWorkout(
        duration: Int,
        avgPower: Int?,
        normalizedPower: Int?,
        intensityFactor: Double?,
        tss: Double?,
        ftp: Int,
        performanceCondition: Int?
    ) async throws -> String {
        var prompt = "Analyze this cycling workout:\n"
        prompt += "- Duration: \(duration / 60) minutes\n"
        if let avgP = avgPower { prompt += "- Average Power: \(avgP)W\n" }
        if let np = normalizedPower { prompt += "- Normalized Power: \(np)W\n" }
        if let intF = intensityFactor { prompt += "- Intensity Factor: \(String(format: "%.2f", intF))\n" }
        if let t = tss { prompt += "- TSS: \(String(format: "%.0f", t))\n" }
        prompt += "- FTP: \(ftp)W\n"

        if let pc = performanceCondition {
            prompt += "- Performance condition started at +\(pc), "
            prompt += "indicating the athlete was \(pc > 0 ? "fresh" : "fatigued")\n"
        }

        prompt += "\nProvide brief insights about this workout in 2-3 sentences."

        let systemPrompt = """
        You are a cycling coach analyzing workout data. Be concise and actionable.
        Focus on what the metrics indicate about the athlete's performance and fatigue.
        """

        return try await sendMessage(prompt: prompt, systemPrompt: systemPrompt)
    }

    func suggestFTPUpdate(
        currentFTP: Int,
        bestEfforts: [(duration: Int, power: Int)],
        estimatedFTP: Int?
    ) async throws -> String {
        var prompt = "Current FTP setting: \(currentFTP)W\n\n"
        prompt += "Recent best power efforts:\n"
        for effort in bestEfforts {
            let durationStr = PowerDurationCurve.formatDuration(effort.duration)
            prompt += "- \(durationStr): \(effort.power)W\n"
        }

        if let estimated = estimatedFTP {
            prompt += "\nCalculated FTP estimate: \(estimated)W\n"
        }

        prompt += "\nShould the athlete update their FTP? If so, what value would you recommend?"

        let systemPrompt = """
        You are a cycling coach. Provide a brief, clear recommendation about FTP.
        Consider that FTP is typically 95% of 20-minute power. Be specific with numbers.
        Keep response to 2-3 sentences.
        """

        return try await sendMessage(prompt: prompt, systemPrompt: systemPrompt)
    }

    func analyzeWeeklyTraining(
        rides: [(name: String, tss: Double, intensityFactor: Double, duration: Int)],
        totalTSS: Double,
        ftpTrend: String?
    ) async throws -> String {
        var prompt = "This week's training summary:\n"

        for ride in rides {
            prompt += "- \(ride.name): \(String(format: "%.0f", ride.tss)) TSS, "
            prompt += "IF \(String(format: "%.2f", ride.intensityFactor)), "
            prompt += "\(ride.duration / 60) min\n"
        }

        prompt += "\nTotal weekly TSS: \(String(format: "%.0f", totalTSS))\n"

        if let trend = ftpTrend {
            prompt += "FTP trend: \(trend)\n"
        }

        prompt += "\nProvide brief insights on training load, recovery needs, and progress."

        let systemPrompt = """
        You are a cycling coach analyzing weekly training data. Be concise.
        Consider both training stress and recovery. Suggest adjustments if needed.
        Keep response to 3-4 sentences.
        """

        return try await sendMessage(prompt: prompt, systemPrompt: systemPrompt)
    }

    /// Recommend a workout based on user context and message
    func recommendWorkout(prompt: String) async throws -> ClaudeRecommendationResponse {
        let systemPrompt = """
        You are an expert cycling coach recommending workouts. Analyze the user's recovery status, \
        recent training, and their message to recommend the best workout from the available options.

        RECOMMENDATION RULES:
        1. If recovery score < 50 OR user mentions fatigue/tired/sore → recommend Zone 2 or Zone 2 HR
        2. If sleep < 6 hours → strongly suggest easy workout (Zone 2)
        3. If weekly TSS > 400 → suggest recovery or Zone 2 HR
        4. If user says "push hard", "ready to go", "feeling strong" → Sweet Spot or Over Unders
        5. If user mentions heart rate training → Zone 2 HR workout
        6. For Zone 2 HR workouts → suggest HR targets based on user's Zone 2 range

        Always provide empathetic reasoning that acknowledges how the user feels.

        Respond ONLY with valid JSON in this exact format (no markdown, no code blocks):
        {
            "workoutName": "exact name from available workouts",
            "reasoning": "2-3 sentence explanation of why this workout fits their situation",
            "suggestedFTP": null or integer if FTP should be adjusted,
            "hrTargetLow": null or integer for HR target low bound,
            "hrTargetHigh": null or integer for HR target high bound,
            "durationScale": 1.0 to 1.5 (scale factor for duration)
        }
        """

        let responseText = try await sendMessage(
            prompt: prompt,
            systemPrompt: systemPrompt,
            maxTokens: 512
        )

        return try parseRecommendationResponse(responseText)
    }

    private func parseRecommendationResponse(_ text: String) throws -> ClaudeRecommendationResponse {
        // Clean up response - remove any markdown code blocks if present
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedText.hasPrefix("```json") {
            cleanedText = String(cleanedText.dropFirst(7))
        } else if cleanedText.hasPrefix("```") {
            cleanedText = String(cleanedText.dropFirst(3))
        }
        if cleanedText.hasSuffix("```") {
            cleanedText = String(cleanedText.dropLast(3))
        }
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleanedText.data(using: .utf8) else {
            throw ClaudeError.decodingError(NSError(domain: "ClaudeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UTF-8"]))
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let json = json,
                  let workoutName = json["workoutName"] as? String,
                  let reasoning = json["reasoning"] as? String else {
                throw ClaudeError.decodingError(NSError(domain: "ClaudeClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing required fields"]))
            }

            let suggestedFTP = json["suggestedFTP"] as? Int
            let hrTargetLow = json["hrTargetLow"] as? Int
            let hrTargetHigh = json["hrTargetHigh"] as? Int
            let durationScale = json["durationScale"] as? Double

            return ClaudeRecommendationResponse(
                workoutName: workoutName,
                reasoning: reasoning,
                suggestedFTP: suggestedFTP,
                hrTargetLow: hrTargetLow,
                hrTargetHigh: hrTargetHigh,
                durationScale: durationScale
            )
        } catch let error as ClaudeError {
            throw error
        } catch {
            throw ClaudeError.decodingError(error)
        }
    }
}

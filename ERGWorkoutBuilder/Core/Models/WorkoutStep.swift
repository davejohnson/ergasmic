import Foundation

enum StepType: String, CaseIterable, Codable {
    case steady
    case ramp
    case repeats
    case hrTarget  // HR-driven step where power adjusts to maintain target HR
}

struct WorkoutStep: Identifiable, Equatable {
    let id: UUID
    var type: StepType
    var durationSec: Int
    var intensityPct: Int      // For steady steps
    var startPct: Int          // For ramp steps
    var endPct: Int            // For ramp steps
    var repeatCount: Int       // For repeat blocks
    var children: [WorkoutStep] // For repeat blocks
    var targetHRLow: Int       // For HR target steps - lower bound of HR zone
    var targetHRHigh: Int      // For HR target steps - upper bound of HR zone
    var fallbackPct: Int       // For HR target steps - initial power % before HR stabilizes

    init(
        id: UUID = UUID(),
        type: StepType = .steady,
        durationSec: Int = 60,
        intensityPct: Int = 100,
        startPct: Int = 50,
        endPct: Int = 100,
        repeatCount: Int = 3,
        children: [WorkoutStep] = [],
        targetHRLow: Int = 120,
        targetHRHigh: Int = 140,
        fallbackPct: Int = 65
    ) {
        self.id = id
        self.type = type
        self.durationSec = durationSec
        self.intensityPct = intensityPct
        self.startPct = startPct
        self.endPct = endPct
        self.repeatCount = repeatCount
        self.children = children
        self.targetHRLow = targetHRLow
        self.targetHRHigh = targetHRHigh
        self.fallbackPct = fallbackPct
    }

    var totalDurationSec: Int {
        switch type {
        case .steady, .ramp, .hrTarget:
            return durationSec
        case .repeats:
            let childDuration = children.reduce(0) { $0 + $1.totalDurationSec }
            return childDuration * repeatCount
        }
    }

    var displayDescription: String {
        switch type {
        case .steady:
            return "\(intensityPct)% for \(formatDuration(durationSec))"
        case .ramp:
            return "\(startPct)% → \(endPct)% over \(formatDuration(durationSec))"
        case .repeats:
            return "\(repeatCount)x repeats (\(formatDuration(totalDurationSec)))"
        case .hrTarget:
            return "HR \(targetHRLow)-\(targetHRHigh) bpm for \(formatDuration(durationSec))"
        }
    }

    static func steady(durationSec: Int, intensityPct: Int) -> WorkoutStep {
        WorkoutStep(type: .steady, durationSec: durationSec, intensityPct: intensityPct)
    }

    static func ramp(durationSec: Int, startPct: Int, endPct: Int) -> WorkoutStep {
        WorkoutStep(type: .ramp, durationSec: durationSec, startPct: startPct, endPct: endPct)
    }

    static func repeats(count: Int, children: [WorkoutStep]) -> WorkoutStep {
        WorkoutStep(type: .repeats, repeatCount: count, children: children)
    }

    static func hrTarget(durationSec: Int, lowBpm: Int, highBpm: Int, fallbackPct: Int = 65) -> WorkoutStep {
        WorkoutStep(
            type: .hrTarget,
            durationSec: durationSec,
            targetHRLow: lowBpm,
            targetHRHigh: highBpm,
            fallbackPct: fallbackPct
        )
    }
}

// MARK: - Validation

extension WorkoutStep {
    enum ValidationError: LocalizedError {
        case durationTooShort
        case intensityOutOfRange
        case repeatCountOutOfRange
        case repeatBlockEmpty
        case totalDurationExceeded
        case hrTargetOutOfRange

        var errorDescription: String? {
            switch self {
            case .durationTooShort:
                return "Duration must be at least 5 seconds"
            case .intensityOutOfRange:
                return "Intensity must be between 30% and 200%"
            case .repeatCountOutOfRange:
                return "Repeat count must be between 2 and 50"
            case .repeatBlockEmpty:
                return "Repeat block must have at least 1 step"
            case .totalDurationExceeded:
                return "Total workout duration cannot exceed 3 hours"
            case .hrTargetOutOfRange:
                return "HR target must be between 50 and 220 bpm"
            }
        }
    }

    func validate() -> ValidationError? {
        switch type {
        case .steady:
            if durationSec < 5 { return .durationTooShort }
            if intensityPct < 30 || intensityPct > 200 { return .intensityOutOfRange }
        case .ramp:
            if durationSec < 5 { return .durationTooShort }
            if startPct < 30 || startPct > 200 { return .intensityOutOfRange }
            if endPct < 30 || endPct > 200 { return .intensityOutOfRange }
        case .repeats:
            if repeatCount < 2 || repeatCount > 50 { return .repeatCountOutOfRange }
            if children.isEmpty { return .repeatBlockEmpty }
            for child in children {
                if let error = child.validate() {
                    return error
                }
            }
        case .hrTarget:
            if durationSec < 5 { return .durationTooShort }
            if targetHRLow < 50 || targetHRLow > 220 { return .hrTargetOutOfRange }
            if targetHRHigh < 50 || targetHRHigh > 220 { return .hrTargetOutOfRange }
            if targetHRLow > targetHRHigh { return .hrTargetOutOfRange }
            if fallbackPct < 30 || fallbackPct > 200 { return .intensityOutOfRange }
        }
        return nil
    }
}

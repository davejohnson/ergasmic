import Foundation

struct ExpandedStep: Identifiable, Equatable {
    let id: UUID
    let originalStepId: UUID
    let type: StepType
    let durationSec: Int
    let intensityPct: Int      // For steady
    let startPct: Int          // For ramp
    let endPct: Int            // For ramp
    let iterationIndex: Int?   // Which repeat iteration (0-based), nil if not in repeat
    let totalIterations: Int?  // Total iterations, nil if not in repeat
    let stepIndex: Int         // Index in expanded sequence
    let targetHRLow: Int       // For hrTarget steps
    let targetHRHigh: Int      // For hrTarget steps
    let fallbackPct: Int       // For hrTarget steps - initial power before HR stabilizes

    init(
        id: UUID = UUID(),
        originalStepId: UUID,
        type: StepType,
        durationSec: Int,
        intensityPct: Int = 100,
        startPct: Int = 50,
        endPct: Int = 100,
        iterationIndex: Int? = nil,
        totalIterations: Int? = nil,
        stepIndex: Int,
        targetHRLow: Int = 120,
        targetHRHigh: Int = 140,
        fallbackPct: Int = 65
    ) {
        self.id = id
        self.originalStepId = originalStepId
        self.type = type
        self.durationSec = durationSec
        self.intensityPct = intensityPct
        self.startPct = startPct
        self.endPct = endPct
        self.iterationIndex = iterationIndex
        self.totalIterations = totalIterations
        self.stepIndex = stepIndex
        self.targetHRLow = targetHRLow
        self.targetHRHigh = targetHRHigh
        self.fallbackPct = fallbackPct
    }

    var displayLabel: String {
        if let iteration = iterationIndex, let total = totalIterations {
            return "Rep \(iteration + 1)/\(total)"
        }
        return ""
    }

    var isHRTargeted: Bool {
        type == .hrTarget
    }

    func intensityAtElapsed(_ elapsedSec: Double) -> Int {
        switch type {
        case .steady:
            return intensityPct
        case .ramp:
            let progress = min(1.0, max(0.0, elapsedSec / Double(durationSec)))
            return startPct + Int(progress * Double(endPct - startPct))
        case .repeats:
            return intensityPct
        case .hrTarget:
            return fallbackPct  // Returns fallback; actual power is controlled by HRController
        }
    }
}

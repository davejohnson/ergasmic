import Foundation

class StepExpander {
    static func expand(_ steps: [WorkoutStep]) -> [ExpandedStep] {
        var result: [ExpandedStep] = []
        var index = 0

        for step in steps {
            let expanded = expandStep(step, stepIndex: &index)
            result.append(contentsOf: expanded)
        }

        return result
    }

    private static func expandStep(
        _ step: WorkoutStep,
        stepIndex: inout Int,
        iterationIndex: Int? = nil,
        totalIterations: Int? = nil
    ) -> [ExpandedStep] {
        switch step.type {
        case .steady:
            let expanded = ExpandedStep(
                id: UUID(),
                originalStepId: step.id,
                type: .steady,
                durationSec: step.durationSec,
                intensityPct: step.intensityPct,
                startPct: step.intensityPct,
                endPct: step.intensityPct,
                iterationIndex: iterationIndex,
                totalIterations: totalIterations,
                stepIndex: stepIndex
            )
            stepIndex += 1
            return [expanded]

        case .ramp:
            let expanded = ExpandedStep(
                id: UUID(),
                originalStepId: step.id,
                type: .ramp,
                durationSec: step.durationSec,
                intensityPct: step.startPct,
                startPct: step.startPct,
                endPct: step.endPct,
                iterationIndex: iterationIndex,
                totalIterations: totalIterations,
                stepIndex: stepIndex
            )
            stepIndex += 1
            return [expanded]

        case .repeats:
            var result: [ExpandedStep] = []

            for iteration in 0..<step.repeatCount {
                for child in step.children {
                    let childExpanded = expandStep(
                        child,
                        stepIndex: &stepIndex,
                        iterationIndex: iteration,
                        totalIterations: step.repeatCount
                    )
                    result.append(contentsOf: childExpanded)
                }
            }

            return result

        case .hrTarget:
            let expanded = ExpandedStep(
                id: UUID(),
                originalStepId: step.id,
                type: .hrTarget,
                durationSec: step.durationSec,
                intensityPct: step.fallbackPct,
                startPct: step.fallbackPct,
                endPct: step.fallbackPct,
                iterationIndex: iterationIndex,
                totalIterations: totalIterations,
                stepIndex: stepIndex,
                targetHRLow: step.targetHRLow,
                targetHRHigh: step.targetHRHigh,
                fallbackPct: step.fallbackPct
            )
            stepIndex += 1
            return [expanded]
        }
    }

    // MARK: - Utility Methods

    static func totalDuration(_ steps: [WorkoutStep]) -> Int {
        steps.reduce(0) { $0 + $1.totalDurationSec }
    }

    static func stepAt(elapsedTime: Double, in expandedSteps: [ExpandedStep]) -> (step: ExpandedStep, elapsedInStep: Double)? {
        var accumulated: Double = 0

        for step in expandedSteps {
            let stepEnd = accumulated + Double(step.durationSec)
            if elapsedTime < stepEnd {
                return (step, elapsedTime - accumulated)
            }
            accumulated = stepEnd
        }

        return nil
    }
}

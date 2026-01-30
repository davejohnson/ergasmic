import Foundation

class TargetCalculator {
    private let ftp: Int

    init(ftp: Int) {
        self.ftp = ftp
    }

    func calculateTargetWatts(for step: ExpandedStep, elapsedInStep: Double) -> Int {
        switch step.type {
        case .steady:
            return wattsFromPercent(step.intensityPct)

        case .ramp:
            let progress = min(1.0, max(0.0, elapsedInStep / Double(step.durationSec)))
            let currentPct = Double(step.startPct) + progress * Double(step.endPct - step.startPct)
            return wattsFromPercent(Int(currentPct))

        case .repeats:
            return wattsFromPercent(step.intensityPct)

        case .hrTarget:
            // For HR-targeted steps, return fallback power
            // The actual power is controlled by HRController in WorkoutEngine
            return wattsFromPercent(step.fallbackPct)
        }
    }

    /// Calculate target watts for HR-targeted step with HRController override
    func calculateTargetWatts(for step: ExpandedStep, hrControllerPowerPct: Int) -> Int {
        guard step.type == .hrTarget else {
            return wattsFromPercent(step.intensityPct)
        }
        return wattsFromPercent(hrControllerPowerPct)
    }

    func wattsFromPercent(_ percent: Int) -> Int {
        Int(Double(ftp) * Double(percent) / 100.0)
    }

    func percentFromWatts(_ watts: Int) -> Int {
        guard ftp > 0 else { return 0 }
        return Int(Double(watts) / Double(ftp) * 100.0)
    }

    func zoneForPercent(_ percent: Int) -> PowerZone {
        switch percent {
        case ..<56:
            return .recovery
        case 56..<76:
            return .endurance
        case 76..<91:
            return .tempo
        case 91..<106:
            return .threshold
        case 106..<121:
            return .vo2max
        default:
            return .anaerobic
        }
    }
}

enum PowerZone: String, CaseIterable {
    case recovery = "Recovery"
    case endurance = "Endurance"
    case tempo = "Tempo"
    case threshold = "Threshold"
    case vo2max = "VO2max"
    case anaerobic = "Anaerobic"

    var color: String {
        switch self {
        case .recovery: return "gray"
        case .endurance: return "blue"
        case .tempo: return "green"
        case .threshold: return "yellow"
        case .vo2max: return "orange"
        case .anaerobic: return "red"
        }
    }

    var percentRange: ClosedRange<Int> {
        switch self {
        case .recovery: return 0...55
        case .endurance: return 56...75
        case .tempo: return 76...90
        case .threshold: return 91...105
        case .vo2max: return 106...120
        case .anaerobic: return 121...200
        }
    }
}

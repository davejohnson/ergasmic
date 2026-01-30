import Foundation

/// FTP estimation using multiple methods
struct FTPEstimate {
    let estimatedFTP: Int
    let method: EstimationMethod
    let confidence: Confidence
    let basedOnDuration: Int?  // Duration in seconds the estimate is based on

    enum EstimationMethod: String {
        case twentyMinuteTest = "95% of 20-min best"
        case criticalPowerModel = "Critical Power model"
        case rampTest = "Ramp test estimate"
    }

    enum Confidence: String {
        case high = "High"
        case medium = "Medium"
        case low = "Low"
    }
}

class FTPEstimator {
    private let powerCurve: PowerDurationCurve

    init(powerCurve: PowerDurationCurve) {
        self.powerCurve = powerCurve
    }

    // MARK: - Main Estimation Methods

    /// Estimates FTP using the classic 95% of 20-minute best power
    func estimateFromTwentyMinute() -> FTPEstimate? {
        guard let twentyMinPower = powerCurve.bestPower(forDuration: 1200) else {
            return nil
        }

        let estimatedFTP = Int(Double(twentyMinPower) * 0.95)
        return FTPEstimate(
            estimatedFTP: estimatedFTP,
            method: .twentyMinuteTest,
            confidence: .high,
            basedOnDuration: 1200
        )
    }

    /// Estimates FTP using the Critical Power model: P(t) = CP + W'/t
    /// Uses best efforts at multiple durations to fit the model
    func estimateFromCriticalPowerModel() -> FTPEstimate? {
        // Need at least 2 data points for curve fitting
        let durations = [60, 300, 1200]  // 1min, 5min, 20min
        var dataPoints: [(duration: Double, power: Double)] = []

        for duration in durations {
            if let power = powerCurve.bestPower(forDuration: duration) {
                dataPoints.append((Double(duration), Double(power)))
            }
        }

        guard dataPoints.count >= 2 else { return nil }

        // Simple linear regression on P = CP + W'/t
        // Rearranged: P = CP + W' * (1/t)
        // y = a + b*x where y=P, x=1/t, a=CP, b=W'
        let xs = dataPoints.map { 1.0 / $0.duration }
        let ys = dataPoints.map { $0.power }

        let n = Double(dataPoints.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)

        let denominator = n * sumX2 - sumX * sumX
        guard denominator != 0 else { return nil }

        let wPrime = (n * sumXY - sumX * sumY) / denominator  // W' in joules
        let cp = (sumY - wPrime * sumX / n) / n  // CP in watts

        // CP is approximately 96% of FTP
        let estimatedFTP = Int(cp / 0.96)

        // Determine confidence based on number of data points and spread
        let confidence: FTPEstimate.Confidence
        if dataPoints.count >= 3 && wPrime > 0 && cp > 0 {
            confidence = .high
        } else if dataPoints.count >= 2 && cp > 0 {
            confidence = .medium
        } else {
            confidence = .low
        }

        return FTPEstimate(
            estimatedFTP: max(0, estimatedFTP),
            method: .criticalPowerModel,
            confidence: confidence,
            basedOnDuration: nil
        )
    }

    /// Returns the best available FTP estimate
    func getBestEstimate() -> FTPEstimate? {
        // Prefer 20-minute test result if available
        if let twentyMinEstimate = estimateFromTwentyMinute() {
            return twentyMinEstimate
        }

        // Fall back to Critical Power model
        return estimateFromCriticalPowerModel()
    }

    /// Returns all available estimates for comparison
    func getAllEstimates() -> [FTPEstimate] {
        var estimates: [FTPEstimate] = []

        if let twentyMin = estimateFromTwentyMinute() {
            estimates.append(twentyMin)
        }

        if let cpModel = estimateFromCriticalPowerModel() {
            estimates.append(cpModel)
        }

        return estimates
    }

    // MARK: - Real-Time FTP Check

    /// Checks if current rolling 20-min power suggests a higher FTP
    /// Returns suggested new FTP if significantly higher than current
    func checkRealTimeFTP(rolling20MinPower: Int, currentFTP: Int) -> Int? {
        let suggestedFTP = Int(Double(rolling20MinPower) * 0.95)

        // Only suggest update if at least 3% higher
        if suggestedFTP > Int(Double(currentFTP) * 1.03) {
            return suggestedFTP
        }

        return nil
    }
}

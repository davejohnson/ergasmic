import Foundation

/// Controller that adjusts power output to maintain a target heart rate zone.
/// Uses a proportional-integral (PI) controller with rate limiting to smoothly
/// adjust power based on HR feedback.
class HRController {
    // Target HR zone
    private(set) var targetHRLow: Int
    private(set) var targetHRHigh: Int

    // Power bounds (as % of FTP)
    private let minPowerPct: Int = 30
    private let maxPowerPct: Int = 100

    // Current adjusted power
    private(set) var currentPowerPct: Int

    // PI controller state
    private var integralError: Double = 0
    private var lastUpdateTime: Date?

    // Controller gains
    private let kP: Double = 0.5   // Proportional gain (power % change per bpm error)
    private let kI: Double = 0.05  // Integral gain (accumulates over time)

    // Rate limiting - max power change per second
    private let maxRateOfChange: Double = 2.0  // % per second

    // HR smoothing
    private var hrHistory: [Int] = []
    private let hrHistorySize = 5  // Average over last 5 readings

    // Settling time before adjustments begin (let HR respond to initial power)
    private var settlingTimeRemaining: TimeInterval = 30.0

    init(targetHRLow: Int, targetHRHigh: Int, initialPowerPct: Int) {
        self.targetHRLow = targetHRLow
        self.targetHRHigh = targetHRHigh
        self.currentPowerPct = initialPowerPct
    }

    /// Update the controller with current HR and elapsed time.
    /// Returns the adjusted power percentage.
    func update(currentHR: Int?, deltaTime: TimeInterval) -> Int {
        // During settling period, don't adjust
        if settlingTimeRemaining > 0 {
            settlingTimeRemaining -= deltaTime
            return currentPowerPct
        }

        guard let hr = currentHR, hr > 0 else {
            // No HR data - maintain current power
            return currentPowerPct
        }

        // Add to HR history for smoothing
        hrHistory.append(hr)
        if hrHistory.count > hrHistorySize {
            hrHistory.removeFirst()
        }

        // Use smoothed HR
        let smoothedHR = Double(hrHistory.reduce(0, +)) / Double(hrHistory.count)

        // Calculate error (positive = HR too high, need less power)
        let targetMidpoint = Double(targetHRLow + targetHRHigh) / 2.0
        let error = smoothedHR - targetMidpoint

        // Dead zone - if within target range, minimal adjustment
        let deadZone = Double(targetHRHigh - targetHRLow) / 2.0
        let effectiveError: Double
        if abs(error) <= deadZone {
            effectiveError = 0
        } else if error > 0 {
            effectiveError = error - deadZone
        } else {
            effectiveError = error + deadZone
        }

        // PI control
        integralError += effectiveError * deltaTime
        // Anti-windup: clamp integral
        integralError = max(-100, min(100, integralError))

        let adjustment = -(kP * effectiveError + kI * integralError)

        // Rate limit the adjustment
        let maxChange = maxRateOfChange * deltaTime
        let clampedAdjustment = max(-maxChange, min(maxChange, adjustment))

        // Apply adjustment
        let newPowerPct = Double(currentPowerPct) + clampedAdjustment
        currentPowerPct = Int(max(Double(minPowerPct), min(Double(maxPowerPct), newPowerPct)))

        return currentPowerPct
    }

    /// Reset the controller state (e.g., when starting a new HR target step)
    func reset(targetHRLow: Int, targetHRHigh: Int, initialPowerPct: Int) {
        self.targetHRLow = targetHRLow
        self.targetHRHigh = targetHRHigh
        self.currentPowerPct = initialPowerPct
        self.integralError = 0
        self.hrHistory.removeAll()
        self.settlingTimeRemaining = 30.0
    }

    /// Get diagnostic info for display
    var diagnosticInfo: String {
        let smoothedHR = hrHistory.isEmpty ? 0 : hrHistory.reduce(0, +) / hrHistory.count
        return "HR: \(smoothedHR) | Target: \(targetHRLow)-\(targetHRHigh) | Power: \(currentPowerPct)%"
    }

    /// Whether the controller is still in settling period
    var isSettling: Bool {
        settlingTimeRemaining > 0
    }

    /// Whether current HR is within target zone
    func isInTargetZone(currentHR: Int?) -> Bool {
        guard let hr = currentHR else { return false }
        return hr >= targetHRLow && hr <= targetHRHigh
    }
}

import Foundation
import Combine

/// Which model is used for HR zone computation
enum HRZoneModel: String {
    case karvonen    // fallback - formula-based
    case lthrBased   // data-driven from HR:Power breakpoint
}

/// Configuration for HR zones, computed from performance data or formula
struct HRZoneConfig {
    let zones: [ClosedRange<Int>]  // 5 zones (index 0 = zone 1)
    let model: HRZoneModel
    let lthr: Int?                 // detected LTHR in bpm
    let observedMaxHR: Int?
    let computedRestingHR: Int?
    let confidence: Double         // 0-1, based on data quantity

    var modelDescription: String {
        switch model {
        case .lthrBased: return "Personalized (LTHR-based)"
        case .karvonen: return "Estimated (Karvonen)"
        }
    }
}

/// Service that computes personalized HR zones from actual performance data.
///
/// Uses the HR:Power baseline from PerformanceAnalyzer to detect LTHR (Lactate Threshold Heart Rate)
/// via piecewise linear regression, then derives 5-zone Friel model from LTHR.
/// Falls back to Karvonen formula when insufficient data.
class HRZoneService: ObservableObject {
    @Published private(set) var currentConfig: HRZoneConfig

    private let settingsService: SettingsService
    private let performanceAnalyzer: PerformanceAnalyzer
    private let healthKitManager: HealthKitManager

    private var cancellables = Set<AnyCancellable>()

    init(
        settingsService: SettingsService,
        performanceAnalyzer: PerformanceAnalyzer,
        healthKitManager: HealthKitManager
    ) {
        self.settingsService = settingsService
        self.performanceAnalyzer = performanceAnalyzer
        self.healthKitManager = healthKitManager

        // Initialize with Karvonen fallback
        self.currentConfig = Self.karvonenConfig(from: settingsService)
    }

    // MARK: - Public API

    /// Refresh zones from latest data. Call on app launch and after each ride.
    @MainActor
    func refresh() async {
        // 1. Update resting HR from HealthKit (14-day average)
        let computedRestingHR = await fetchAverageRestingHR(days: 14)
        if let rhr = computedRestingHR {
            settingsService.computedRestingHR = rhr
        }

        // 2. Get HR:Power baseline data points
        let dataPoints = performanceAnalyzer.getBaselineDataPoints()

        // 3. Determine max HR to use
        let maxHR = settingsService.observedMaxHR ?? settingsService.maxHR

        // 4. Try to detect LTHR
        if let lthr = detectLTHR(from: dataPoints, maxHR: maxHR) {
            settingsService.detectedLTHR = lthr

            let zones = computeZonesFromLTHR(lthr, maxHR: maxHR)
            let confidence = min(1.0, Double(dataPoints.count) / 10.0)

            currentConfig = HRZoneConfig(
                zones: zones,
                model: .lthrBased,
                lthr: lthr,
                observedMaxHR: settingsService.observedMaxHR,
                computedRestingHR: computedRestingHR,
                confidence: confidence
            )
        } else {
            // Fall back to Karvonen
            currentConfig = Self.karvonenConfig(
                from: settingsService,
                observedMaxHR: settingsService.observedMaxHR,
                computedRestingHR: computedRestingHR
            )
        }
    }

    /// Drop-in replacement for SettingsService.hrZoneBounds
    func hrZoneBounds(zone: Int) -> ClosedRange<Int> {
        guard zone >= 1, zone <= 5, zone <= currentConfig.zones.count else {
            return 0...0
        }
        return currentConfig.zones[zone - 1]
    }

    /// Drop-in replacement for SettingsService.hrZoneForHeartRate
    func hrZoneForHeartRate(_ hr: Int) -> Int {
        for (index, range) in currentConfig.zones.enumerated() {
            if range.contains(hr) {
                return index + 1
            }
        }
        // Below zone 1 or above zone 5
        if hr < (currentConfig.zones.first?.lowerBound ?? 0) {
            return 1
        }
        return 5
    }

    /// Track observed max HR from ride telemetry samples
    func trackObservedMaxHR(from samples: [TelemetrySample]) {
        let maxHRInRide = samples.compactMap { $0.heartRate }.max() ?? 0
        guard maxHRInRide > 0 else { return }

        let currentObserved = settingsService.observedMaxHR ?? 0
        if maxHRInRide > currentObserved {
            settingsService.observedMaxHR = maxHRInRide
        }
    }

    // MARK: - LTHR Detection

    /// Detect Lactate Threshold Heart Rate from HR:Power baseline data.
    ///
    /// Uses piecewise linear regression to find the breakpoint where the HR:Power
    /// relationship changes slope (power gains per HR increment decrease).
    func detectLTHR(from dataPoints: [HRPowerDataPoint], maxHR: Int) -> Int? {
        guard dataPoints.count >= 6 else { return nil }

        let sorted = dataPoints.sorted { $0.hrPercent < $1.hrPercent }

        // Require sufficient HR range
        guard let first = sorted.first, let last = sorted.last,
              last.hrPercent - first.hrPercent >= 25 else {
            return nil
        }

        let n = sorted.count
        var bestSplitIndex = -1
        var bestResidualSum = Double.infinity

        // Try each candidate split point
        for k in 2..<(n - 2) {
            let leftPoints = Array(sorted[0...k])
            let rightPoints = Array(sorted[k..<n])

            guard let leftFit = linearFit(leftPoints),
                  let rightFit = linearFit(rightPoints) else {
                continue
            }

            // Key constraint: second segment slope must be less than first
            // This means power gains flatten out (indicating threshold)
            guard rightFit.slope < leftFit.slope else { continue }

            // Calculate total sum of squared residuals
            let leftResiduals = sumOfSquaredResiduals(leftPoints, slope: leftFit.slope, intercept: leftFit.intercept)
            let rightResiduals = sumOfSquaredResiduals(rightPoints, slope: rightFit.slope, intercept: rightFit.intercept)
            let totalResiduals = leftResiduals + rightResiduals

            if totalResiduals < bestResidualSum {
                bestResidualSum = totalResiduals
                bestSplitIndex = k
            }
        }

        guard bestSplitIndex >= 0 else { return nil }

        // Convert HR percent at breakpoint to absolute HR
        let lthrPercent = sorted[bestSplitIndex].hrPercent
        let lthrBPM = Int(Double(maxHR) * Double(lthrPercent) / 100.0)

        return lthrBPM
    }

    // MARK: - Zone Computation

    /// Compute 5-zone Friel model from LTHR
    func computeZonesFromLTHR(_ lthr: Int, maxHR: Int) -> [ClosedRange<Int>] {
        let zone1Upper = Int(Double(lthr) * 0.85) - 1
        let zone2Upper = Int(Double(lthr) * 0.89)
        let zone3Upper = Int(Double(lthr) * 0.94)
        let zone4Upper = lthr - 1
        let zone5Upper = maxHR

        return [
            0...zone1Upper,                     // Zone 1: Recovery (< 85% LTHR)
            (zone1Upper + 1)...zone2Upper,      // Zone 2: Aerobic (85-89% LTHR)
            (zone2Upper + 1)...zone3Upper,      // Zone 3: Tempo (90-94% LTHR)
            (zone3Upper + 1)...zone4Upper,      // Zone 4: Threshold (95-99% LTHR)
            lthr...zone5Upper                    // Zone 5: VO2max (100%+ LTHR)
        ]
    }

    // MARK: - HealthKit Integration

    /// Fetch average resting HR over N days from HealthKit
    func fetchAverageRestingHR(days: Int) async -> Int? {
        let now = Date()
        guard let startDate = Calendar.current.date(byAdding: .day, value: -days, to: now) else {
            return nil
        }

        do {
            let samples = try await healthKitManager.fetchRestingHR(
                for: DateInterval(start: startDate, end: now)
            )

            guard !samples.isEmpty else { return nil }

            let average = samples.map { $0.value }.reduce(0.0, +) / Double(samples.count)
            return Int(average.rounded())
        } catch {
            print("HRZoneService: Error fetching resting HR: \(error)")
            return nil
        }
    }

    // MARK: - Linear Regression Helpers

    private struct LinearFit {
        let slope: Double
        let intercept: Double
    }

    /// Least-squares linear fit: power = slope * hrPercent + intercept
    private func linearFit(_ points: [HRPowerDataPoint]) -> LinearFit? {
        let n = Double(points.count)
        guard n >= 2 else { return nil }

        let sumX = points.reduce(0.0) { $0 + Double($1.hrPercent) }
        let sumY = points.reduce(0.0) { $0 + Double($1.avgPower) }
        let sumXY = points.reduce(0.0) { $0 + Double($1.hrPercent) * Double($1.avgPower) }
        let sumX2 = points.reduce(0.0) { $0 + Double($1.hrPercent) * Double($1.hrPercent) }

        let denominator = n * sumX2 - sumX * sumX
        guard abs(denominator) > 0.001 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator
        let intercept = (sumY - slope * sumX) / n

        return LinearFit(slope: slope, intercept: intercept)
    }

    /// Sum of squared residuals for a linear fit
    private func sumOfSquaredResiduals(_ points: [HRPowerDataPoint], slope: Double, intercept: Double) -> Double {
        points.reduce(0.0) { sum, point in
            let predicted = slope * Double(point.hrPercent) + intercept
            let residual = Double(point.avgPower) - predicted
            return sum + residual * residual
        }
    }

    // MARK: - Karvonen Fallback

    private static func karvonenConfig(
        from settings: SettingsService,
        observedMaxHR: Int? = nil,
        computedRestingHR: Int? = nil
    ) -> HRZoneConfig {
        var zones: [ClosedRange<Int>] = []
        for zone in 1...5 {
            zones.append(settings.hrZoneBounds(zone: zone))
        }

        return HRZoneConfig(
            zones: zones,
            model: .karvonen,
            lthr: nil,
            observedMaxHR: observedMaxHR,
            computedRestingHR: computedRestingHR,
            confidence: 0
        )
    }
}

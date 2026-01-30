import Foundation

struct TelemetrySample {
    let timestamp: Date
    let elapsedSec: Int
    let power: Int
    let heartRate: Int?
    let cadence: Int?
}

struct TelemetryStatistics {
    var averagePower: Int?
    var maxPower: Int?
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var averageCadence: Int?
    var normalizedPower: Int?
    var sampleCount: Int

    func intensityFactor(ftp: Int) -> Double? {
        guard let np = normalizedPower, ftp > 0 else { return nil }
        return Double(np) / Double(ftp)
    }

    func tss(ftp: Int) -> Double? {
        guard let np = normalizedPower,
              let intF = intensityFactor(ftp: ftp),
              ftp > 0 else { return nil }
        // TSS = (duration_seconds * NP * IF) / (FTP * 3600) * 100
        let durationHours = Double(sampleCount) / 3600.0
        return durationHours * Double(np) * intF / Double(ftp) * 100
    }
}

class TelemetryAggregator {
    private(set) var startTime: Date?
    private var samples: [TelemetrySample] = []
    private var isRecording = false
    private var elapsedSeconds: Int = 0

    // Rolling window for normalized power (30 seconds)
    private var rollingPowerWindow: [Int] = []
    private let rollingWindowSize = 30

    // Rolling windows for performance condition (5 minutes = 300 seconds)
    private var rolling5MinPowerWindow: [Int] = []
    private var rolling5MinHRWindow: [Int] = []
    private let rolling5MinWindowSize = 300

    // For 30-second rolling average
    private var fourthPowerSum: Double = 0
    private var rollingAverageCount: Int = 0

    // Rolling 20-min power for FTP estimation
    private var rolling20MinPowerWindow: [Int] = []
    private let rolling20MinWindowSize = 1200  // 20 minutes

    func start() {
        startTime = Date()
        isRecording = true
        elapsedSeconds = 0
        samples.removeAll()
        rollingPowerWindow.removeAll()
        rolling5MinPowerWindow.removeAll()
        rolling5MinHRWindow.removeAll()
        rolling20MinPowerWindow.removeAll()
        fourthPowerSum = 0
        rollingAverageCount = 0
    }

    func stop() {
        isRecording = false
    }

    func reset() {
        startTime = nil
        isRecording = false
        elapsedSeconds = 0
        samples.removeAll()
        rollingPowerWindow.removeAll()
        rolling5MinPowerWindow.removeAll()
        rolling5MinHRWindow.removeAll()
        rolling20MinPowerWindow.removeAll()
        fourthPowerSum = 0
        rollingAverageCount = 0
    }

    func record(power: Int, heartRate: Int?, cadence: Int?) {
        guard isRecording else { return }

        elapsedSeconds += 1

        let sample = TelemetrySample(
            timestamp: Date(),
            elapsedSec: elapsedSeconds,
            power: power,
            heartRate: heartRate,
            cadence: cadence
        )
        samples.append(sample)

        // Update rolling power window for NP calculation
        rollingPowerWindow.append(power)
        if rollingPowerWindow.count > rollingWindowSize {
            rollingPowerWindow.removeFirst()
        }

        // Calculate rolling 30s average and accumulate fourth power
        if rollingPowerWindow.count == rollingWindowSize {
            let avg = Double(rollingPowerWindow.reduce(0, +)) / Double(rollingWindowSize)
            let fourthPower = pow(avg, 4)
            fourthPowerSum += fourthPower
            rollingAverageCount += 1
        }

        // Update 5-minute rolling windows for performance condition
        rolling5MinPowerWindow.append(power)
        if rolling5MinPowerWindow.count > rolling5MinWindowSize {
            rolling5MinPowerWindow.removeFirst()
        }

        if let hr = heartRate, hr > 0 {
            rolling5MinHRWindow.append(hr)
            if rolling5MinHRWindow.count > rolling5MinWindowSize {
                rolling5MinHRWindow.removeFirst()
            }
        }

        // Update 20-minute rolling window for FTP estimation
        rolling20MinPowerWindow.append(power)
        if rolling20MinPowerWindow.count > rolling20MinWindowSize {
            rolling20MinPowerWindow.removeFirst()
        }
    }

    func getStatistics() -> TelemetryStatistics {
        guard !samples.isEmpty else {
            return TelemetryStatistics(
                averagePower: nil,
                maxPower: nil,
                averageHeartRate: nil,
                maxHeartRate: nil,
                averageCadence: nil,
                normalizedPower: nil,
                sampleCount: 0
            )
        }

        // Average power
        let totalPower = samples.reduce(0) { $0 + $1.power }
        let avgPower = totalPower / samples.count

        // Max power
        let maxPower = samples.map { $0.power }.max() ?? 0

        // Average heart rate (excluding nil and zero values)
        let hrSamples = samples.compactMap { $0.heartRate }.filter { $0 > 0 }
        let avgHR = hrSamples.isEmpty ? nil : hrSamples.reduce(0, +) / hrSamples.count

        // Max heart rate
        let maxHR = hrSamples.max()

        // Average cadence (excluding nil and zero values)
        let cadenceSamples = samples.compactMap { $0.cadence }.filter { $0 > 0 }
        let avgCadence = cadenceSamples.isEmpty ? nil : cadenceSamples.reduce(0, +) / cadenceSamples.count

        // Normalized power
        var np: Int? = nil
        if rollingAverageCount > 0 {
            let avgFourthPower = fourthPowerSum / Double(rollingAverageCount)
            np = Int(pow(avgFourthPower, 0.25))
        }

        return TelemetryStatistics(
            averagePower: avgPower,
            maxPower: maxPower,
            averageHeartRate: avgHR,
            maxHeartRate: maxHR,
            averageCadence: avgCadence,
            normalizedPower: np,
            sampleCount: samples.count
        )
    }

    var currentSamples: [TelemetrySample] {
        samples
    }

    // MARK: - Export for Persistence

    func exportSamples() -> [TelemetrySample] {
        return samples
    }

    // MARK: - Rolling Averages for Performance Condition

    /// Returns the 5-minute rolling average power, or nil if not enough data
    var rolling5MinAvgPower: Int? {
        guard rolling5MinPowerWindow.count >= 60 else { return nil }  // At least 1 minute
        let sum = rolling5MinPowerWindow.reduce(0, +)
        return sum / rolling5MinPowerWindow.count
    }

    /// Returns the 5-minute rolling average heart rate, or nil if not enough data
    var rolling5MinAvgHR: Int? {
        guard rolling5MinHRWindow.count >= 60 else { return nil }  // At least 1 minute
        let sum = rolling5MinHRWindow.reduce(0, +)
        return sum / rolling5MinHRWindow.count
    }

    /// Returns true if we have at least 6 minutes of data (enough for performance condition)
    var hasEnoughDataForPerformanceCondition: Bool {
        elapsedSeconds >= 360  // 6 minutes
    }

    // MARK: - Rolling 20-Min Power for FTP Estimation

    /// Returns the current 20-minute rolling average power, or nil if not enough data
    var rolling20MinAvgPower: Int? {
        guard rolling20MinPowerWindow.count == rolling20MinWindowSize else { return nil }
        let sum = rolling20MinPowerWindow.reduce(0, +)
        return sum / rolling20MinWindowSize
    }

    /// Returns the best (max) 20-minute power seen so far, calculated from samples
    var best20MinPower: Int? {
        guard samples.count >= rolling20MinWindowSize else { return nil }

        var maxAvg = 0
        for i in 0...(samples.count - rolling20MinWindowSize) {
            let window = samples[i..<(i + rolling20MinWindowSize)]
            let sum = window.reduce(0) { $0 + $1.power }
            let avg = sum / rolling20MinWindowSize
            maxAvg = max(maxAvg, avg)
        }
        return maxAvg > 0 ? maxAvg : nil
    }

    // MARK: - Power Duration Best Efforts

    /// Calculate best average power for a given duration in seconds
    func bestPowerForDuration(_ durationSec: Int) -> Int? {
        guard samples.count >= durationSec else { return nil }

        var maxAvg = 0
        for i in 0...(samples.count - durationSec) {
            let window = samples[i..<(i + durationSec)]
            let sum = window.reduce(0) { $0 + $1.power }
            let avg = sum / durationSec
            maxAvg = max(maxAvg, avg)
        }
        return maxAvg > 0 ? maxAvg : nil
    }
}

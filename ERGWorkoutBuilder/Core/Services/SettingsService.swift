import Foundation
import Combine

class SettingsService: ObservableObject {
    private enum Keys {
        static let ftp = "user_ftp"
        static let weight = "user_weight"
        static let maxHR = "user_max_hr"
        static let restingHR = "user_resting_hr"
        static let connectedTrainerId = "connected_trainer_id"
        static let connectedHeartRateId = "connected_hr_id"
        static let claudeAPIKey = "claude_api_key"
        static let healthKitEnabled = "healthkit_enabled"
        static let aiInsightsEnabled = "ai_insights_enabled"
        static let observedMaxHR = "observed_max_hr"
        static let computedRestingHR = "computed_resting_hr"
        static let detectedLTHR = "detected_lthr"
    }

    @Published var ftp: Int {
        didSet {
            UserDefaults.standard.set(ftp, forKey: Keys.ftp)
        }
    }

    @Published var weight: Double {
        didSet {
            UserDefaults.standard.set(weight, forKey: Keys.weight)
        }
    }

    @Published var maxHR: Int {
        didSet {
            UserDefaults.standard.set(maxHR, forKey: Keys.maxHR)
        }
    }

    @Published var restingHR: Int {
        didSet {
            UserDefaults.standard.set(restingHR, forKey: Keys.restingHR)
        }
    }

    @Published var connectedTrainerId: String? {
        didSet {
            UserDefaults.standard.set(connectedTrainerId, forKey: Keys.connectedTrainerId)
        }
    }

    @Published var connectedHeartRateId: String? {
        didSet {
            UserDefaults.standard.set(connectedHeartRateId, forKey: Keys.connectedHeartRateId)
        }
    }

    @Published var claudeAPIKey: String {
        didSet {
            UserDefaults.standard.set(claudeAPIKey, forKey: Keys.claudeAPIKey)
        }
    }

    @Published var healthKitEnabled: Bool {
        didSet {
            UserDefaults.standard.set(healthKitEnabled, forKey: Keys.healthKitEnabled)
        }
    }

    @Published var aiInsightsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(aiInsightsEnabled, forKey: Keys.aiInsightsEnabled)
        }
    }

    @Published var observedMaxHR: Int? {
        didSet {
            if let value = observedMaxHR {
                UserDefaults.standard.set(value, forKey: Keys.observedMaxHR)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.observedMaxHR)
            }
        }
    }

    @Published var computedRestingHR: Int? {
        didSet {
            if let value = computedRestingHR {
                UserDefaults.standard.set(value, forKey: Keys.computedRestingHR)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.computedRestingHR)
            }
        }
    }

    @Published var detectedLTHR: Int? {
        didSet {
            if let value = detectedLTHR {
                UserDefaults.standard.set(value, forKey: Keys.detectedLTHR)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.detectedLTHR)
            }
        }
    }

    init() {
        let savedFtp = UserDefaults.standard.integer(forKey: Keys.ftp)
        self.ftp = savedFtp > 0 ? savedFtp : 200 // Default 200W

        let savedWeight = UserDefaults.standard.double(forKey: Keys.weight)
        self.weight = savedWeight > 0 ? savedWeight : 70.0 // Default 70kg

        let savedMaxHR = UserDefaults.standard.integer(forKey: Keys.maxHR)
        self.maxHR = savedMaxHR > 0 ? savedMaxHR : 185 // Default 185 bpm

        let savedRestingHR = UserDefaults.standard.integer(forKey: Keys.restingHR)
        self.restingHR = savedRestingHR > 0 ? savedRestingHR : 60 // Default 60 bpm

        self.connectedTrainerId = UserDefaults.standard.string(forKey: Keys.connectedTrainerId)
        self.connectedHeartRateId = UserDefaults.standard.string(forKey: Keys.connectedHeartRateId)

        self.claudeAPIKey = UserDefaults.standard.string(forKey: Keys.claudeAPIKey) ?? ""
        self.healthKitEnabled = UserDefaults.standard.bool(forKey: Keys.healthKitEnabled)
        self.aiInsightsEnabled = UserDefaults.standard.bool(forKey: Keys.aiInsightsEnabled)

        let savedObservedMaxHR = UserDefaults.standard.integer(forKey: Keys.observedMaxHR)
        self.observedMaxHR = savedObservedMaxHR > 0 ? savedObservedMaxHR : nil

        let savedComputedRestingHR = UserDefaults.standard.integer(forKey: Keys.computedRestingHR)
        self.computedRestingHR = savedComputedRestingHR > 0 ? savedComputedRestingHR : nil

        let savedDetectedLTHR = UserDefaults.standard.integer(forKey: Keys.detectedLTHR)
        self.detectedLTHR = savedDetectedLTHR > 0 ? savedDetectedLTHR : nil
    }

    func wattsFromPercentFTP(_ percent: Int) -> Int {
        Int(Double(ftp) * Double(percent) / 100.0)
    }

    func percentFTPFromWatts(_ watts: Int) -> Int {
        guard ftp > 0 else { return 0 }
        return Int(Double(watts) / Double(ftp) * 100.0)
    }

    // MARK: - Heart Rate Zones (Karvonen method using HR Reserve)

    var heartRateReserve: Int {
        maxHR - restingHR
    }

    func hrZoneBounds(zone: Int) -> ClosedRange<Int> {
        // 5-zone model based on % of HR Reserve
        let zoneBounds: [(low: Double, high: Double)] = [
            (0.50, 0.60),  // Zone 1: Recovery
            (0.60, 0.70),  // Zone 2: Aerobic
            (0.70, 0.80),  // Zone 3: Tempo
            (0.80, 0.90),  // Zone 4: Threshold
            (0.90, 1.00)   // Zone 5: VO2max
        ]

        guard zone >= 1 && zone <= 5 else { return 0...0 }
        let bounds = zoneBounds[zone - 1]
        let low = restingHR + Int(Double(heartRateReserve) * bounds.low)
        let high = restingHR + Int(Double(heartRateReserve) * bounds.high)
        return low...high
    }

    func hrZoneForHeartRate(_ hr: Int) -> Int {
        for zone in 1...5 {
            if hrZoneBounds(zone: zone).contains(hr) {
                return zone
            }
        }
        return hr < hrZoneBounds(zone: 1).lowerBound ? 1 : 5
    }

    func percentMaxHR(for hr: Int) -> Int {
        guard maxHR > 0 else { return 0 }
        return Int(Double(hr) / Double(maxHR) * 100.0)
    }
}

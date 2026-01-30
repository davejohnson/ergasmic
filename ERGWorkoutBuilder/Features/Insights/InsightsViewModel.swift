import Foundation
import Combine

@MainActor
class InsightsViewModel: ObservableObject {
    // Dependencies
    private let powerCurve: PowerDurationCurve
    private let ftpEstimator: FTPEstimator
    private let performanceAnalyzer: PerformanceAnalyzer
    private let healthKitManager: HealthKitManager
    private let recoveryAnalyzer: RecoveryAnalyzer
    private let rideRepository: RideRepository
    private let settingsService: SettingsService

    // Published state
    @Published var ftpEstimate: FTPEstimate?
    @Published var powerRecords: [PowerDurationRecord] = []
    @Published var recoveryStatus: RecoveryStatus?
    @Published var lastNightSleep: SleepSummary?
    @Published var hrvTrend: (current: Double?, trend: HealthKitManager.HRVTrend)?
    @Published var externalWorkouts: [ExternalWorkout] = []
    @Published var isLoadingRecovery = false
    @Published var error: String?

    private var cancellables = Set<AnyCancellable>()

    init(
        powerCurve: PowerDurationCurve,
        performanceAnalyzer: PerformanceAnalyzer,
        healthKitManager: HealthKitManager,
        rideRepository: RideRepository,
        settingsService: SettingsService
    ) {
        self.powerCurve = powerCurve
        self.ftpEstimator = FTPEstimator(powerCurve: powerCurve)
        self.performanceAnalyzer = performanceAnalyzer
        self.healthKitManager = healthKitManager
        self.recoveryAnalyzer = RecoveryAnalyzer(
            healthKitManager: healthKitManager,
            rideRepository: rideRepository,
            settingsService: settingsService
        )
        self.rideRepository = rideRepository
        self.settingsService = settingsService

        setupSubscriptions()
    }

    private func setupSubscriptions() {
        // Subscribe to power curve updates
        powerCurve.$records
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                self?.powerRecords = records.values.sorted { $0.duration < $1.duration }
                self?.ftpEstimate = self?.ftpEstimator.getBestEstimate()
            }
            .store(in: &cancellables)

        recoveryAnalyzer.$currentStatus
            .receive(on: DispatchQueue.main)
            .assign(to: &$recoveryStatus)

        recoveryAnalyzer.$isAnalyzing
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoadingRecovery)
    }

    // MARK: - Actions

    func loadData() async {
        // Load power records
        powerCurve.loadRecords()
        ftpEstimate = ftpEstimator.getBestEstimate()

        // Load recovery data if HealthKit is enabled
        if settingsService.healthKitEnabled {
            await loadHealthData()
        }
    }

    func loadHealthData() async {
        do {
            // Request authorization if needed
            if !healthKitManager.isAuthorized {
                try await healthKitManager.requestAuthorization()
            }

            // Fetch sleep data
            lastNightSleep = try await healthKitManager.fetchLastNightSleep()

            // Fetch HRV trend
            hrvTrend = try await healthKitManager.fetchHRVTrend(days: 7)

            // Fetch external cycling workouts (Garmin, etc.)
            externalWorkouts = try await healthKitManager.fetchRecentCyclingWorkouts(days: 7)

            // Analyze recovery (includes external workout TSS)
            await recoveryAnalyzer.analyze()

        } catch {
            self.error = "Failed to load health data: \(error.localizedDescription)"
        }
    }

    func clearError() {
        error = nil
    }

    // MARK: - Computed Properties

    var currentFTP: Int {
        settingsService.ftp
    }

    var isHealthKitEnabled: Bool {
        settingsService.healthKitEnabled
    }

    var baselineProgress: Double {
        performanceAnalyzer.baselineProgress
    }

    var baselineStatusText: String {
        performanceAnalyzer.baselineStatusText
    }

    var weeklyTSS: Double {
        let recentRides = rideRepository.fetchRecent(limit: 30)
        let calendar = Calendar.current
        let oneWeekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        // In-app rides TSS
        let inAppTSS = recentRides
            .filter { $0.startedAt >= oneWeekAgo }
            .compactMap { $0.tss }
            .reduce(0.0, +)

        // External rides TSS (from HealthKit)
        let externalTSS = externalWorkouts.compactMap { workout in
            workout.estimatedTSS(
                ftp: settingsService.ftp,
                restingHR: settingsService.restingHR,
                maxHR: settingsService.maxHR
            )
        }.reduce(0.0, +)

        return inAppTSS + externalTSS
    }

    var externalWorkoutCount: Int {
        externalWorkouts.count
    }
}

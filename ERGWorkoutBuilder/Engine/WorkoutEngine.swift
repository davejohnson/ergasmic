import Foundation
import Combine

@MainActor
class WorkoutEngine: ObservableObject {
    // MARK: - Published State

    @Published private(set) var state: WorkoutState = .idle
    @Published private(set) var currentStepIndex: Int = 0
    @Published private(set) var elapsedInStep: Double = 0
    @Published private(set) var totalElapsed: Double = 0
    @Published private(set) var targetPower: Int = 0
    @Published var powerOffset: Int = 0  // Manual adjustment (+/- watts)
    @Published private(set) var actualPower: Int = 0
    @Published private(set) var cadence: Int = 0
    @Published private(set) var heartRate: Int = 0
    @Published private(set) var performanceCondition: PerformanceConditionResult?
    @Published private(set) var isHRControlled: Bool = false  // True when running HR-targeted step
    @Published private(set) var hrControllerStatus: String = ""  // Diagnostic info

    // MARK: - Workout Data

    private(set) var workout: Workout?
    private(set) var expandedSteps: [ExpandedStep] = []
    private var targetCalculator: TargetCalculator?
    private var hrController: HRController?
    private var lastStepIndex: Int = -1  // Track step changes for HR controller reset

    // MARK: - Dependencies

    private weak var trainerDevice: TrainerDevice?
    private weak var heartRateDevice: HeartRateDevice?
    private let settingsService: SettingsService
    private var performanceAnalyzer: PerformanceAnalyzer?

    // MARK: - State Machine

    private let stateMachine = WorkoutStateMachine()
    private var stateMachineCancellable: AnyCancellable?

    // MARK: - Timer

    private var timer: Timer?
    private let tickInterval: TimeInterval = 1.0

    // MARK: - Telemetry

    private var powerCancellable: AnyCancellable?
    private var cadenceCancellable: AnyCancellable?
    private var heartRateCancellable: AnyCancellable?

    let telemetryAggregator = TelemetryAggregator()

    // MARK: - Initialization

    init(settingsService: SettingsService) {
        self.settingsService = settingsService

        stateMachineCancellable = stateMachine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                self?.state = newState
                self?.handleStateChange(newState)
            }
    }

    // MARK: - Setup

    func configure(
        trainer: TrainerDevice?,
        heartRate: HeartRateDevice?,
        performanceAnalyzer: PerformanceAnalyzer? = nil
    ) {
        print("WorkoutEngine: configure called - trainer: \(trainer == nil ? "nil" : "present"), heartRate: \(heartRate == nil ? "nil" : "present")")
        self.trainerDevice = trainer
        self.heartRateDevice = heartRate
        self.performanceAnalyzer = performanceAnalyzer

        setupTelemetrySubscriptions()
    }

    func loadWorkout(_ workout: Workout, ftp: Int? = nil) {
        self.workout = workout
        self.expandedSteps = StepExpander.expand(workout.steps)
        self.targetCalculator = TargetCalculator(ftp: ftp ?? settingsService.ftp)
        resetProgress()
    }

    // MARK: - Controls

    func start() {
        guard state.canStart else { return }
        stateMachine.handle(.startPressed)
    }

    func pause() {
        guard state.canPause else { return }
        stateMachine.handle(.pausePressed)
    }

    func resume() {
        guard state.canResume else { return }
        stateMachine.handle(.resumePressed)
    }

    func stop() {
        stateMachine.handle(.stopPressed)
    }

    func skipForward() {
        guard state.canSkip else { return }
        advanceToNextStep()
    }

    func skipBackward() {
        guard state.canSkip else { return }

        if elapsedInStep > 3 {
            // Restart current step
            elapsedInStep = 0
        } else if currentStepIndex > 0 {
            // Go to previous step
            currentStepIndex -= 1
            elapsedInStep = 0
        }

        updateTarget()
    }

    func increasePower(by watts: Int = 10) {
        powerOffset += watts
        updateTarget()
    }

    func decreasePower(by watts: Int = 10) {
        powerOffset -= watts
        updateTarget()
    }

    func resetPowerOffset() {
        powerOffset = 0
        updateTarget()
    }

    // MARK: - Trainer Connection Events

    func trainerConnected() {
        stateMachine.handle(.trainerConnected)
    }

    func trainerReady() {
        stateMachine.handle(.trainerReady)
    }

    func trainerDisconnected() {
        stateMachine.handle(.trainerDisconnected)
    }

    func trainerReconnected() {
        stateMachine.handle(.reconnected)
    }

    // MARK: - Private Methods

    private func handleStateChange(_ newState: WorkoutState) {
        switch newState {
        case .running:
            print("WorkoutEngine: State changed to RUNNING")
            print("WorkoutEngine: trainerDevice is \(trainerDevice == nil ? "NIL" : "present")")
            // Request FTMS control when workout begins
            // TrainerDevice will automatically call startTraining() when control is granted
            if trainerDevice?.hasControl != true {
                print("WorkoutEngine: Requesting FTMS control...")
                trainerDevice?.requestControl()
            }
            startTimer()
            updateTarget()
            telemetryAggregator.start()

        case .paused:
            stopTimer()
            trainerDevice?.pauseTraining()

        case .finished:
            stopTimer()
            trainerDevice?.stopTraining()
            telemetryAggregator.stop()

        case .ready:
            resetProgress()

        case .idle, .connecting, .error:
            stopTimer()
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard state == .running else { return }

        totalElapsed += tickInterval
        elapsedInStep += tickInterval

        // Check if step is complete
        if let currentStep = currentExpandedStep,
           elapsedInStep >= Double(currentStep.durationSec) {
            advanceToNextStep()
        } else {
            updateTarget()
        }

        // Update HR controller for HR-targeted steps
        updateHRController()

        // Record telemetry
        telemetryAggregator.record(
            power: actualPower,
            heartRate: heartRate > 0 ? heartRate : nil,
            cadence: cadence > 0 ? cadence : nil
        )

        // Calculate performance condition if analyzer is available
        updatePerformanceCondition()
    }

    private func updateHRController() {
        guard let step = currentExpandedStep else {
            isHRControlled = false
            hrControllerStatus = ""
            return
        }

        // Check if we moved to a new step
        if currentStepIndex != lastStepIndex {
            lastStepIndex = currentStepIndex

            if step.isHRTargeted {
                // Initialize or reset HR controller for new HR-targeted step
                if hrController == nil {
                    hrController = HRController(
                        targetHRLow: step.targetHRLow,
                        targetHRHigh: step.targetHRHigh,
                        initialPowerPct: step.fallbackPct
                    )
                } else {
                    hrController?.reset(
                        targetHRLow: step.targetHRLow,
                        targetHRHigh: step.targetHRHigh,
                        initialPowerPct: step.fallbackPct
                    )
                }
                isHRControlled = true
            } else {
                isHRControlled = false
                hrControllerStatus = ""
            }
        }

        // Update HR controller if active
        if isHRControlled, let controller = hrController, let calculator = targetCalculator {
            let currentHR = heartRate > 0 ? heartRate : nil
            let adjustedPowerPct = controller.update(currentHR: currentHR, deltaTime: tickInterval)
            let adjustedPowerWatts = calculator.calculateTargetWatts(for: step, hrControllerPowerPct: adjustedPowerPct)

            // Apply power offset and set target
            let finalTarget = max(0, adjustedPowerWatts + powerOffset)
            targetPower = finalTarget
            trainerDevice?.setTargetPower(finalTarget)

            // Update status for UI
            hrControllerStatus = controller.diagnosticInfo
        }
    }

    private func updatePerformanceCondition() {
        guard let analyzer = performanceAnalyzer else {
            performanceCondition = nil
            return
        }

        performanceCondition = analyzer.calculatePerformanceCondition(
            currentPower: actualPower,
            currentHR: heartRate,
            rolling5MinPower: telemetryAggregator.rolling5MinAvgPower,
            rolling5MinHR: telemetryAggregator.rolling5MinAvgHR,
            elapsedSeconds: Int(totalElapsed)
        )
    }

    private func advanceToNextStep() {
        currentStepIndex += 1

        if currentStepIndex >= expandedSteps.count {
            stateMachine.handle(.workoutCompleted)
        } else {
            elapsedInStep = 0
            updateTarget()
        }
    }

    private func updateTarget() {
        guard let step = currentExpandedStep,
              let calculator = targetCalculator else {
            print("WorkoutEngine: updateTarget failed - no step or calculator")
            return
        }

        // HR-targeted steps are handled by updateHRController()
        guard !step.isHRTargeted else { return }

        let baseTarget = calculator.calculateTargetWatts(for: step, elapsedInStep: elapsedInStep)
        let adjustedTarget = max(0, baseTarget + powerOffset)  // Apply offset, don't go below 0
        targetPower = adjustedTarget

        if trainerDevice == nil {
            print("WorkoutEngine: WARNING - trainerDevice is nil!")
        } else {
            if powerOffset != 0 {
                print("WorkoutEngine: Setting target power to \(adjustedTarget)W (base: \(baseTarget)W, offset: \(powerOffset > 0 ? "+" : "")\(powerOffset)W)")
            } else {
                print("WorkoutEngine: Setting target power to \(adjustedTarget)W")
            }
        }
        trainerDevice?.setTargetPower(adjustedTarget)
    }

    private func resetProgress() {
        currentStepIndex = 0
        elapsedInStep = 0
        totalElapsed = 0
        targetPower = 0
        telemetryAggregator.reset()
        hrController = nil
        lastStepIndex = -1
        isHRControlled = false
        hrControllerStatus = ""
    }

    private func setupTelemetrySubscriptions() {
        powerCancellable = trainerDevice?.$currentPower
            .receive(on: DispatchQueue.main)
            .sink { [weak self] power in
                self?.actualPower = power
            }

        // Cadence comes from the trainer (FTMS Indoor Bike Data)
        cadenceCancellable = trainerDevice?.$currentCadence
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cad in
                self?.cadence = cad
            }

        heartRateCancellable = heartRateDevice?.$currentHeartRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hr in
                self?.heartRate = hr
            }
    }

    // MARK: - Computed Properties

    var currentExpandedStep: ExpandedStep? {
        guard currentStepIndex < expandedSteps.count else { return nil }
        return expandedSteps[currentStepIndex]
    }

    var stepRemainingTime: Int {
        guard let step = currentExpandedStep else { return 0 }
        return max(0, step.durationSec - Int(elapsedInStep))
    }

    var totalRemainingTime: Int {
        let currentStepRemaining = stepRemainingTime
        let futureTime = expandedSteps.dropFirst(currentStepIndex + 1).reduce(0) { $0 + $1.durationSec }
        return currentStepRemaining + futureTime
    }

    var totalWorkoutDuration: Int {
        expandedSteps.reduce(0) { $0 + $1.durationSec }
    }

    var progress: Double {
        guard totalWorkoutDuration > 0 else { return 0 }
        return totalElapsed / Double(totalWorkoutDuration)
    }

    var stepProgress: Double {
        guard let step = currentExpandedStep, step.durationSec > 0 else { return 0 }
        return elapsedInStep / Double(step.durationSec)
    }

    // MARK: - Ride Summary

    func generateRideSummary() -> Ride {
        let stats = telemetryAggregator.getStatistics()

        return Ride(
            workoutId: workout?.id,
            workoutName: workout?.name ?? "Unknown Workout",
            startedAt: telemetryAggregator.startTime ?? Date(),
            endedAt: Date(),
            ftpUsed: settingsService.ftp,
            status: state == .finished ? .completed : .abandoned,
            avgPower: stats.averagePower,
            avgHeartRate: stats.averageHeartRate,
            avgCadence: stats.averageCadence,
            durationSec: Int(totalElapsed),
            normalizedPower: stats.normalizedPower,
            intensityFactor: stats.intensityFactor(ftp: settingsService.ftp),
            tss: stats.tss(ftp: settingsService.ftp)
        )
    }
}

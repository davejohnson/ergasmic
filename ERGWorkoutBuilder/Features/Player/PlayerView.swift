import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var settingsService: SettingsService
    @State private var engine: WorkoutEngine?
    @State private var hasInitialized = false

    let workout: Workout
    var ftpOverride: Int?
    var hrTargetLowOverride: Int?
    var hrTargetHighOverride: Int?

    var body: some View {
        Group {
            if let engine = engine {
                PlayerContentView(
                    workout: workout,
                    engine: engine,
                    bleManager: bleManager,
                    onDismiss: { dismiss() }
                )
            } else {
                ZStack {
                    Color.black.ignoresSafeArea()
                    ProgressView()
                        .tint(.white)
                }
            }
        }
        .onAppear {
            initializeEngine()
        }
        .onChange(of: bleManager.trainerConnectionState) { _, newState in
            handleTrainerStateChange(newState)
        }
    }

    private func initializeEngine() {
        guard !hasInitialized else { return }
        hasInitialized = true

        let newEngine = WorkoutEngine(settingsService: settingsService)
        newEngine.configure(
            trainer: bleManager.trainerDevice,
            heartRate: bleManager.heartRateDevice
        )

        // Apply HR target overrides to workout if provided
        var adjustedWorkout = workout
        if hrTargetLowOverride != nil || hrTargetHighOverride != nil {
            adjustedWorkout.steps = workout.steps.map { applyHROverrides($0) }
        }

        // Load workout with optional FTP override
        let ftpToUse = ftpOverride ?? settingsService.ftp
        newEngine.loadWorkout(adjustedWorkout, ftp: ftpToUse)

        if bleManager.trainerConnectionState == .ready ||
           bleManager.trainerConnectionState == .connected {
            newEngine.trainerReady()
        }

        self.engine = newEngine
    }

    private func applyHROverrides(_ step: WorkoutStep) -> WorkoutStep {
        var adjusted = step
        if step.type == .hrTarget {
            if let low = hrTargetLowOverride {
                adjusted.targetHRLow = low
            }
            if let high = hrTargetHighOverride {
                adjusted.targetHRHigh = high
            }
        } else if step.type == .repeats {
            adjusted.children = step.children.map { applyHROverrides($0) }
        }
        return adjusted
    }

    private func handleTrainerStateChange(_ state: BLEConnectionState) {
        guard let engine = engine else { return }

        switch state {
        case .ready, .connected:
            engine.trainerReady()
        case .disconnected:
            engine.trainerDisconnected()
        default:
            break
        }
    }
}

// MARK: - Player Content View

struct PlayerContentView: View {
    let workout: Workout
    @ObservedObject var engine: WorkoutEngine
    let bleManager: BLEManager
    let onDismiss: () -> Void

    @State private var showingSummary = false
    @State private var showingEndConfirmation = false

    // Single accent color with variations
    private let accent = Color.cyan

    var body: some View {
        ZStack {
            // Background
            Color(red: 0.05, green: 0.05, blue: 0.07)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer()

                // Main Power Display
                powerDisplay

                Spacer()

                // Secondary Metrics
                secondaryMetrics
                    .padding(.horizontal, 40)

                Spacer()

                // Step Progress Section
                stepProgressSection
                    .padding(.horizontal, 20)

                // Controls
                controls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showingSummary) {
            SummaryView(ride: engine.generateRideSummary()) {
                onDismiss()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { showingEndConfirmation = true } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(.white.opacity(0.1)))
            }

            Spacer()

            VStack(spacing: 2) {
                Text(workout.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))

                Text(engine.state.displayText)
                    .font(.system(size: 11))
                    .foregroundColor(engine.state == .running ? accent : .white.opacity(0.4))
            }

            Spacer()

            // Spacer for balance
            Color.clear.frame(width: 32, height: 32)
        }
    }

    // MARK: - Power Display (Hero)

    private var powerDisplay: some View {
        VStack(spacing: 8) {
            Text("\(engine.actualPower)")
                .font(.system(size: 120, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("WATTS")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .tracking(3)
        }
    }

    // MARK: - Secondary Metrics

    private var secondaryMetrics: some View {
        HStack(spacing: 40) {
            // Heart Rate
            VStack(spacing: 4) {
                Text(engine.heartRate > 0 ? "\(engine.heartRate)" : "--")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
                Text("BPM")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)
            }

            // Cadence
            VStack(spacing: 4) {
                Text(engine.cadence > 0 ? "\(engine.cadence)" : "--")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .monospacedDigit()
                Text("RPM")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)
            }
        }
    }

    // MARK: - Step Progress Section

    private var stepProgressSection: some View {
        VStack(spacing: 16) {
            // Current Step Info with Target
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let step = engine.currentExpandedStep {
                        Text(step.displayLabel.isEmpty ? "Step \(engine.currentStepIndex + 1)" : step.displayLabel)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(engine.targetPower)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(accent)
                        Text("W target")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.4))

                        if engine.powerOffset != 0 {
                            Text("(\(engine.powerOffset > 0 ? "+" : "")\(engine.powerOffset))")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(accent.opacity(0.7))
                                .onTapGesture {
                                    engine.resetPowerOffset()
                                }
                        }
                    }
                }

                Spacer()

                // Power adjustment
                HStack(spacing: 12) {
                    Button { engine.decreasePower() } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }
                    .disabled(!engine.state.isActive)

                    Button { engine.increasePower() } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(.white.opacity(0.1)))
                    }
                    .disabled(!engine.state.isActive)
                }
            }

            // Step Progress Bar
            VStack(spacing: 6) {
                ProgressBar(
                    progress: engine.stepProgress,
                    label: "Step",
                    timeRemaining: engine.stepRemainingTime,
                    color: accent
                )

                ProgressBar(
                    progress: engine.progress,
                    label: "Total",
                    timeRemaining: engine.totalRemainingTime,
                    color: accent.opacity(0.5)
                )
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.05))
        )
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 24) {
            Spacer()

            // Skip back
            Button { engine.skipBackward() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(engine.state.canSkip ? 0.6 : 0.2))
                    .frame(width: 48, height: 48)
            }
            .disabled(!engine.state.canSkip)

            // Main control
            Button {
                switch engine.state {
                case .ready: engine.start()
                case .running: engine.pause()
                case .paused: engine.resume()
                case .finished: showingSummary = true
                default: break
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(accent)
                        .frame(width: 72, height: 72)

                    Image(systemName: mainControlIcon)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.black)
                }
            }

            // Skip forward
            Button { engine.skipForward() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(engine.state.canSkip ? 0.6 : 0.2))
                    .frame(width: 48, height: 48)
            }
            .disabled(!engine.state.canSkip)

            Spacer()
        }
        .confirmationDialog("End Workout?", isPresented: $showingEndConfirmation, titleVisibility: .visible) {
            Button("Save") {
                engine.stop()
                showingSummary = true
            }
            Button("Discard", role: .destructive) {
                engine.stop()
                onDismiss()
            }
            Button("Cancel", role: .cancel) { }
        }
    }

    private var mainControlIcon: String {
        switch engine.state {
        case .ready, .paused: return "play.fill"
        case .running: return "pause.fill"
        case .finished: return "checkmark"
        default: return "circle.fill"
        }
    }
}

// MARK: - Progress Bar

struct ProgressBar: View {
    let progress: Double
    let label: String
    let timeRemaining: Int
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .frame(width: 36, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.1))

                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1, max(0, progress)))
                }
            }
            .frame(height: 6)

            Text(formatTime(timeRemaining))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.5))
                .monospacedDigit()
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    PlayerView(workout: Workout(
        name: "Threshold Builder",
        steps: [
            .steady(durationSec: 300, intensityPct: 50),
            .ramp(durationSec: 300, startPct: 50, endPct: 100),
            .steady(durationSec: 300, intensityPct: 50)
        ]
    ))
    .environmentObject(BLEManager())
    .environmentObject(SettingsService())
}

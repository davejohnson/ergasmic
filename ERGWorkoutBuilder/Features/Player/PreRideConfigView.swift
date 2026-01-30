import SwiftUI

struct PreRideConfigView: View {
    let workout: Workout
    let onStart: (Workout) -> Void
    let onCancel: () -> Void

    // Optional pre-fill values from AI coach recommendation
    var initialFTP: Int?
    var initialHRLow: Int?
    var initialHRHigh: Int?
    var initialDurationScale: Double?

    @EnvironmentObject var settingsService: SettingsService
    @State private var ftp: Int = 200
    @State private var durationScale: Double = 1.0
    @State private var hrTargetLow: Int = 120
    @State private var hrTargetHigh: Int = 140

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    workoutHeader
                    stepsSection
                    ftpSection
                    if hasHRTargetSteps {
                        hrTargetSection
                    }
                    durationSection
                    powerPreview
                    Spacer(minLength: 24)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Configure Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        onStart(adjustedWorkout)
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Use pre-fill values if provided, otherwise use defaults
                ftp = initialFTP ?? settingsService.ftp
                durationScale = initialDurationScale ?? 1.0

                // Initialize HR targets from pre-fill or first HR target step
                if let low = initialHRLow, let high = initialHRHigh {
                    hrTargetLow = low
                    hrTargetHigh = high
                } else if let hrStep = workout.steps.first(where: { $0.type == .hrTarget }) {
                    hrTargetLow = hrStep.targetHRLow
                    hrTargetHigh = hrStep.targetHRHigh
                }
            }
        }
    }

    // MARK: - Workout Header

    private var workoutHeader: some View {
        VStack(spacing: 12) {
            Text(workout.name)
                .font(.title2)
                .fontWeight(.bold)

            if !workout.notes.isEmpty {
                Text(workout.notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 16) {
                Label(formatDuration(adjustedTotalDuration), systemImage: "clock")
                Label("\(workout.steps.count) steps", systemImage: "list.bullet")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Steps Section

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Steps")
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(workout.steps.enumerated()), id: \.element.id) { index, step in
                    stepRow(step, index: index + 1)
                    if index < workout.steps.count - 1 {
                        Divider()
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func stepRow(_ step: WorkoutStep, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index)")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(width: 20)

            stepIcon(for: step)
                .foregroundColor(colorForStepType(step.type))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(stepLabel(step))
                    .font(.subheadline)
                Text(formatDuration(Int(Double(step.totalDurationSec) * durationScale)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(stepPowerLabel(step))
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundColor(colorForStepType(step.type))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func stepIcon(for step: WorkoutStep) -> some View {
        Group {
            switch step.type {
            case .steady: Image(systemName: "minus")
            case .ramp: Image(systemName: "arrow.up.right")
            case .repeats: Image(systemName: "repeat")
            case .hrTarget: Image(systemName: "heart")
            }
        }
    }

    private func stepLabel(_ step: WorkoutStep) -> String {
        switch step.type {
        case .steady: return "Steady"
        case .ramp: return "Ramp"
        case .repeats: return "\(step.repeatCount)x Repeat"
        case .hrTarget: return "HR Target"
        }
    }

    private func stepPowerLabel(_ step: WorkoutStep) -> String {
        switch step.type {
        case .steady:
            return "\(step.intensityPct)% (\(wattsForPercent(step.intensityPct))W)"
        case .ramp:
            return "\(step.startPct)%→\(step.endPct)%"
        case .repeats:
            let children = step.children.map { stepPowerLabel($0) }.joined(separator: " / ")
            return children
        case .hrTarget:
            return "\(step.targetHRLow)-\(step.targetHRHigh) bpm"
        }
    }

    private func colorForStepType(_ type: StepType) -> Color {
        switch type {
        case .steady: return .blue
        case .ramp: return .orange
        case .repeats: return .purple
        case .hrTarget: return .red
        }
    }

    // MARK: - FTP Section

    private var ftpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Functional Threshold Power")
                .font(.headline)

            HStack {
                Text("FTP")
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 4) {
                    TextField("FTP", value: $ftp, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                    Text("W")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )

            Text("Power targets will be calculated based on this FTP value")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - HR Target Section

    private var hasHRTargetSteps: Bool {
        workout.steps.contains { $0.type == .hrTarget }
    }

    private var hrTargetSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate Target")
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Text("Low")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("Low", value: $hrTargetLow, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("bpm")
                            .foregroundColor(.secondary)
                    }
                }

                HStack {
                    Text("High")
                        .foregroundColor(.secondary)
                    Spacer()
                    HStack(spacing: 4) {
                        TextField("High", value: $hrTargetHigh, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 50)
                        Text("bpm")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )

            Text("Power will automatically adjust to keep your heart rate in this zone")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Duration Section

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Duration")
                .font(.headline)

            VStack(spacing: 8) {
                HStack {
                    Text("Scale")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1fx", durationScale))
                        .fontWeight(.medium)
                        .monospacedDigit()
                }

                Slider(value: $durationScale, in: 1.0...2.0, step: 0.1)
                    .tint(.blue)

                HStack {
                    Text("1x")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("2x")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )

            Text("Adjust the workout duration while keeping intensity the same")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Power Preview

    private var powerPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Power Zones Preview")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(uniqueIntensities.sorted(), id: \.self) { pct in
                    HStack {
                        Text("\(pct)%")
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)

                        ProgressView(value: Double(pct), total: 150)
                            .tint(colorForIntensity(pct))

                        Text("\(wattsForPercent(pct))W")
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Computed Properties

    private var adjustedWorkout: Workout {
        var adjusted = workout
        adjusted.steps = workout.steps.map { adjustStep($0) }
        return adjusted
    }

    private func adjustStep(_ step: WorkoutStep) -> WorkoutStep {
        var adjusted = step
        adjusted.durationSec = Int(Double(step.durationSec) * durationScale)

        switch step.type {
        case .repeats:
            adjusted.children = step.children.map { adjustStep($0) }
        case .hrTarget:
            adjusted.targetHRLow = hrTargetLow
            adjusted.targetHRHigh = hrTargetHigh
        default:
            break
        }

        return adjusted
    }

    private var adjustedTotalDuration: Int {
        Int(Double(workout.totalDurationSec) * durationScale)
    }

    private var uniqueIntensities: Set<Int> {
        var intensities = Set<Int>()
        collectIntensities(from: workout.steps, into: &intensities)
        return intensities
    }

    private func collectIntensities(from steps: [WorkoutStep], into set: inout Set<Int>) {
        for step in steps {
            switch step.type {
            case .steady:
                set.insert(step.intensityPct)
            case .ramp:
                set.insert(step.startPct)
                set.insert(step.endPct)
            case .repeats:
                collectIntensities(from: step.children, into: &set)
            case .hrTarget:
                set.insert(step.fallbackPct)  // Show fallback power in preview
            }
        }
    }

    private func wattsForPercent(_ pct: Int) -> Int {
        Int(Double(ftp) * Double(pct) / 100.0)
    }

    private func colorForIntensity(_ pct: Int) -> Color {
        switch pct {
        case ..<56: return .gray
        case 56..<76: return .blue
        case 76..<91: return .green
        case 91..<106: return .yellow
        case 106..<121: return .orange
        default: return .red
        }
    }
}

#Preview {
    PreRideConfigView(
        workout: Workout(
            name: "Test Workout",
            notes: "A test workout description",
            steps: [
                .ramp(durationSec: 300, startPct: 40, endPct: 55),
                .steady(durationSec: 600, intensityPct: 75),
                .ramp(durationSec: 300, startPct: 75, endPct: 40)
            ]
        ),
        onStart: { _ in },
        onCancel: {},
        initialFTP: nil,
        initialHRLow: nil,
        initialHRHigh: nil,
        initialDurationScale: nil
    )
    .environmentObject(SettingsService())
}

import SwiftUI

struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var settingsService: SettingsService
    @State private var showingBuilder = false
    @State private var workoutToEdit: Workout?
    @State private var workoutToConfig: Workout?
    @State private var workoutToPlay: Workout?

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                if viewModel.workouts.isEmpty {
                    emptyStateView
                } else {
                    workoutListView
                }
            }
            .navigationTitle("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        workoutToEdit = nil
                        showingBuilder = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .sheet(isPresented: $showingBuilder) {
                if let workout = workoutToEdit {
                    BuilderView(workout: workout) { updatedWorkout in
                        viewModel.save(updatedWorkout)
                        workoutToEdit = nil
                    }
                } else {
                    BuilderView(workout: Workout()) { newWorkout in
                        viewModel.save(newWorkout)
                    }
                }
            }
            .sheet(item: $workoutToConfig) { workout in
                PreRideConfigView(
                    workout: workout,
                    onStart: { adjusted in
                        workoutToConfig = nil
                        workoutToPlay = adjusted
                    },
                    onCancel: {
                        workoutToConfig = nil
                    }
                )
                .environmentObject(settingsService)
            }
            .fullScreenCover(item: $workoutToPlay, onDismiss: {
                workoutToPlay = nil
            }) { workout in
                PlayerView(workout: workout)
                    .environmentObject(bleManager)
                    .environmentObject(settingsService)
            }
            .onAppear {
                viewModel.loadWorkouts()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "figure.indoor.cycle")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("No Workouts Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Create your first structured workout\nto start training")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                workoutToEdit = nil
                showingBuilder = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create Workout")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(Capsule())
                .shadow(color: .blue.opacity(0.3), radius: 8, y: 4)
            }
        }
        .padding()
    }

    private var workoutListView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.workouts) { workout in
                    WorkoutCard(workout: workout)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            workoutToConfig = workout
                        }
                        .contextMenu {
                            Button {
                                workoutToEdit = workout
                                showingBuilder = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button {
                                viewModel.duplicate(workout)
                            } label: {
                                Label("Duplicate", systemImage: "doc.on.doc")
                            }

                            Divider()

                            Button(role: .destructive) {
                                viewModel.delete(workout)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }
}

struct WorkoutCard: View {
    let workout: Workout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)

                    if !workout.notes.isEmpty {
                        Text(workout.notes)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // Workout visualization bar
            WorkoutVisualizationBar(steps: workout.steps)
                .frame(height: 32)

            HStack(spacing: 16) {
                Label(workout.formattedDuration, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Label("\(workout.steps.count) steps", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Intensity indicator
                if let avgIntensity = averageIntensity {
                    IntensityBadge(intensity: avgIntensity)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
    }

    private var averageIntensity: Int? {
        let intensities = workout.steps.compactMap { step -> Int? in
            switch step.type {
            case .steady: return step.intensityPct
            case .ramp: return (step.startPct + step.endPct) / 2
            case .repeats: return nil
            case .hrTarget: return step.fallbackPct
            }
        }
        guard !intensities.isEmpty else { return nil }
        return intensities.reduce(0, +) / intensities.count
    }
}

struct WorkoutVisualizationBar: View {
    let steps: [WorkoutStep]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(Array(flattenedSteps.enumerated()), id: \.offset) { index, step in
                    stepBar(for: step)
                        .frame(width: stepWidth(for: step, totalWidth: geometry.size.width))
                }
            }
            .frame(width: geometry.size.width, alignment: .leading)
        }
    }

    private var flattenedSteps: [WorkoutStep] {
        var result: [WorkoutStep] = []
        for step in steps {
            if step.type == .repeats {
                for _ in 0..<min(step.repeatCount, 3) {
                    result.append(contentsOf: step.children)
                }
            } else {
                result.append(step)
            }
        }
        return result
    }

    private var totalDuration: Int {
        flattenedSteps.reduce(0) { $0 + $1.durationSec }
    }

    private func stepWidth(for step: WorkoutStep, totalWidth: CGFloat) -> CGFloat {
        guard totalDuration > 0 else { return 0 }
        let stepCount = CGFloat(flattenedSteps.count)
        let totalSpacing = max(0, stepCount - 1) // 1px spacing between steps
        let availableWidth = totalWidth - totalSpacing
        let proportionalWidth = availableWidth * CGFloat(step.durationSec) / CGFloat(totalDuration)
        return max(2, proportionalWidth) // Minimum 2px to remain visible
    }

    private func stepBar(for step: WorkoutStep) -> some View {
        let intensity: Int
        switch step.type {
        case .ramp:
            intensity = (step.startPct + step.endPct) / 2
        case .hrTarget:
            intensity = step.fallbackPct
        default:
            intensity = step.intensityPct
        }
        return RoundedRectangle(cornerRadius: 4)
            .fill(colorForIntensity(intensity))
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

struct IntensityBadge: View {
    let intensity: Int

    var body: some View {
        Text("\(intensity)%")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(badgeColor.opacity(0.15))
            )
    }

    private var badgeColor: Color {
        switch intensity {
        case ..<76: return .blue
        case 76..<91: return .green
        case 91..<106: return .yellow
        case 106..<121: return .orange
        default: return .red
        }
    }
}

#Preview {
    LibraryView()
        .environmentObject(BLEManager())
        .environmentObject(SettingsService())
}

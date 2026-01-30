import SwiftUI

/// Card displaying a workout recommendation with action buttons
struct RecommendationCard: View {
    let recommendation: WorkoutRecommendation
    let onStart: () -> Void
    let onAdjust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Workout header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(recommendation.workout.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        Label(formattedDuration, systemImage: "clock")
                        if let scale = adjustedDurationText {
                            Text(scale)
                                .foregroundColor(.orange)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                // Workout type badge
                workoutTypeBadge
            }

            // Intensity visualization bar
            WorkoutIntensityBar(steps: recommendation.workout.steps)
                .frame(height: 32)

            // Adjustments info
            if hasAdjustments {
                adjustmentsSection
            }

            // Action buttons
            HStack(spacing: 12) {
                Button(action: onAdjust) {
                    Label("Adjust", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Computed Properties

    private var formattedDuration: String {
        let baseDuration = recommendation.workout.totalDurationSec
        let scaledDuration = Int(Double(baseDuration) * recommendation.durationScale)
        return formatDuration(scaledDuration)
    }

    private var adjustedDurationText: String? {
        guard recommendation.durationScale != 1.0 else { return nil }
        return String(format: "%.1fx duration", recommendation.durationScale)
    }

    private var hasAdjustments: Bool {
        recommendation.suggestedFTP != nil || recommendation.suggestedHRTargets != nil
    }

    private var workoutTypeBadge: some View {
        let (text, color) = workoutTypeInfo
        return Text(text)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .clipShape(Capsule())
    }

    private var workoutTypeInfo: (String, Color) {
        let name = recommendation.workout.name.lowercased()
        if name.contains("zone 2") || name.contains("endurance") {
            return ("Endurance", .blue)
        } else if name.contains("sweet spot") {
            return ("Sweet Spot", .green)
        } else if name.contains("over under") || name.contains("threshold") {
            return ("Threshold", .orange)
        } else if name.contains("wringer") || name.contains("vo2") {
            return ("VO2max", .red)
        } else if name.contains("hr") {
            return ("HR Control", .purple)
        }
        return ("Workout", .gray)
    }

    private var adjustmentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()

            if let ftp = recommendation.suggestedFTP {
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.yellow)
                    Text("FTP adjusted to \(ftp)W")
                        .font(.caption)
                }
            }

            if let hrTargets = recommendation.suggestedHRTargets {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(.red)
                    Text("HR target: \(hrTargets.low)-\(hrTargets.high) bpm")
                        .font(.caption)
                }
            }
        }
    }
}

/// Simple visualization bar showing workout intensity profile
struct WorkoutIntensityBar: View {
    let steps: [WorkoutStep]

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 1) {
                ForEach(flattenedSteps.indices, id: \.self) { index in
                    let step = flattenedSteps[index]
                    stepBar(for: step, totalDuration: totalDuration, width: geometry.size.width)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var flattenedSteps: [WorkoutStep] {
        var result: [WorkoutStep] = []
        flattenSteps(steps, into: &result)
        return result
    }

    private func flattenSteps(_ steps: [WorkoutStep], into result: inout [WorkoutStep]) {
        for step in steps {
            if step.type == .repeats {
                for _ in 0..<step.repeatCount {
                    flattenSteps(step.children, into: &result)
                }
            } else {
                result.append(step)
            }
        }
    }

    private var totalDuration: Int {
        flattenedSteps.reduce(0) { $0 + $1.durationSec }
    }

    private func stepBar(for step: WorkoutStep, totalDuration: Int, width: CGFloat) -> some View {
        let proportion = totalDuration > 0 ? CGFloat(step.durationSec) / CGFloat(totalDuration) : 0
        let barWidth = max(2, proportion * width)

        return Rectangle()
            .fill(colorForStep(step))
            .frame(width: barWidth)
    }

    private func colorForStep(_ step: WorkoutStep) -> Color {
        let intensity: Int
        switch step.type {
        case .steady:
            intensity = step.intensityPct
        case .ramp:
            intensity = (step.startPct + step.endPct) / 2
        case .hrTarget:
            intensity = step.fallbackPct
        case .repeats:
            intensity = 50
        }

        switch intensity {
        case ..<56: return Color.gray
        case 56..<76: return Color.blue
        case 76..<91: return Color.green
        case 91..<106: return Color.yellow
        case 106..<121: return Color.orange
        default: return Color.red
        }
    }
}

#Preview {
    VStack {
        RecommendationCard(
            recommendation: WorkoutRecommendation(
                workout: DefaultWorkouts.sweetSpot(),
                reasoning: "Based on your good recovery score and your desire to push today, Sweet Spot is perfect for building threshold power.",
                suggestedFTP: nil,
                suggestedHRTargets: nil,
                durationScale: 1.0
            ),
            onStart: {},
            onAdjust: {}
        )

        RecommendationCard(
            recommendation: WorkoutRecommendation(
                workout: DefaultWorkouts.zone2HR(),
                reasoning: "With your low recovery score, let's focus on easy aerobic work with heart rate control.",
                suggestedFTP: nil,
                suggestedHRTargets: (low: 125, high: 140),
                durationScale: 1.2
            ),
            onStart: {},
            onAdjust: {}
        )
    }
    .padding()
}

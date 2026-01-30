import SwiftUI

struct SummaryView: View {
    let ride: Ride
    let onDismiss: () -> Void

    @State private var hasAcknowledged = false
    @State private var showStats = false

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.08, blue: 0.12),
                    Color(red: 0.04, green: 0.04, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    // Celebration Header
                    celebrationHeader
                        .padding(.top, 40)

                    // Stats Grid
                    if showStats {
                        statsSection
                            .transition(.opacity.combined(with: .move(edge: .bottom)))

                        // Advanced Metrics
                        advancedMetricsSection
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 24)
            }

            // Bottom button
            VStack {
                Spacer()
                bottomButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
            }
        }
        .interactiveDismissDisabled(!hasAcknowledged)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                showStats = true
            }
        }
    }

    // MARK: - Celebration Header

    private var celebrationHeader: some View {
        VStack(spacing: 20) {
            // Animated checkmark/icon
            ZStack {
                // Outer ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: statusGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 100, height: 100)

                // Inner fill
                Circle()
                    .fill(
                        LinearGradient(
                            colors: statusGradientColors.map { $0.opacity(0.2) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 92, height: 92)

                Image(systemName: ride.status == .completed ? "checkmark" : "flag.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: statusGradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text(ride.status == .completed ? "Workout Complete!" : "Workout Ended")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)

                Text(ride.workoutName)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }

            // Duration highlight
            Text(ride.formattedDuration)
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
    }

    private var statusGradientColors: [Color] {
        ride.status == .completed ? [.green, .cyan] : [.orange, .yellow]
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                SummaryStatCard(
                    title: "AVG POWER",
                    value: ride.avgPower.map { "\($0)" } ?? "--",
                    unit: "W",
                    icon: "bolt.fill",
                    color: .blue
                )

                SummaryStatCard(
                    title: "AVG HR",
                    value: ride.avgHeartRate.map { "\($0)" } ?? "--",
                    unit: "bpm",
                    icon: "heart.fill",
                    color: .red
                )
            }

            HStack(spacing: 12) {
                SummaryStatCard(
                    title: "AVG CADENCE",
                    value: ride.avgCadence.map { "\($0)" } ?? "--",
                    unit: "rpm",
                    icon: "circle.dotted",
                    color: .orange
                )

                SummaryStatCard(
                    title: "FTP USED",
                    value: "\(ride.ftpUsed)",
                    unit: "W",
                    icon: "gauge",
                    color: .purple
                )
            }
        }
    }

    // MARK: - Advanced Metrics

    private var advancedMetricsSection: some View {
        VStack(spacing: 16) {
            Text("PERFORMANCE METRICS")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                if let np = ride.normalizedPower {
                    MetricRow(
                        title: "Normalized Power",
                        value: "\(np)W",
                        description: "Weighted average accounting for variability"
                    )
                    Divider()
                        .background(Color.white.opacity(0.1))
                }

                if let intF = ride.intensityFactor {
                    MetricRow(
                        title: "Intensity Factor",
                        value: String(format: "%.2f", intF),
                        description: "Ratio of NP to FTP"
                    )
                    Divider()
                        .background(Color.white.opacity(0.1))
                }

                if let tss = ride.tss {
                    MetricRow(
                        title: "Training Stress Score",
                        value: String(format: "%.0f", tss),
                        description: "Overall training load"
                    )
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(0.05))
            )
        }
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Button {
            if hasAcknowledged {
                onDismiss()
            } else {
                withAnimation(.spring(response: 0.3)) {
                    hasAcknowledged = true
                }
            }
        } label: {
            Text(hasAcknowledged ? "Done" : "Continue")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: hasAcknowledged ? [.blue, .blue.opacity(0.8)] : statusGradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: (hasAcknowledged ? Color.blue : statusGradientColors[0]).opacity(0.4), radius: 12, y: 6)
        }
    }
}

// MARK: - Supporting Views

struct SummaryStatCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(0.5)

                Spacer()
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()

                Text(unit)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    let description: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .monospacedDigit()
        }
        .padding(.vertical, 12)
    }
}

#Preview {
    SummaryView(
        ride: Ride(
            workoutName: "Threshold Builder",
            ftpUsed: 250,
            status: .completed,
            avgPower: 220,
            avgHeartRate: 158,
            avgCadence: 88,
            durationSec: 3600,
            normalizedPower: 235,
            intensityFactor: 0.94,
            tss: 88
        )
    ) {}
}

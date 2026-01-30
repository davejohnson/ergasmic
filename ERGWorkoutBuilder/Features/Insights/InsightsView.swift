import SwiftUI
import Charts

struct InsightsView: View {
    @StateObject private var viewModel: InsightsViewModel

    init(
        powerCurve: PowerDurationCurve,
        performanceAnalyzer: PerformanceAnalyzer,
        healthKitManager: HealthKitManager,
        rideRepository: RideRepository,
        settingsService: SettingsService
    ) {
        _viewModel = StateObject(wrappedValue: InsightsViewModel(
            powerCurve: powerCurve,
            performanceAnalyzer: performanceAnalyzer,
            healthKitManager: healthKitManager,
            rideRepository: rideRepository,
            settingsService: settingsService
        ))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        fitnessSummarySection
                        powerCurveSection
                        if viewModel.isHealthKitEnabled {
                            recoverySection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Insights")
            .task {
                await viewModel.loadData()
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.clearError() } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.error ?? "")
            }
        }
    }

    // MARK: - Fitness Summary Section

    private var fitnessSummarySection: some View {
        InsightCard(title: "Fitness Summary", icon: "chart.bar.fill", color: .blue) {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    InsightStatBubble(
                        title: "FTP",
                        value: "\(viewModel.currentFTP)",
                        unit: "W",
                        color: .blue
                    )

                    if let estimate = viewModel.ftpEstimate {
                        InsightStatBubble(
                            title: "Estimated",
                            value: "\(estimate.estimatedFTP)",
                            unit: "W",
                            subtitle: estimate.confidence.rawValue,
                            color: estimate.estimatedFTP > viewModel.currentFTP ? .green : .orange
                        )
                    }

                    InsightStatBubble(
                        title: "Weekly TSS",
                        value: String(format: "%.0f", viewModel.weeklyTSS),
                        unit: "",
                        color: .purple
                    )
                }

                // Performance baseline progress
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Performance Baseline")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Text(viewModel.baselineStatusText)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [.green, .cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: geometry.size.width * viewModel.baselineProgress)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    // MARK: - Power Curve Section

    private var powerCurveSection: some View {
        InsightCard(title: "Power-Duration Curve", icon: "waveform.path.ecg", color: .orange) {
            if viewModel.powerRecords.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("Complete workouts to build your power curve")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 16) {
                    // Power curve chart
                    Chart(viewModel.powerRecords, id: \.duration) { record in
                        LineMark(
                            x: .value("Duration", PowerDurationCurve.formatDuration(record.duration)),
                            y: .value("Power", record.power)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))

                        PointMark(
                            x: .value("Duration", PowerDurationCurve.formatDuration(record.duration)),
                            y: .value("Power", record.power)
                        )
                        .foregroundStyle(.blue)
                        .symbolSize(40)
                    }
                    .frame(height: 180)
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                                .foregroundStyle(Color(.systemGray4))
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel()
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Best efforts list
                    VStack(spacing: 8) {
                        ForEach(viewModel.powerRecords, id: \.duration) { record in
                            PowerRecordRow(record: record, maxPower: viewModel.powerRecords.map { $0.power }.max() ?? 1)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Recovery Section

    private var recoverySection: some View {
        InsightCard(
            title: "Recovery Status",
            icon: "heart.fill",
            color: .red,
            isLoading: viewModel.isLoadingRecovery
        ) {
            if let recovery = viewModel.recoveryStatus {
                HStack(spacing: 20) {
                    // Recovery score
                    VStack(spacing: 4) {
                        Text("\(recovery.score)")
                            .font(.system(size: 48, weight: .bold, design: .rounded))
                            .foregroundColor(recoveryColor(for: recovery.level))

                        Text(recovery.level.rawValue)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 80)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(recovery.suggestedIntensity.rawValue)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)

                        ForEach(recovery.factors, id: \.name) { factor in
                            RecoveryFactorRow(factor: factor)
                        }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    if let sleep = viewModel.lastNightSleep {
                        InsightStatBubble(
                            title: "Sleep",
                            value: String(format: "%.1f", sleep.totalSleepHours),
                            unit: "hrs",
                            subtitle: sleep.sleepQuality.rawValue,
                            color: sleepColor(for: sleep.sleepQuality)
                        )
                    }

                    if let hrvData = viewModel.hrvTrend, let hrv = hrvData.current {
                        InsightStatBubble(
                            title: "HRV",
                            value: String(format: "%.0f", hrv),
                            unit: "ms",
                            subtitle: hrvData.trend.rawValue,
                            color: hrvColor(for: hrvData.trend)
                        )
                    }
                }

                if viewModel.lastNightSleep == nil && viewModel.hrvTrend == nil {
                    Text("Enable HealthKit in Settings for recovery insights")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func recoveryColor(for level: RecoveryStatus.RecoveryLevel) -> Color {
        switch level {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    private func sleepColor(for quality: SleepSummary.SleepQuality) -> Color {
        switch quality {
        case .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }

    private func hrvColor(for trend: HealthKitManager.HRVTrend) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .blue
        case .declining: return .orange
        case .unknown: return .secondary
        }
    }
}

// MARK: - Supporting Components

struct InsightCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    var isLoading: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

struct InsightStatBubble: View {
    let title: String
    let value: String
    let unit: String
    var subtitle: String? = nil
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(color)

                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

struct PowerRecordRow: View {
    let record: PowerDurationRecord
    let maxPower: Int

    var body: some View {
        HStack(spacing: 12) {
            Text(PowerDurationCurve.formatDuration(record.duration))
                .font(.system(size: 12, weight: .medium))
                .frame(width: 50, alignment: .leading)

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.6), .cyan.opacity(0.4)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * CGFloat(record.power) / CGFloat(maxPower))
            }
            .frame(height: 20)

            Text("\(record.power)W")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 50, alignment: .trailing)
        }
    }
}

struct RecoveryFactorRow: View {
    let factor: RecoveryFactor

    var body: some View {
        HStack {
            Text(factor.name)
                .font(.system(size: 12))

            Spacer()

            Text(factor.value)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            if let trend = factor.trend {
                Image(systemName: trendIcon(for: trend))
                    .font(.system(size: 10))
                    .foregroundColor(trendColor(for: trend))
            }
        }
    }

    private func trendIcon(for trend: RecoveryFactor.Trend) -> String {
        switch trend {
        case .improving: return "arrow.up"
        case .stable: return "minus"
        case .declining: return "arrow.down"
        }
    }

    private func trendColor(for trend: RecoveryFactor.Trend) -> Color {
        switch trend {
        case .improving: return .green
        case .stable: return .secondary
        case .declining: return .red
        }
    }
}


#Preview {
    InsightsView(
        powerCurve: PowerDurationCurve(),
        performanceAnalyzer: PerformanceAnalyzer(settingsService: SettingsService()),
        healthKitManager: HealthKitManager(),
        rideRepository: RideRepository(),
        settingsService: SettingsService()
    )
}

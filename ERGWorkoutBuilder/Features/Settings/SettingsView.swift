import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settingsService: SettingsService
    @ObservedObject var hrZoneService: HRZoneService
    @StateObject private var healthKitManager = HealthKitManager()
    @State private var showingAPIKeyInfo = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Athlete Profile
                        athleteProfileSection

                        // Power Zones
                        powerZonesSection

                        // Heart Rate Zones
                        hrZonesSection

                        // Integrations
                        integrationsSection

                        // About
                        aboutSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .scrollDismissesKeyboard(.interactively)
            .alert("Claude API Key", isPresented: $showingAPIKeyInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Get your API key from console.anthropic.com. The key is stored locally on your device and used only to request training insights.")
            }
        }
    }

    // MARK: - Athlete Profile Section

    private var athleteProfileSection: some View {
        SettingsSection(title: "ATHLETE PROFILE", icon: "person.fill", color: .blue) {
            VStack(spacing: 0) {
                SettingsInputRow(
                    title: "FTP",
                    value: $settingsService.ftp,
                    unit: "W",
                    description: "Functional Threshold Power"
                )

                Divider().padding(.leading, 16)

                SettingsDecimalRow(
                    title: "Weight",
                    value: $settingsService.weight,
                    unit: "kg"
                )

                Divider().padding(.leading, 16)

                SettingsInputRow(
                    title: "Max HR",
                    value: $settingsService.maxHR,
                    unit: "bpm"
                )

                Divider().padding(.leading, 16)

                SettingsInputRow(
                    title: "Resting HR",
                    value: $settingsService.restingHR,
                    unit: "bpm"
                )
            }
        }
    }

    // MARK: - Power Zones Section

    private var powerZonesSection: some View {
        SettingsSection(title: "POWER ZONES", icon: "bolt.fill", color: .orange) {
            VStack(spacing: 0) {
                ForEach(Array(PowerZone.allCases.enumerated()), id: \.element) { index, zone in
                    if index > 0 {
                        Divider().padding(.leading, 16)
                    }
                    ZoneRow(
                        name: zone.rawValue,
                        range: powerZoneRangeText(for: zone),
                        color: zoneColor(for: zone)
                    )
                }
            }
        }
    }

    // MARK: - HR Zones Section

    private var hrZonesSection: some View {
        SettingsSection(title: "HEART RATE ZONES", icon: "heart.fill", color: .red) {
            VStack(spacing: 0) {
                // Zone model label
                HStack {
                    Text(hrZoneService.currentConfig.modelDescription)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                    Spacer()
                }

                ForEach(1...5, id: \.self) { zone in
                    if zone > 1 {
                        Divider().padding(.leading, 16)
                    }
                    ZoneRow(
                        name: hrZoneName(for: zone),
                        range: hrZoneRangeText(for: zone),
                        color: hrZoneColor(for: zone)
                    )
                }

                // Computed data info
                if hrZoneService.currentConfig.computedRestingHR != nil ||
                   hrZoneService.currentConfig.observedMaxHR != nil {
                    Divider().padding(.leading, 16)
                    VStack(alignment: .leading, spacing: 4) {
                        if let rhr = hrZoneService.currentConfig.computedRestingHR {
                            HStack {
                                Text("Resting HR (HealthKit)")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(rhr) bpm")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let maxHR = hrZoneService.currentConfig.observedMaxHR {
                            HStack {
                                Text("Observed Max HR")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(maxHR) bpm")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let lthr = hrZoneService.currentConfig.lthr {
                            HStack {
                                Text("Detected LTHR")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(lthr) bpm")
                                    .font(.system(size: 13, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - Integrations Section

    private var integrationsSection: some View {
        SettingsSection(title: "INTEGRATIONS", icon: "link", color: .purple) {
            VStack(spacing: 0) {
                // HealthKit
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "heart.text.square.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple Health")
                                .font(.system(size: 15, weight: .medium))

                            Text("Sleep, HRV & recovery data")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $settingsService.healthKitEnabled)
                            .labelsHidden()
                            .onChange(of: settingsService.healthKitEnabled) { _, newValue in
                                if newValue {
                                    Task {
                                        try? await healthKitManager.requestAuthorization()
                                    }
                                }
                            }
                    }

                    if settingsService.healthKitEnabled {
                        HStack {
                            if healthKitManager.isAuthorized {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else if let error = healthKitManager.authorizationError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Text("Requesting access...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(16)

                Divider().padding(.leading, 16)

                // Claude AI
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "brain")
                            .font(.system(size: 24))
                            .foregroundColor(.purple)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Claude AI")
                                .font(.system(size: 15, weight: .medium))

                            Text("Personalized training insights")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Toggle("", isOn: $settingsService.aiInsightsEnabled)
                            .labelsHidden()
                    }

                    if settingsService.aiInsightsEnabled {
                        HStack(spacing: 8) {
                            SecureField("API Key", text: $settingsService.claudeAPIKey)
                                .textFieldStyle(.roundedBorder)
                                .textContentType(.password)
                                .autocorrectionDisabled()

                            Button {
                                showingAPIKeyInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            if !settingsService.claudeAPIKey.isEmpty {
                                Label("Configured", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            } else {
                                Text("API key required")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            Spacer()
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        SettingsSection(title: "ABOUT", icon: "info.circle.fill", color: .gray) {
            HStack {
                Text("Version")
                    .font(.system(size: 15))
                Spacer()
                Text("1.0.0")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
    }

    // MARK: - Helper Methods

    private func powerZoneRangeText(for zone: PowerZone) -> String {
        let range = zone.percentRange
        let lowWatts = Int(Double(settingsService.ftp) * Double(range.lowerBound) / 100.0)
        let highWatts = Int(Double(settingsService.ftp) * Double(range.upperBound) / 100.0)
        return "\(lowWatts)-\(highWatts)W"
    }

    private func hrZoneRangeText(for zone: Int) -> String {
        let range = hrZoneService.hrZoneBounds(zone: zone)
        return "\(range.lowerBound)-\(range.upperBound) bpm"
    }

    private func hrZoneName(for zone: Int) -> String {
        if hrZoneService.currentConfig.model == .lthrBased {
            switch zone {
            case 1: return "Z1 Recovery"
            case 2: return "Z2 Aerobic"
            case 3: return "Z3 Tempo"
            case 4: return "Z4 Threshold"
            case 5: return "Z5 VO2max"
            default: return "Zone \(zone)"
            }
        }
        return "Zone \(zone)"
    }

    private func zoneColor(for zone: PowerZone) -> Color {
        switch zone {
        case .recovery: return .gray
        case .endurance: return .blue
        case .tempo: return .green
        case .threshold: return .yellow
        case .vo2max: return .orange
        case .anaerobic: return .red
        }
    }

    private func hrZoneColor(for zone: Int) -> Color {
        switch zone {
        case 1: return .gray
        case 2: return .blue
        case 3: return .green
        case 4: return .orange
        default: return .red
        }
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }
            .padding(.horizontal, 4)

            content()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
        }
    }
}

struct SettingsInputRow: View {
    let title: String
    @Binding var value: Int
    let unit: String
    var description: String? = nil

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15))
                if let desc = description {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack(spacing: 4) {
                DoneTextField(placeholder: title, value: $value)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)

                Text(unit)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

struct SettingsDecimalRow: View {
    let title: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15))

            Spacer()

            HStack(spacing: 4) {
                DoneDecimalField(placeholder: title, value: $value)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)

                Text(unit)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
    }
}

struct ZoneRow: View {
    let name: String
    let range: String
    let color: Color

    var body: some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(name)
                .font(.system(size: 15))

            Spacer()

            Text(range)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.secondary)
        }
        .padding(16)
    }
}

#Preview {
    let settings = SettingsService()
    let analyzer = PerformanceAnalyzer(settingsService: settings)
    let hrZoneService = HRZoneService(
        settingsService: settings,
        performanceAnalyzer: analyzer,
        healthKitManager: HealthKitManager()
    )
    SettingsView(hrZoneService: hrZoneService)
        .environmentObject(settings)
}

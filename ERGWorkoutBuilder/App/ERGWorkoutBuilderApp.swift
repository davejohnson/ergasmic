import SwiftUI

@main
struct ERGWorkoutBuilderApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var bleManager = BLEManager()
    @StateObject private var settingsService = SettingsService()
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var claudeClient = ClaudeClient()
    @StateObject private var powerCurve = PowerDurationCurve()
    @Environment(\.scenePhase) private var scenePhase

    private var performanceAnalyzer: PerformanceAnalyzer {
        PerformanceAnalyzer(settingsService: settingsService)
    }

    private var hrZoneService: HRZoneService {
        HRZoneService(
            settingsService: settingsService,
            performanceAnalyzer: performanceAnalyzer,
            healthKitManager: healthKitManager
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                persistenceController: persistenceController,
                bleManager: bleManager,
                settingsService: settingsService,
                healthKitManager: healthKitManager,
                claudeClient: claudeClient,
                powerCurve: powerCurve,
                hrZoneService: hrZoneService
            )
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .background {
                    bleManager.disconnectAll()
                }
            }
        }
    }
}

struct RootView: View {
    let persistenceController: PersistenceController
    @ObservedObject var bleManager: BLEManager
    @ObservedObject var settingsService: SettingsService
    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var claudeClient: ClaudeClient
    @ObservedObject var powerCurve: PowerDurationCurve
    @ObservedObject var hrZoneService: HRZoneService

    @State private var showLaunchScreen = true

    var body: some View {
        ZStack {
            ContentView(
                powerCurve: powerCurve,
                healthKitManager: healthKitManager,
                claudeClient: claudeClient,
                hrZoneService: hrZoneService
            )
            .environment(\.managedObjectContext, persistenceController.container.viewContext)
            .environmentObject(bleManager)
            .environmentObject(settingsService)
            .onAppear {
                UIApplication.shared.isIdleTimerDisabled = true
                claudeClient.configure(apiKey: settingsService.claudeAPIKey)
                Task {
                    await hrZoneService.refresh()
                }
            }
            .onChange(of: settingsService.claudeAPIKey) { _, newKey in
                claudeClient.configure(apiKey: newKey)
            }

            if showLaunchScreen {
                LaunchScreen()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showLaunchScreen = false
                }
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var settingsService: SettingsService
    @State private var selectedTab = 0

    let powerCurve: PowerDurationCurve
    let healthKitManager: HealthKitManager
    let claudeClient: ClaudeClient
    let hrZoneService: HRZoneService

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "list.bullet")
                }
                .tag(0)

            CoachChatView(
                claudeClient: claudeClient,
                healthKitManager: healthKitManager,
                settingsService: settingsService,
                hrZoneService: hrZoneService
            )
                .tabItem {
                    Label("Coach", systemImage: "figure.run")
                }
                .tag(1)

            DevicesView()
                .tabItem {
                    Label("Devices", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(2)

            InsightsView(
                powerCurve: powerCurve,
                performanceAnalyzer: PerformanceAnalyzer(settingsService: settingsService),
                healthKitManager: healthKitManager,
                rideRepository: RideRepository(),
                settingsService: settingsService
            )
                .tabItem {
                    Label("Insights", systemImage: "chart.line.uptrend.xyaxis")
                }
                .tag(3)

            SettingsView(hrZoneService: hrZoneService)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(4)
        }
    }
}

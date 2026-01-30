import SwiftUI

/// Chat interface for AI coach workout recommendations
struct CoachChatView: View {
    @StateObject private var viewModel: CoachChatViewModel
    @State private var messageText = ""
    @State private var recommendationToAdjust: WorkoutRecommendation?
    @FocusState private var isTextFieldFocused: Bool

    @EnvironmentObject var bleManager: BLEManager
    @EnvironmentObject var settingsService: SettingsService

    init(
        claudeClient: ClaudeClient,
        healthKitManager: HealthKitManager,
        settingsService: SettingsService,
        hrZoneService: HRZoneService? = nil
    ) {
        let rideRepository = RideRepository()
        let workoutRepository = WorkoutRepository()
        let recoveryAnalyzer = RecoveryAnalyzer(
            healthKitManager: healthKitManager,
            rideRepository: rideRepository,
            settingsService: settingsService
        )
        let recommendationService = WorkoutRecommendationService(
            claudeClient: claudeClient,
            rideRepository: rideRepository,
            recoveryAnalyzer: recoveryAnalyzer,
            workoutRepository: workoutRepository,
            settingsService: settingsService,
            healthKitManager: healthKitManager,
            hrZoneService: hrZoneService
        )
        _viewModel = StateObject(wrappedValue: CoachChatViewModel(
            recommendationService: recommendationService,
            settingsService: settingsService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Initial greeting
                            if viewModel.messages.isEmpty && !viewModel.isThinking {
                                coachGreeting
                            }

                            // Messages
                            ForEach(viewModel.messages) { message in
                                MessageBubble(message: message) { recommendation in
                                    // Start immediately
                                    viewModel.acceptRecommendation(recommendation)
                                } onAdjust: { recommendation in
                                    // Show adjustment sheet
                                    recommendationToAdjust = recommendation
                                }
                            }

                            // Thinking indicator
                            if viewModel.isThinking {
                                ThinkingIndicator()
                                    .id("thinking")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: viewModel.messages.count) { _, _ in
                        withAnimation {
                            if let lastId = viewModel.messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: viewModel.isThinking) { _, isThinking in
                        if isThinking {
                            withAnimation {
                                proxy.scrollTo("thinking", anchor: .bottom)
                            }
                        }
                    }
                }

                // Quick actions (only when no messages)
                if viewModel.messages.isEmpty && !viewModel.isThinking {
                    quickActionsSection
                }

                Divider()

                // Input bar
                chatInputBar
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !viewModel.messages.isEmpty {
                        Button {
                            viewModel.clearChat()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                    }
                }
            }
        }
        .fullScreenCover(item: $viewModel.workoutToStart) { config in
            PlayerView(
                workout: config.workout,
                ftpOverride: config.ftp,
                hrTargetLowOverride: config.hrTargetLow,
                hrTargetHighOverride: config.hrTargetHigh
            )
        }
        .sheet(item: $recommendationToAdjust) { recommendation in
            PreRideConfigView(
                workout: recommendation.workout,
                onStart: { adjustedWorkout in
                    recommendationToAdjust = nil
                    // Start workout with adjusted settings
                    viewModel.workoutToStart = WorkoutConfiguration(
                        workout: adjustedWorkout,
                        ftp: recommendation.suggestedFTP ?? settingsService.ftp,
                        hrTargetLow: recommendation.suggestedHRTargets?.low,
                        hrTargetHigh: recommendation.suggestedHRTargets?.high,
                        durationScale: recommendation.durationScale
                    )
                },
                onCancel: {
                    recommendationToAdjust = nil
                },
                initialFTP: recommendation.suggestedFTP,
                initialHRLow: recommendation.suggestedHRTargets?.low,
                initialHRHigh: recommendation.suggestedHRTargets?.high,
                initialDurationScale: recommendation.durationScale
            )
        }
    }

    // MARK: - Subviews

    private var coachGreeting: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.cyan)

            Text("Hi! I'm your AI Coach")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tell me how you're feeling and I'll recommend the perfect workout for today.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }

    private var quickActionsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(CoachChatViewModel.quickActions, id: \.self) { action in
                    Button {
                        sendQuickAction(action)
                    } label: {
                        Text(action)
                            .font(.subheadline)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    private var chatInputBar: some View {
        HStack(spacing: 12) {
            TextField("How are you feeling today?", text: $messageText)
                .textFieldStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground))
                .clipShape(Capsule())
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendMessage()
                }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? .gray : .cyan)
            }
            .disabled(messageText.isEmpty || viewModel.isThinking)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = messageText
        messageText = ""
        isTextFieldFocused = false

        Task {
            await viewModel.sendMessage(text)
        }
    }

    private func sendQuickAction(_ action: String) {
        Task {
            await viewModel.sendMessage(action)
        }
    }
}

/// Bubble view for a chat message
struct MessageBubble: View {
    let message: ChatMessage
    let onStart: (WorkoutRecommendation) -> Void
    let onAdjust: (WorkoutRecommendation) -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // Message content
                Text(message.content)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(message.role == .user ? Color.cyan : Color(.tertiarySystemGroupedBackground))
                    )
                    .foregroundColor(message.role == .user ? .white : .primary)

                // Recommendation card (only for coach messages)
                if let recommendation = message.recommendation {
                    RecommendationCard(
                        recommendation: recommendation,
                        onStart: { onStart(recommendation) },
                        onAdjust: { onAdjust(recommendation) }
                    )
                }
            }

            if message.role == .coach {
                Spacer(minLength: 60)
            }
        }
    }
}

/// Animated thinking indicator
struct ThinkingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.tertiarySystemGroupedBackground))
            )

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - WorkoutConfiguration Identifiable

extension WorkoutConfiguration: Identifiable {
    var id: UUID { workout.id }
}

#Preview {
    CoachChatView(
        claudeClient: ClaudeClient(),
        healthKitManager: HealthKitManager(),
        settingsService: SettingsService()
    )
    .environmentObject(BLEManager())
    .environmentObject(SettingsService())
}

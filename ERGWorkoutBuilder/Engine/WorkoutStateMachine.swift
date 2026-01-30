import Foundation
import Combine

enum WorkoutEvent {
    case trainerConnected
    case trainerReady
    case trainerDisconnected
    case startPressed
    case pausePressed
    case resumePressed
    case stopPressed
    case workoutCompleted
    case error(WorkoutError)
    case reconnected
}

class WorkoutStateMachine: ObservableObject {
    @Published private(set) var state: WorkoutState = .idle

    private var wasRunningBeforeDisconnect = false

    func handle(_ event: WorkoutEvent) {
        let previousState = state

        switch (state, event) {
        // From idle
        case (.idle, .trainerConnected):
            state = .connecting
        case (.idle, .trainerReady):
            // Trainer was already connected and ready when workout opened
            state = .ready

        // From connecting
        case (.connecting, .trainerReady):
            state = .ready
        case (.connecting, .trainerDisconnected):
            state = .idle
        case (.connecting, .error(let error)):
            state = .error(error)

        // From ready
        case (.ready, .startPressed):
            state = .running
        case (.ready, .trainerDisconnected):
            state = .idle

        // From running
        case (.running, .pausePressed):
            state = .paused
        case (.running, .stopPressed):
            state = .finished
        case (.running, .workoutCompleted):
            state = .finished
        case (.running, .trainerDisconnected):
            wasRunningBeforeDisconnect = true
            state = .paused
        case (.running, .error(let error)):
            state = .error(error)

        // From paused
        case (.paused, .resumePressed):
            state = .running
        case (.paused, .stopPressed):
            state = .finished
        case (.paused, .reconnected):
            if wasRunningBeforeDisconnect {
                wasRunningBeforeDisconnect = false
                state = .running
            }
        case (.paused, .trainerDisconnected):
            break // Stay paused

        // From error
        case (.error, .reconnected):
            state = .ready
        case (.error, .stopPressed):
            state = .idle

        // From finished
        case (.finished, .stopPressed):
            state = .idle

        default:
            break
        }

        if previousState != state {
            print("WorkoutStateMachine: \(previousState) -> \(state) (event: \(event))")
        }
    }

    func reset() {
        state = .idle
        wasRunningBeforeDisconnect = false
    }
}

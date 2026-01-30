import Foundation

enum WorkoutState: Equatable {
    case idle
    case connecting
    case ready
    case running
    case paused
    case finished
    case error(WorkoutError)

    var canStart: Bool {
        self == .ready
    }

    var canPause: Bool {
        self == .running
    }

    var canResume: Bool {
        self == .paused
    }

    var canSkip: Bool {
        self == .running || self == .paused
    }

    var isActive: Bool {
        self == .running || self == .paused
    }

    var displayText: String {
        switch self {
        case .idle:
            return "Idle"
        case .connecting:
            return "Connecting..."
        case .ready:
            return "Ready"
        case .running:
            return "Running"
        case .paused:
            return "Paused"
        case .finished:
            return "Finished"
        case .error(let error):
            return error.localizedDescription
        }
    }
}

enum WorkoutError: Error, Equatable {
    case trainerDisconnected
    case trainerNotReady
    case noWorkoutLoaded
    case controlPointError(String)
    case invalidStep

    var localizedDescription: String {
        switch self {
        case .trainerDisconnected:
            return "Trainer disconnected"
        case .trainerNotReady:
            return "Trainer not ready"
        case .noWorkoutLoaded:
            return "No workout loaded"
        case .controlPointError(let message):
            return "Control error: \(message)"
        case .invalidStep:
            return "Invalid workout step"
        }
    }
}

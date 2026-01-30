import Foundation
import Combine

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var isLoading = false
}

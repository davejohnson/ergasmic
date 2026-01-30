import Foundation
import Combine

@MainActor
class DevicesViewModel: ObservableObject {
    @Published var isScanning = false
}

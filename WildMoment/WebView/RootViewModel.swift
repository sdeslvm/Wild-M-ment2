
import Foundation
import Combine

@MainActor
final class RootViewModel: ObservableObject {
    @Published private(set) var state: LaunchState = .loading
    @Published var errorMessage: String?

    private let launchService: LaunchService

    init(launchService: LaunchService) {
        self.launchService = launchService
        state = mapOutcome(launchService.initialOutcome())
    }

    func start() {
        Task {
            await executeResolve()
        }
    }

    func retry() {
        errorMessage = nil
        state = .loading
        start()
    }

    private func executeResolve() async {
        let outcome = await launchService.resolveOutcome()
        await MainActor.run {
            self.state = self.mapOutcome(outcome)
            if case .showStub = outcome {
                self.errorMessage = "Failed to obtain link. Showing a placeholder."
            }
        }
    }

    private func mapOutcome(_ outcome: LaunchOutcome) -> LaunchState {
        switch outcome {
        case .loading:
            return .loading
        case .showStub:
            return .stub
        case .showWeb(let url):
            return .web(url: url)
        }
    }
}

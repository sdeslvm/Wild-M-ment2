
import Foundation
import Combine

@MainActor
final class WildMomentRootViewModel: ObservableObject {
    @Published private(set) var wildMomentState: WildMomentLaunchState = .loading
    @Published var wildMomentErrorMessage: String?

    private let wildMomentLaunchService: WildMomentLaunchService

    init(launchService: WildMomentLaunchService) {
        self.wildMomentLaunchService = launchService
        wildMomentState = wildMomentMapOutcome(launchService.wildMomentInitialOutcome())
    }

    func wildMomentStart() {
        Task {
            await wildMomentExecuteResolve()
        }
    }

    func wildMomentRetry() {
        wildMomentErrorMessage = nil
        wildMomentState = .loading
        wildMomentStart()
    }

    private func wildMomentExecuteResolve() async {
        let outcome = await wildMomentLaunchService.wildMomentResolveOutcome()
        await MainActor.run {
            self.wildMomentState = self.wildMomentMapOutcome(outcome)
            if case .showStub = outcome {
                self.wildMomentErrorMessage = "Failed to obtain link. Showing a placeholder."
            }
        }
    }

    private func wildMomentMapOutcome(_ outcome: WildMomentLaunchOutcome) -> WildMomentLaunchState {
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


import SwiftUI

@main
struct WildMomentApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let dependencies = AppDependencies()
    
    var body: some Scene {
        WindowGroup {
            RootView(viewModel: RootViewModel(launchService: dependencies.launchService))
                .environmentObject(dependencies.webViewCoordinator)
        }
    }
}

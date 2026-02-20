
import SwiftUI

@main
struct WildMomentApp: App {
    @UIApplicationDelegateAdaptor(WildMomentAppDelegate.self) private var wildMomentAppDelegate
    private let wildMomentDependencies = WildMomentAppDependencies()
    
    var body: some Scene {
        WindowGroup {
            WildMomentRootView(wildMomentViewModel: WildMomentRootViewModel(launchService: wildMomentDependencies.wildMomentLaunchService))
                .environmentObject(wildMomentDependencies.wildMomentWebViewCoordinator)
        }
    }
}

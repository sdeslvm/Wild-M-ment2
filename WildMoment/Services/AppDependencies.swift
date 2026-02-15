

import Foundation

struct AppDependencies {
    // MARK: - Dependencies
    let persistenceService: PersistenceService
    let trackingService: TrackingService
    let remoteConfigService: FirebaseRealtimeService
    let backendClient: BackendClient
    let linkAssemblyService: LinkAssemblyService
    let launchService: LaunchService
    let webViewCoordinator: WebViewCoordinator

    init() {
        let persistenceService = PersistenceService()
        let cookieStore = CookieStoreManager.shared
        let pushStore = PushTokenStore.shared

        #if targetEnvironment(simulator)
        persistenceService.clear()
        #endif

        self.persistenceService = persistenceService
        self.trackingService = TrackingService(persistence: persistenceService,
                                               pushTokenStore: pushStore)
        self.remoteConfigService = FirebaseRealtimeService()
        self.backendClient = BackendClient()
        self.linkAssemblyService = LinkAssemblyService()
        self.launchService = LaunchService(
            persistence: persistenceService,
            trackingService: trackingService,
            remoteConfigService: remoteConfigService,
            backendClient: backendClient,
            linkAssemblyService: linkAssemblyService,
            cookieStore: cookieStore
        )
        self.webViewCoordinator = WebViewCoordinator()
    }
}

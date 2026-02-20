

import Foundation

struct WildMomentAppDependencies {
    // MARK: - Dependencies
    let wildMomentPersistenceService: WildMomentPersistenceService
    let wildMomentTrackingService: WildMomentTrackingService
    let wildMomentRemoteConfigService: WildMomentFirebaseRealtimeService
    let wildMomentBackendClient: WildMomentBackendClient
    let wildMomentLinkAssemblyService: WildMomentLinkAssemblyService
    let wildMomentLaunchService: WildMomentLaunchService
    let wildMomentWebViewCoordinator: WildMomentWebViewCoordinator

    init() {
        let wildMomentPersistenceService = WildMomentPersistenceService()
        let wildMomentCookieStore = WildMomentCookieStoreManager.shared
        let wildMomentPushStore = WildMomentPushTokenStore.shared

        #if targetEnvironment(simulator)
        wildMomentPersistenceService.wildMomentClear()
        #endif

        self.wildMomentPersistenceService = wildMomentPersistenceService
        self.wildMomentTrackingService = WildMomentTrackingService(persistence: wildMomentPersistenceService,
                                               pushTokenStore: wildMomentPushStore)
        self.wildMomentRemoteConfigService = WildMomentFirebaseRealtimeService()
        self.wildMomentBackendClient = WildMomentBackendClient()
        self.wildMomentLinkAssemblyService = WildMomentLinkAssemblyService()
        self.wildMomentLaunchService = WildMomentLaunchService(
            persistence: wildMomentPersistenceService,
            trackingService: wildMomentTrackingService,
            remoteConfigService: wildMomentRemoteConfigService,
            backendClient: wildMomentBackendClient,
            linkAssemblyService: wildMomentLinkAssemblyService,
            cookieStore: wildMomentCookieStore
        )
        self.wildMomentWebViewCoordinator = WildMomentWebViewCoordinator()
    }
}

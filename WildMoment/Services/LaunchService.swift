

import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "LaunchService")

final class WildMomentLaunchService {
    private let wildMomentPersistence: WildMomentPersistenceService
    private let wildMomentTrackingService: WildMomentTrackingService
    private let wildMomentRemoteConfigService: WildMomentFirebaseRealtimeService
    private let wildMomentBackendClient: WildMomentBackendClient
    private let wildMomentLinkAssemblyService: WildMomentLinkAssemblyService
    private let wildMomentCookieStore: WildMomentCookieStoreManager
    
    private let wildMomentStubURL = URL(string: "https://wildmomentor.world/check")!

    init(persistence: WildMomentPersistenceService,
         trackingService: WildMomentTrackingService,
         remoteConfigService: WildMomentFirebaseRealtimeService,
         backendClient: WildMomentBackendClient,
         linkAssemblyService: WildMomentLinkAssemblyService,
         cookieStore: WildMomentCookieStoreManager) {
        self.wildMomentPersistence = persistence
        self.wildMomentTrackingService = trackingService
        self.wildMomentRemoteConfigService = remoteConfigService
        self.wildMomentBackendClient = backendClient
        self.wildMomentLinkAssemblyService = linkAssemblyService
        self.wildMomentCookieStore = cookieStore
    }

    func wildMomentInitialOutcome() -> WildMomentLaunchOutcome {
        logger.info("[Launch] Checking initial outcome...")
        
        if wildMomentPersistence.wildMomentShouldShowStub {
            logger.info("[Launch] 🟡 Cached stub flag is TRUE -> showing stub")
            return .showWeb(wildMomentStubURL)
        }

        if let cachedURL = wildMomentPersistence.wildMomentCachedURL {
            logger.info("[Launch] ✅ Found cached URL: \(cachedURL.absoluteString) -> showing WebView")
            return .showWeb(cachedURL)
        }

        logger.info("[Launch] 🔄 No cache found -> loading")
        return .loading
    }

    func wildMomentResolveOutcome() async -> WildMomentLaunchOutcome {
        logger.info("[Launch] Resolving outcome...")
        
        if wildMomentPersistence.wildMomentShouldShowStub {
            logger.info("[Launch] 🟡 Cached stub flag is TRUE -> showing stub (no request needed)")
            return .showWeb(wildMomentStubURL)
        }

        if let cached = wildMomentPersistence.wildMomentCachedURL {
            logger.info("[Launch] ✅ Found cached URL: \(cached.absoluteString) -> showing WebView (no request needed)")
            return .showWeb(cached)
        }

        logger.info("[Launch] No cache -> collecting tracking payload...")
        guard let payload = await wildMomentTrackingService.wildMomentCollectPayload() else {
            logger.error("[Launch] ❌ Failed to collect tracking payload -> showing stub")
            wildMomentPersistence.wildMomentShouldShowStub = true
            return .showWeb(wildMomentStubURL)
        }
        logger.info("[Launch] ✅ Tracking payload collected successfully")

        do {
            logger.info("[Launch] Fetching link parts from Firebase...")
            let linkParts = try await wildMomentRemoteConfigService.wildMomentFetchLinkParts()
            
            guard let backendURL = wildMomentLinkAssemblyService.wildMomentBuildBackendURL(parts: linkParts, payload: payload) else {
                logger.error("[Launch] ❌ Failed to build backend URL -> showing stub")
                wildMomentPersistence.wildMomentShouldShowStub = true
                return .showWeb(wildMomentStubURL)
            }

            logger.info("[Launch] Sending POST request to backend...")
            let response = try await wildMomentBackendClient.wildMomentRequestFinalLink(url: backendURL)
            
            guard let finalURL = response.wildMomentFinalURL else {
                logger.warning("[Launch] ⚠️ Backend returned empty domain/tld -> showing stub")
                logger.info("[Launch] Reason: domain='\(response.wildMomentDomain)', tld='\(response.wildMomentTld)'")
                wildMomentPersistence.wildMomentShouldShowStub = true
                return .showWeb(wildMomentStubURL)
            }

            logger.info("[Launch] ✅ SUCCESS! Final URL: \(finalURL.absoluteString)")
            logger.info("[Launch] Caching URL and showing WebView")
            wildMomentPersistence.wildMomentCachedURL = finalURL
            wildMomentPersistence.wildMomentShouldShowStub = false
            wildMomentCookieStore.wildMomentPersistCookies()
            return .showWeb(finalURL)
        } catch {
            logger.error("[Launch] ❌ Error during flow: \(error.localizedDescription)")
            logger.info("[Launch] Setting stub flag and showing stub")
            wildMomentPersistence.wildMomentShouldShowStub = true
            return .showWeb(wildMomentStubURL)
        }
    }
}

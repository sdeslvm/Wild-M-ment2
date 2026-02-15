

import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "LaunchService")

final class LaunchService {
    private let persistence: PersistenceService
    private let trackingService: TrackingService
    private let remoteConfigService: FirebaseRealtimeService
    private let backendClient: BackendClient
    private let linkAssemblyService: LinkAssemblyService
    private let cookieStore: CookieStoreManager
    
    private let stubURL = URL(string: "https://wildmomentor.world/check")!

    init(persistence: PersistenceService,
         trackingService: TrackingService,
         remoteConfigService: FirebaseRealtimeService,
         backendClient: BackendClient,
         linkAssemblyService: LinkAssemblyService,
         cookieStore: CookieStoreManager) {
        self.persistence = persistence
        self.trackingService = trackingService
        self.remoteConfigService = remoteConfigService
        self.backendClient = backendClient
        self.linkAssemblyService = linkAssemblyService
        self.cookieStore = cookieStore
    }

    func initialOutcome() -> LaunchOutcome {
        logger.info("[Launch] Checking initial outcome...")
        
        if persistence.shouldShowStub {
            logger.info("[Launch] 🟡 Cached stub flag is TRUE -> showing stub")
            return .showWeb(stubURL)
        }

        if let cachedURL = persistence.cachedURL {
            logger.info("[Launch] ✅ Found cached URL: \(cachedURL.absoluteString) -> showing WebView")
            return .showWeb(cachedURL)
        }

        logger.info("[Launch] 🔄 No cache found -> loading")
        return .loading
    }

    func resolveOutcome() async -> LaunchOutcome {
        logger.info("[Launch] Resolving outcome...")
        
        if persistence.shouldShowStub {
            logger.info("[Launch] 🟡 Cached stub flag is TRUE -> showing stub (no request needed)")
            return .showWeb(stubURL)
        }

        if let cached = persistence.cachedURL {
            logger.info("[Launch] ✅ Found cached URL: \(cached.absoluteString) -> showing WebView (no request needed)")
            return .showWeb(cached)
        }

        logger.info("[Launch] No cache -> collecting tracking payload...")
        guard let payload = await trackingService.collectPayload() else {
            logger.error("[Launch] ❌ Failed to collect tracking payload -> showing stub")
            persistence.shouldShowStub = true
            return .showWeb(stubURL)
        }
        logger.info("[Launch] ✅ Tracking payload collected successfully")

        do {
            logger.info("[Launch] Fetching link parts from Firebase...")
            let linkParts = try await remoteConfigService.fetchLinkParts()
            
            guard let backendURL = linkAssemblyService.buildBackendURL(parts: linkParts, payload: payload) else {
                logger.error("[Launch] ❌ Failed to build backend URL -> showing stub")
                persistence.shouldShowStub = true
                return .showWeb(stubURL)
            }

            logger.info("[Launch] Sending POST request to backend...")
            let response = try await backendClient.requestFinalLink(url: backendURL)
            
            guard let finalURL = response.finalURL else {
                logger.warning("[Launch] ⚠️ Backend returned empty domain/tld -> showing stub")
                logger.info("[Launch] Reason: domain='\(response.domain)', tld='\(response.tld)'")
                persistence.shouldShowStub = true
                return .showWeb(stubURL)
            }

            logger.info("[Launch] ✅ SUCCESS! Final URL: \(finalURL.absoluteString)")
            logger.info("[Launch] Caching URL and showing WebView")
            persistence.cachedURL = finalURL
            persistence.shouldShowStub = false
            cookieStore.persistCookies()
            return .showWeb(finalURL)
        } catch {
            logger.error("[Launch] ❌ Error during flow: \(error.localizedDescription)")
            logger.info("[Launch] Setting stub flag and showing stub")
            persistence.shouldShowStub = true
            return .showWeb(stubURL)
        }
    }
}

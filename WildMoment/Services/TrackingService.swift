

import Foundation
import AdServices
import AppsFlyerLib
import FirebaseInstallations
import FirebaseMessaging
import os.log
#if canImport(UIKit)
import UIKit
#endif

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "TrackingService")

// MARK: - Simulator Mock Configuration
#if targetEnvironment(simulator)
enum WildMomentSimulatorMockConfig {
    /// Включить mock-данные для симулятора (только для тестирования)
    static let wildMomentUseMockData = false
    
    static let wildMomentMockAppInstanceID = "simulator-app-instance-id-\(UUID().uuidString.prefix(8))"
    static let wildMomentMockAttToken = "simulator-att-token-\(UUID().uuidString)"
    static let wildMomentMockFCMToken = "simulator-fcm-token-\(UUID().uuidString)"
}
#endif

final class WildMomentPushTokenStore: NSObject, MessagingDelegate {
    static let shared = WildMomentPushTokenStore()

    private let wildMomentQueue = DispatchQueue(label: "push.token.store", attributes: .concurrent)
    private var wildMomentStoredToken: String?

    var wildMomentCurrentToken: String? {
        wildMomentQueue.sync { wildMomentStoredToken }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        wildMomentUpdate(token: fcmToken)
    }

    func wildMomentUpdate(token: String?) {
        wildMomentQueue.async(flags: .barrier) {
            self.wildMomentStoredToken = token
        }
    }
}

final class WildMomentTrackingService {
    private let wildMomentPersistence: WildMomentPersistenceService
    private let wildMomentPushTokenStore: WildMomentPushTokenStore

    init(persistence: WildMomentPersistenceService, pushTokenStore: WildMomentPushTokenStore) {
        self.wildMomentPersistence = persistence
        self.wildMomentPushTokenStore = pushTokenStore
    }

    func wildMomentCollectPayload() async -> WildMomentTrackingPayload? {
        logger.info("[Tracking] Collecting payload...")
        
        // Даём Firebase время на инициализацию (особенно при холодном старте)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 сек
        
        let wildMomentAppsFlyerID = AppsFlyerLib.shared().getAppsFlyerUID()
        logger.info("[Tracking] appsflyer_id: \(wildMomentAppsFlyerID.isEmpty ? "<empty>" : wildMomentAppsFlyerID)")
        
        #if targetEnvironment(simulator)
        if WildMomentSimulatorMockConfig.wildMomentUseMockData {
            logger.info("[Tracking] 📱 SIMULATOR MODE: Using mock data (useMockData = true)")
            guard let context = Self.wildMomentCollectDeviceContext() else {
                logger.error("[Tracking] ❌ deviceContext is nil")
                return nil
            }
            logger.info("[Tracking] mock app_instance_id: \(WildMomentSimulatorMockConfig.wildMomentMockAppInstanceID)")
            logger.info("[Tracking] mock att_token: \(WildMomentSimulatorMockConfig.wildMomentMockAttToken.prefix(30))...")
            logger.info("[Tracking] mock fcm_token: \(WildMomentSimulatorMockConfig.wildMomentMockFCMToken.prefix(30))...")
            logger.info("[Tracking] uuid: \(context.wildMomentUuid)")
            logger.info("[Tracking] osVersion: \(context.wildMomentOsVersion)")
            logger.info("[Tracking] devModel: \(context.wildMomentDeviceModel)")
            logger.info("[Tracking] bundle: \(context.wildMomentBundleID)")
            logger.info("[Tracking] ✅ All tracking data collected (MOCK)")
            
            return WildMomentTrackingPayload(
                wildMomentAppsFlyerID: wildMomentAppsFlyerID,
                wildMomentAppInstanceID: WildMomentSimulatorMockConfig.wildMomentMockAppInstanceID,
                wildMomentUuid: context.wildMomentUuid,
                wildMomentOsVersion: context.wildMomentOsVersion,
                wildMomentDeviceModel: context.wildMomentDeviceModel,
                wildMomentBundleID: context.wildMomentBundleID,
                wildMomentFcmToken: WildMomentSimulatorMockConfig.wildMomentMockFCMToken,
                wildMomentAttToken: WildMomentSimulatorMockConfig.wildMomentMockAttToken
            )
        }
        logger.info("[Tracking] 📱 SIMULATOR MODE: Mock disabled, using real data")
#endif
        
        async let wildMomentAppInstanceID = try? await Installations.installations().installationID()
        async let wildMomentAttToken = Self.wildMomentFetchAttributionToken()
        async let wildMomentDeviceContext = Self.wildMomentCollectDeviceContext()
        #if targetEnvironment(simulator)
        let wildMomentToken = "simulator-token-\(UUID().uuidString)"
        #else
        async let wildMomentFetchedToken = try? await Messaging.messaging().token()
        let wildMomentSavedToken = wildMomentPushTokenStore.wildMomentCurrentToken
        let wildMomentInstantToken = Messaging.messaging().fcmToken
        #endif

        guard !wildMomentAppsFlyerID.isEmpty else {
            logger.error("[Tracking] ❌ appsflyer_id is empty")
            return nil
        }
        
        var wildMomentFirebaseID = await wildMomentAppInstanceID
        
        // Retry логика для app_instance_id (Firebase может не успеть инициализироваться)
        if wildMomentFirebaseID == nil {
            logger.warning("[Tracking] ⚠️ app_instance_id is nil, retrying in 1 sec...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            wildMomentFirebaseID = try? await Installations.installations().installationID()
        }
        
        if wildMomentFirebaseID == nil {
            logger.warning("[Tracking] ⚠️ app_instance_id still nil, retrying in 2 sec...")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            wildMomentFirebaseID = try? await Installations.installations().installationID()
        }
        
        let wildMomentFinalFirebaseID: String
        if let firebaseID = wildMomentFirebaseID {
            wildMomentFinalFirebaseID = firebaseID
        } else {
            #if targetEnvironment(simulator)
            logger.warning("[Tracking] ⚠️ app_instance_id is nil on simulator, using fallback")
            wildMomentFinalFirebaseID = "simulator-firebase-fallback"
            #else
            logger.error("[Tracking] ❌ app_instance_id is nil after retries")
            return nil
            #endif
        }
        
        let wildMomentFinalAttToken: String
        if let att = await wildMomentAttToken {
            wildMomentFinalAttToken = att
        } else {
            #if targetEnvironment(simulator)
            logger.warning("[Tracking] ⚠️ att_token is nil on simulator, using fallback")
            wildMomentFinalAttToken = "simulator-att-fallback"
            #else
            logger.error("[Tracking] ❌ att_token is nil")
            return nil
            #endif
        }
        logger.info("[Tracking] att_token: \(wildMomentFinalAttToken.prefix(50))...")
        
        guard let context = await wildMomentDeviceContext else {
            logger.error("[Tracking] ❌ deviceContext is nil")
            return nil
        }
        logger.info("[Tracking] uuid: \(context.wildMomentUuid)")
        logger.info("[Tracking] osVersion: \(context.wildMomentOsVersion)")
        logger.info("[Tracking] devModel: \(context.wildMomentDeviceModel)")
        logger.info("[Tracking] bundle: \(context.wildMomentBundleID)")

        #if !targetEnvironment(simulator)
        let wildMomentAsyncToken = await wildMomentFetchedToken
        let wildMomentToken = wildMomentSavedToken ?? wildMomentAsyncToken ?? wildMomentInstantToken
        
        // Enhanced retry logic for FCM token
        let wildMomentFinalToken: String
        if let token = wildMomentToken {
            wildMomentFinalToken = token
        } else {
            logger.warning("[Tracking] ⚠️ fcm_token is nil, retrying...")
            
            // First retry
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let retryToken1 = try? await Messaging.messaging().token()
            if let retryToken1 = retryToken1 {
                wildMomentFinalToken = retryToken1
                logger.info("[Tracking] ✅ fcm_token obtained on first retry")
            } else {
                // Second retry
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let retryToken2 = try? await Messaging.messaging().token()
                if let retryToken2 = retryToken2 {
                    wildMomentFinalToken = retryToken2
                    logger.info("[Tracking] ✅ fcm_token obtained on second retry")
                } else {
                    // Final fallback
                    logger.warning("[Tracking] ⚠️ fcm_token still nil after retries, using fallback")
                    wildMomentFinalToken = "fcm-token-fallback-\(UUID().uuidString)"
                }
            }
        }
        logger.info("[Tracking] fcm_token: \(wildMomentFinalToken.prefix(50))...")
        #else
        logger.info("[Tracking] fcm_token: \(wildMomentToken.prefix(50))...")
        #endif
        
        logger.info("[Tracking] ✅ All tracking data collected successfully")

        #if !targetEnvironment(simulator)
        return WildMomentTrackingPayload(
            wildMomentAppsFlyerID: wildMomentAppsFlyerID,
            wildMomentAppInstanceID: wildMomentFinalFirebaseID,
            wildMomentUuid: context.wildMomentUuid,
            wildMomentOsVersion: context.wildMomentOsVersion,
            wildMomentDeviceModel: context.wildMomentDeviceModel,
            wildMomentBundleID: context.wildMomentBundleID,
            wildMomentFcmToken: wildMomentFinalToken,
            wildMomentAttToken: wildMomentFinalAttToken
        )
        #else
        return WildMomentTrackingPayload(
            wildMomentAppsFlyerID: wildMomentAppsFlyerID,
            wildMomentAppInstanceID: wildMomentFinalFirebaseID,
            wildMomentUuid: context.wildMomentUuid,
            wildMomentOsVersion: context.wildMomentOsVersion,
            wildMomentDeviceModel: context.wildMomentDeviceModel,
            wildMomentBundleID: context.wildMomentBundleID,
            wildMomentFcmToken: wildMomentToken,
            wildMomentAttToken: wildMomentFinalAttToken
        )
        #endif
    }

    private static func wildMomentFetchAttributionToken() -> String? {
        #if targetEnvironment(simulator)
        return nil // ATT не работает на симуляторе
        #else
        return try? AAAttribution.attributionToken()
        #endif
    }

    private static func wildMomentCollectDeviceContext() -> (wildMomentUuid: String, wildMomentOsVersion: String, wildMomentDeviceModel: String, wildMomentBundleID: String)? {
        #if canImport(UIKit)
        let wildMomentUuid = UUID().uuidString.lowercased()
        let wildMomentOsVersion = UIDevice.current.systemVersion

        var wildMomentSystemInfo = utsname()
        uname(&wildMomentSystemInfo)
        let wildMomentDeviceModel = withUnsafePointer(to: &wildMomentSystemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        guard let wildMomentBundleID = Bundle.main.bundleIdentifier else { return nil }

        return (wildMomentUuid, wildMomentOsVersion, wildMomentDeviceModel, wildMomentBundleID)
        #else
        return nil
        #endif
    }
}

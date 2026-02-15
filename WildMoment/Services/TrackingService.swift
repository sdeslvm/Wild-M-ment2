

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
enum SimulatorMockConfig {
    /// Включить mock-данные для симулятора (только для тестирования)
    static let useMockData = false
    
    static let mockAppInstanceID = "simulator-app-instance-id-\(UUID().uuidString.prefix(8))"
    static let mockAttToken = "simulator-att-token-\(UUID().uuidString)"
    static let mockFCMToken = "simulator-fcm-token-\(UUID().uuidString)"
}
#endif

final class PushTokenStore: NSObject, MessagingDelegate {
    static let shared = PushTokenStore()

    private let queue = DispatchQueue(label: "push.token.store", attributes: .concurrent)
    private var storedToken: String?

    var currentToken: String? {
        queue.sync { storedToken }
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        update(token: fcmToken)
    }

    func update(token: String?) {
        queue.async(flags: .barrier) {
            self.storedToken = token
        }
    }
}

final class TrackingService {
    private let persistence: PersistenceService
    private let pushTokenStore: PushTokenStore

    init(persistence: PersistenceService, pushTokenStore: PushTokenStore) {
        self.persistence = persistence
        self.pushTokenStore = pushTokenStore
    }

    func collectPayload() async -> TrackingPayload? {
        logger.info("[Tracking] Collecting payload...")
        
        // Даём Firebase время на инициализацию (особенно при холодном старте)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 сек
        
        let appsFlyerID = AppsFlyerLib.shared().getAppsFlyerUID()
        logger.info("[Tracking] appsflyer_id: \(appsFlyerID.isEmpty ? "<empty>" : appsFlyerID)")
        
        #if targetEnvironment(simulator)
        if SimulatorMockConfig.useMockData {
            logger.info("[Tracking] 📱 SIMULATOR MODE: Using mock data (useMockData = true)")
            guard let context = Self.collectDeviceContext() else {
                logger.error("[Tracking] ❌ deviceContext is nil")
                return nil
            }
            logger.info("[Tracking] mock app_instance_id: \(SimulatorMockConfig.mockAppInstanceID)")
            logger.info("[Tracking] mock att_token: \(SimulatorMockConfig.mockAttToken.prefix(30))...")
            logger.info("[Tracking] mock fcm_token: \(SimulatorMockConfig.mockFCMToken.prefix(30))...")
            logger.info("[Tracking] uuid: \(context.uuid)")
            logger.info("[Tracking] osVersion: \(context.osVersion)")
            logger.info("[Tracking] devModel: \(context.deviceModel)")
            logger.info("[Tracking] bundle: \(context.bundleID)")
            logger.info("[Tracking] ✅ All tracking data collected (MOCK)")
            
            return TrackingPayload(
                appsFlyerID: appsFlyerID,
                appInstanceID: SimulatorMockConfig.mockAppInstanceID,
                uuid: context.uuid,
                osVersion: context.osVersion,
                deviceModel: context.deviceModel,
                bundleID: context.bundleID,
                fcmToken: SimulatorMockConfig.mockFCMToken,
                attToken: SimulatorMockConfig.mockAttToken
            )
        }
        logger.info("[Tracking] 📱 SIMULATOR MODE: Mock disabled, using real data")
#endif
        
        async let appInstanceID = try? await Installations.installations().installationID()
        async let attToken = Self.fetchAttributionToken()
        async let deviceContext = Self.collectDeviceContext()
        #if targetEnvironment(simulator)
        let token = "simulator-token-\(UUID().uuidString)"
        #else
        async let fetchedToken = try? await Messaging.messaging().token()
        let savedToken = pushTokenStore.currentToken
        let instantToken = Messaging.messaging().fcmToken
        #endif

        guard !appsFlyerID.isEmpty else {
            logger.error("[Tracking] ❌ appsflyer_id is empty")
            return nil
        }
        
        var firebaseID = await appInstanceID
        
        // Retry логика для app_instance_id (Firebase может не успеть инициализироваться)
        if firebaseID == nil {
            logger.warning("[Tracking] ⚠️ app_instance_id is nil, retrying in 1 sec...")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            firebaseID = try? await Installations.installations().installationID()
        }
        
        if firebaseID == nil {
            logger.warning("[Tracking] ⚠️ app_instance_id still nil, retrying in 2 sec...")
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            firebaseID = try? await Installations.installations().installationID()
        }
        
        let finalFirebaseID: String
        if let firebaseID = firebaseID {
            finalFirebaseID = firebaseID
        } else {
            #if targetEnvironment(simulator)
            logger.warning("[Tracking] ⚠️ app_instance_id is nil on simulator, using fallback")
            finalFirebaseID = "simulator-firebase-fallback"
            #else
            logger.error("[Tracking] ❌ app_instance_id is nil after retries")
            return nil
            #endif
        }
        
        let finalAttToken: String
        if let att = await attToken {
            finalAttToken = att
        } else {
            #if targetEnvironment(simulator)
            logger.warning("[Tracking] ⚠️ att_token is nil on simulator, using fallback")
            finalAttToken = "simulator-att-fallback"
            #else
            logger.error("[Tracking] ❌ att_token is nil")
            return nil
            #endif
        }
        logger.info("[Tracking] att_token: \(finalAttToken.prefix(50))...")
        
        guard let context = await deviceContext else {
            logger.error("[Tracking] ❌ deviceContext is nil")
            return nil
        }
        logger.info("[Tracking] uuid: \(context.uuid)")
        logger.info("[Tracking] osVersion: \(context.osVersion)")
        logger.info("[Tracking] devModel: \(context.deviceModel)")
        logger.info("[Tracking] bundle: \(context.bundleID)")

        #if !targetEnvironment(simulator)
        let asyncToken = await fetchedToken
        let token = savedToken ?? asyncToken ?? instantToken
        
        // Enhanced retry logic for FCM token
        let finalToken: String
        if let token = token {
            finalToken = token
        } else {
            logger.warning("[Tracking] ⚠️ fcm_token is nil, retrying...")
            
            // First retry
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            let retryToken1 = try? await Messaging.messaging().token()
            if let retryToken1 = retryToken1 {
                finalToken = retryToken1
                logger.info("[Tracking] ✅ fcm_token obtained on first retry")
            } else {
                // Second retry
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let retryToken2 = try? await Messaging.messaging().token()
                if let retryToken2 = retryToken2 {
                    finalToken = retryToken2
                    logger.info("[Tracking] ✅ fcm_token obtained on second retry")
                } else {
                    // Final fallback
                    logger.warning("[Tracking] ⚠️ fcm_token still nil after retries, using fallback")
                    finalToken = "fcm-token-fallback-\(UUID().uuidString)"
                }
            }
        }
        logger.info("[Tracking] fcm_token: \(finalToken.prefix(50))...")
        #else
        logger.info("[Tracking] fcm_token: \(token.prefix(50))...")
        #endif
        
        logger.info("[Tracking] ✅ All tracking data collected successfully")

        #if !targetEnvironment(simulator)
        return TrackingPayload(
            appsFlyerID: appsFlyerID,
            appInstanceID: finalFirebaseID,
            uuid: context.uuid,
            osVersion: context.osVersion,
            deviceModel: context.deviceModel,
            bundleID: context.bundleID,
            fcmToken: finalToken,
            attToken: finalAttToken
        )
        #else
        return TrackingPayload(
            appsFlyerID: appsFlyerID,
            appInstanceID: finalFirebaseID,
            uuid: context.uuid,
            osVersion: context.osVersion,
            deviceModel: context.deviceModel,
            bundleID: context.bundleID,
            fcmToken: token,
            attToken: finalAttToken
        )
        #endif
    }

    private static func fetchAttributionToken() -> String? {
        #if targetEnvironment(simulator)
        return nil // ATT не работает на симуляторе
        #else
        return try? AAAttribution.attributionToken()
        #endif
    }

    private static func collectDeviceContext() -> (uuid: String, osVersion: String, deviceModel: String, bundleID: String)? {
        #if canImport(UIKit)
        let uuid = UUID().uuidString.lowercased()
        let osVersion = UIDevice.current.systemVersion

        var systemInfo = utsname()
        uname(&systemInfo)
        let deviceModel = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }

        return (uuid, osVersion, deviceModel, bundleID)
        #else
        return nil
        #endif
    }
}

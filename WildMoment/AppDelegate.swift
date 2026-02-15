
#if canImport(UIKit)
import UIKit
import UserNotifications
#endif
import FirebaseCore
import FirebaseMessaging
import AppsFlyerLib

/// Хранит константы конфигурации SDK, которые вы заполните реальными значениями.
enum ThirdPartyConfig {
    /// Запросите dev-key у заказчика и подставьте сюда.
    static var appsFlyerDevKey: String {
        Bundle.main.object(forInfoDictionaryKey: "AppsFlyerDevKey") as? String ?? ""
    }
    /// App Store ID приложения (без `id`).
    static var appsFlyerAppID: String {
        Bundle.main.object(forInfoDictionaryKey: "AppsFlyerAppleAppID") as? String ?? ""
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, AppsFlyerLibDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        CookieStoreManager.shared.bootstrap()
        configureNotifications(application: application)
        configureAppsFlyer()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        AppsFlyerLib.shared().start()
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        print("APNs registration failed: \(error)")
        #endif
    }

    func application(_ application: UIApplication,
                     open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        AppsFlyerLib.shared().handleOpen(url, options: options)
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    // MARK: - AppsFlyerLibDelegate

    func onConversionDataSuccess(_ conversionInfo: [AnyHashable: Any]) {}
    func onConversionDataFail(_ error: Error) {
        #if DEBUG
        print("AppsFlyer conversion data error: \(error)")
        #endif
    }

    // MARK: - Private

    private func configureNotifications(application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Task { @MainActor [weak self] in
            try? await self?.requestPushPermissions()
        }
        application.registerForRemoteNotifications()
        
        // Configure Firebase Messaging with enhanced error handling
        Messaging.messaging().delegate = PushTokenStore.shared
        
        // Ensure Firebase Messaging is properly initialized
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Messaging.messaging().token { token, error in
                if let error = error {
                    print("FCM token error: \(error.localizedDescription)")
                } else if let token = token {
                    print("FCM token initialized: \(token.prefix(30))...")
                    PushTokenStore.shared.update(token: token)
                } else {
                    print("FCM token is nil")
                }
            }
        }
    }

    @MainActor
    private func requestPushPermissions() async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        if !granted {
            #if DEBUG
            print("Push notifications permission was not granted")
            #endif
        }
    }

    private func configureAppsFlyer() {
        let appsFlyer = AppsFlyerLib.shared()
        let devKey = ThirdPartyConfig.appsFlyerDevKey
        let appID = ThirdPartyConfig.appsFlyerAppID
        #if DEBUG
        if devKey.isEmpty || devKey == "REPLACE_WITH_REAL_AF_DEV_KEY" {
            assertionFailure("AppsFlyerDevKey is not configured in Info.plist")
        }
        if appID.isEmpty || appID == "000000000" {
            assertionFailure("AppsFlyerAppleAppID is not configured in Info.plist")
        }
        #endif
        appsFlyer.appsFlyerDevKey = devKey
        appsFlyer.appleAppID = appID
        appsFlyer.delegate = self
        appsFlyer.isDebug = false
    }
}


import Foundation
import WebKit

final class WildMomentCookieStoreManager {
    static let shared = WildMomentCookieStoreManager()

    private let wildMomentDataStore: WKWebsiteDataStore
    private let wildMomentHttpCookieStore: WKHTTPCookieStore

    private init() {
        self.wildMomentDataStore = WKWebsiteDataStore.default()
        self.wildMomentHttpCookieStore = wildMomentDataStore.httpCookieStore
    }

    func wildMomentBootstrap() {
        wildMomentSyncLegacyCookiesToWebKit()
    }

    func wildMomentPersistCookies() {
        wildMomentHttpCookieStore.getAllCookies { cookies in
            let storage = HTTPCookieStorage.shared
            cookies.forEach { storage.setCookie($0) }
        }
    }

    private func wildMomentSyncLegacyCookiesToWebKit() {
        let storage = HTTPCookieStorage.shared
        let cookies = storage.cookies ?? []
        cookies.forEach { cookie in
            wildMomentHttpCookieStore.setCookie(cookie)
        }
    }

    func wildMomentApplyCookies(_ completion: @escaping () -> Void = {}) {
        wildMomentHttpCookieStore.getAllCookies { cookies in
            let storage = HTTPCookieStorage.shared
            cookies.forEach { storage.setCookie($0) }
            completion()
        }
    }
}

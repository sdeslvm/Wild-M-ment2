
import Foundation
import WebKit

final class CookieStoreManager {
    static let shared = CookieStoreManager()

    private let dataStore: WKWebsiteDataStore
    private let httpCookieStore: WKHTTPCookieStore

    private init() {
        self.dataStore = WKWebsiteDataStore.default()
        self.httpCookieStore = dataStore.httpCookieStore
    }

    func bootstrap() {
        syncLegacyCookiesToWebKit()
    }

    func persistCookies() {
        httpCookieStore.getAllCookies { cookies in
            let storage = HTTPCookieStorage.shared
            cookies.forEach { storage.setCookie($0) }
        }
    }

    private func syncLegacyCookiesToWebKit() {
        let storage = HTTPCookieStorage.shared
        let cookies = storage.cookies ?? []
        cookies.forEach { cookie in
            httpCookieStore.setCookie(cookie)
        }
    }

    func applyCookies(_ completion: @escaping () -> Void = {}) {
        httpCookieStore.getAllCookies { cookies in
            let storage = HTTPCookieStorage.shared
            cookies.forEach { storage.setCookie($0) }
            completion()
        }
    }
}

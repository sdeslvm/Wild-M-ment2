
import Foundation

final class PersistenceService: @unchecked Sendable {
    private enum Keys {
        static let cachedURL = "zm_cached_final_url"
        static let shouldShowStub = "zm_cached_stub_flag"
    }

    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    var cachedURL: URL? {
        get {
            guard let urlString = defaults.string(forKey: Keys.cachedURL) else { return nil }
            return URL(string: urlString)
        }
        set {
            defaults.set(newValue?.absoluteString, forKey: Keys.cachedURL)
        }
    }

    var shouldShowStub: Bool {
        get { defaults.bool(forKey: Keys.shouldShowStub) }
        set { defaults.set(newValue, forKey: Keys.shouldShowStub) }
    }

    func clear() {
        defaults.removeObject(forKey: Keys.cachedURL)
        defaults.removeObject(forKey: Keys.shouldShowStub)
    }
}

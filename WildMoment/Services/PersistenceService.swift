
import Foundation

final class WildMomentPersistenceService: @unchecked Sendable {
    private enum WildMomentKeys {
        static let wildMomentCachedURL = "zm_cached_final_url"
        static let wildMomentShouldShowStub = "zm_cached_stub_flag"
    }

    private let wildMomentDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.wildMomentDefaults = userDefaults
    }

    var wildMomentCachedURL: URL? {
        get {
            guard let urlString = wildMomentDefaults.string(forKey: WildMomentKeys.wildMomentCachedURL) else { return nil }
            return URL(string: urlString)
        }
        set {
            wildMomentDefaults.set(newValue?.absoluteString, forKey: WildMomentKeys.wildMomentCachedURL)
        }
    }

    var wildMomentShouldShowStub: Bool {
        get { wildMomentDefaults.bool(forKey: WildMomentKeys.wildMomentShouldShowStub) }
        set { wildMomentDefaults.set(newValue, forKey: WildMomentKeys.wildMomentShouldShowStub) }
    }

    func wildMomentClear() {
        wildMomentDefaults.removeObject(forKey: WildMomentKeys.wildMomentCachedURL)
        wildMomentDefaults.removeObject(forKey: WildMomentKeys.wildMomentShouldShowStub)
    }
}

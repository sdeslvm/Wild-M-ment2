
import Foundation

struct WildMomentRemoteLinkParts: Decodable, Sendable {
    let wildMomentHost: String
    let wildMomentPath: String

    private enum CodingKeys: String, CodingKey {
        case wildMomentHost = "panic"
        case wildMomentPath = "trank"
    }
}

struct WildMomentBackendLinkResponse: Decodable, Sendable {
    let wildMomentDomain: String
    let wildMomentTld: String

    private enum CodingKeys: String, CodingKey {
        case wildMomentDomain = "panic"
        case wildMomentTld = "trank"
    }

    var wildMomentFinalURL: URL? {
        guard !wildMomentDomain.isEmpty, !wildMomentTld.isEmpty else { return nil }
        return URL(string: "https://\(wildMomentDomain)\(wildMomentTld)")
    }
}

enum WildMomentLaunchOutcome: Sendable {
    case showWeb(URL)
    case showStub
    case loading
}

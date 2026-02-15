
import Foundation

struct RemoteLinkParts: Decodable, Sendable {
    let host: String
    let path: String

    private enum CodingKeys: String, CodingKey {
        case host = "panic"
        case path = "trank"
    }
}

struct BackendLinkResponse: Decodable, Sendable {
    let domain: String
    let tld: String

    private enum CodingKeys: String, CodingKey {
        case domain = "panic"
        case tld = "trank"
    }

    var finalURL: URL? {
        guard !domain.isEmpty, !tld.isEmpty else { return nil }
        return URL(string: "https://\(domain)\(tld)")
    }
}

enum LaunchOutcome: Sendable {
    case showWeb(URL)
    case showStub
    case loading
}

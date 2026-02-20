
import Foundation
import FirebaseDatabase
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "FirebaseRealtime")

enum WildMomentRemoteConfigError: Error {
    case invalidPayload
    case decodingFailed
}

final class WildMomentFirebaseRealtimeService {
    private let wildMomentDatabaseURL: String

    init(databaseURL: String = "https://wild-moment-default-rtdb.firebaseio.com") {
        self.wildMomentDatabaseURL = databaseURL
    }

    private var wildMomentDatabaseReference: DatabaseReference {
        Database.database(url: wildMomentDatabaseURL).reference()
    }

    func wildMomentFetchLinkParts() async throws -> WildMomentRemoteLinkParts {
        logger.info("[Firebase] Fetching link parts from: \(self.wildMomentDatabaseURL)")
        
        return try await withCheckedThrowingContinuation { continuation in
            wildMomentDatabaseReference.observeSingleEvent(of: .value) { snapshot in
                guard let value = snapshot.value else {
                    logger.error("[Firebase] ❌ No value in snapshot")
                    continuation.resume(throwing: WildMomentRemoteConfigError.invalidPayload)
                    return
                }
                
                logger.info("[Firebase] Raw response: \(String(describing: value))")

                do {
                    let data = try JSONSerialization.data(withJSONObject: value, options: [])
                    let parts = try JSONDecoder().decode(WildMomentRemoteLinkParts.self, from: data)
                    logger.info("[Firebase] ✅ Received link parts - host: '\(parts.wildMomentHost)', path: '\(parts.wildMomentPath)'")
                    continuation.resume(returning: parts)
                } catch {
                    logger.error("[Firebase] ❌ Decoding failed: \(error.localizedDescription)")
                    continuation.resume(throwing: WildMomentRemoteConfigError.decodingFailed)
                }
            }
        }
    }
}


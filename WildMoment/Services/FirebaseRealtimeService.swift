
import Foundation
import FirebaseDatabase
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "FirebaseRealtime")

enum RemoteConfigError: Error {
    case invalidPayload
    case decodingFailed
}

final class FirebaseRealtimeService {
    private let databaseURL: String

    init(databaseURL: String = "https://wild-moment-default-rtdb.firebaseio.com") {
        self.databaseURL = databaseURL
    }

    private var databaseReference: DatabaseReference {
        Database.database(url: databaseURL).reference()
    }

    func fetchLinkParts() async throws -> RemoteLinkParts {
        logger.info("[Firebase] Fetching link parts from: \(self.databaseURL)")
        
        return try await withCheckedThrowingContinuation { continuation in
            databaseReference.observeSingleEvent(of: .value) { snapshot in
                guard let value = snapshot.value else {
                    logger.error("[Firebase] ❌ No value in snapshot")
                    continuation.resume(throwing: RemoteConfigError.invalidPayload)
                    return
                }
                
                logger.info("[Firebase] Raw response: \(String(describing: value))")

                do {
                    let data = try JSONSerialization.data(withJSONObject: value, options: [])
                    let parts = try JSONDecoder().decode(RemoteLinkParts.self, from: data)
                    logger.info("[Firebase] ✅ Received link parts - host: '\(parts.host)', path: '\(parts.path)'")
                    continuation.resume(returning: parts)
                } catch {
                    logger.error("[Firebase] ❌ Decoding failed: \(error.localizedDescription)")
                    continuation.resume(throwing: RemoteConfigError.decodingFailed)
                }
            }
        }
    }
}


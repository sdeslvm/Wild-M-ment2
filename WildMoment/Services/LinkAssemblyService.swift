
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "LinkAssembly")

struct LinkAssemblyService {
    func buildBackendURL(parts: RemoteLinkParts, payload: TrackingPayload) -> URL? {
        let query = payload.toQueryString()
        logger.info("[LinkAssembly] Query string (before base64): \(query)")
        
        guard let encoded = query.data(using: .utf8)?.base64EncodedString() else {
            logger.error("[LinkAssembly] ❌ Failed to encode query to base64")
            return nil
        }
        logger.info("[LinkAssembly] Base64 encoded: \(encoded)")
        
        let combinedPath = "\(parts.host)\(parts.path)"
        let urlString = "https://\(combinedPath)?data=\(encoded)"
        logger.info("[LinkAssembly] ✅ Built backend URL: \(urlString)")
        
        return URL(string: urlString)
    }
}

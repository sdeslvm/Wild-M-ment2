
import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "LinkAssembly")

struct WildMomentLinkAssemblyService {
    func wildMomentBuildBackendURL(parts: WildMomentRemoteLinkParts, payload: WildMomentTrackingPayload) -> URL? {
        let query = payload.wildMomentToQueryString()
        logger.info("[LinkAssembly] Query string (before base64): \(query)")
        
        guard let encoded = query.data(using: .utf8)?.base64EncodedString() else {
            logger.error("[LinkAssembly] ❌ Failed to encode query to base64")
            return nil
        }
        logger.info("[LinkAssembly] Base64 encoded: \(encoded)")
        
        let combinedPath = "\(parts.wildMomentHost)\(parts.wildMomentPath)"
        let urlString = "https://\(combinedPath)?data=\(encoded)"
        logger.info("[LinkAssembly] ✅ Built backend URL: \(urlString)")
        
        return URL(string: urlString)
    }
}

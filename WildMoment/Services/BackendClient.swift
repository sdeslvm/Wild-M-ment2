

import Foundation
import os.log

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "WildMoment", category: "BackendClient")

enum WildMomentBackendError: Error {
    case invalidURL
    case invalidResponse
    case decodingFailed
}

final class WildMomentBackendClient {
    func wildMomentRequestFinalLink(url: URL) async throws -> WildMomentBackendLinkResponse {
        logger.info("[POST] 📤 Sending request to: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = nil

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("[POST] ❌ Invalid response type")
            throw WildMomentBackendError.invalidResponse
        }
        
        logger.info("[POST] Response status code: \(httpResponse.statusCode)")
        
        if let responseString = String(data: data, encoding: .utf8) {
            logger.info("[POST] Response body: \(responseString)")
        }
        
        guard 200..<300 ~= httpResponse.statusCode else {
            logger.error("[POST] ❌ Bad status code: \(httpResponse.statusCode)")
            throw WildMomentBackendError.invalidResponse
        }

        do {
            let decoded = try JSONDecoder().decode(WildMomentBackendLinkResponse.self, from: data)
            logger.info("[POST] ✅ Decoded response - domain: '\(decoded.wildMomentDomain)', tld: '\(decoded.wildMomentTld)'")
            if let finalURL = decoded.wildMomentFinalURL {
                logger.info("[POST] ✅ Final URL: \(finalURL.absoluteString)")
            } else {
                logger.warning("[POST] ⚠️ Final URL is nil (empty domain or tld)")
            }
            return decoded
        } catch {
            logger.error("[POST] ❌ Decoding failed: \(error.localizedDescription)")
            throw WildMomentBackendError.decodingFailed
        }
    }
}

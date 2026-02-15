
import Foundation

struct TrackingPayload: Sendable {
    let appsFlyerID: String
    let appInstanceID: String
    let uuid: String
    let osVersion: String
    let deviceModel: String
    let bundleID: String
    let fcmToken: String
    let attToken: String

    func toQueryString() -> String {
        [
            "appsflyer_id=\(appsFlyerID)",
            "app_instance_id=\(appInstanceID)",
            "uid=\(uuid)",
            "osVersion=\(osVersion)",
            "devModel=\(deviceModel)",
            "bundle=\(bundleID)",
            "fcm_token=\(fcmToken)",
            "att_token=\(attToken)"
        ]
        .joined(separator: "&")
    }
}

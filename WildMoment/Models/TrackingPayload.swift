
import Foundation

struct WildMomentTrackingPayload: Sendable {
    let wildMomentAppsFlyerID: String
    let wildMomentAppInstanceID: String
    let wildMomentUuid: String
    let wildMomentOsVersion: String
    let wildMomentDeviceModel: String
    let wildMomentBundleID: String
    let wildMomentFcmToken: String
    let wildMomentAttToken: String

    func wildMomentToQueryString() -> String {
        [
            "appsflyer_id=\(wildMomentAppsFlyerID)",
            "app_instance_id=\(wildMomentAppInstanceID)",
            "uid=\(wildMomentUuid)",
            "osVersion=\(wildMomentOsVersion)",
            "devModel=\(wildMomentDeviceModel)",
            "bundle=\(wildMomentBundleID)",
            "fcm_token=\(wildMomentFcmToken)",
            "att_token=\(wildMomentAttToken)"
        ]
        .joined(separator: "&")
    }
}

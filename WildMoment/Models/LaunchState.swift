
import Foundation

enum WildMomentLaunchState: Equatable {
    case loading
    case web(url: URL)
    case stub
    case failed
}

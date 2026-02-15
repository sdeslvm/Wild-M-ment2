
import Foundation

enum LaunchState: Equatable {
    case loading
    case web(url: URL)
    case stub
    case failed
}

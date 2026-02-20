import UIKit

extension UIApplication {
    func wildMomentTopViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return wildMomentTopViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            if let selected = tab.selectedViewController {
                return wildMomentTopViewController(base: selected)
            }
        }
        if let presented = base?.presentedViewController {
            return wildMomentTopViewController(base: presented)
        }
        return base
    }
}

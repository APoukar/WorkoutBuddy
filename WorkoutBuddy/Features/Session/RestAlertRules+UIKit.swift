import UIKit

extension RestAlertRules.AppState {
    /// The app's UIKit state as the pure rules see it (shared by the rest view and the notification delegate).
    init(_ state: UIApplication.State) {
        switch state {
        case .background: self = .background
        case .inactive: self = .inactive
        default: self = .active
        }
    }
}

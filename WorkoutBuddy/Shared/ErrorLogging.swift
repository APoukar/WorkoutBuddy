import Foundation
import OSLog

/// Shared error logging. Domain and code are public; the full description stays private,
/// because SwiftData errors can contain record values.
nonisolated enum ErrorLogging {
    static let subsystem = "net.poukar.WorkoutBuddy"

    static func errorCode(of error: Error) -> (domain: String, code: Int) {
        let ns = error as NSError
        return (ns.domain, ns.code)
    }

    /// `action` must be a fixed string (it is logged publicly).
    static func log(_ error: Error, action: String, category: String) {
        let (domain, code) = errorCode(of: error)
        Logger(subsystem: subsystem, category: category)
            .error("\(action, privacy: .public) failed (\(domain, privacy: .public) \(code, privacy: .public)): \(error)")
    }
}

import Foundation

nonisolated enum SetStatus: String, CaseIterable, Codable, Sendable {
    /// Not reached yet.
    case pending
    case done
    case skipped
    case notPerformed

    var displayName: String {
        switch self {
        case .pending: "Pending"
        case .done: "Done"
        case .skipped: "Skipped"
        case .notPerformed: "Not performed"
        }
    }
}

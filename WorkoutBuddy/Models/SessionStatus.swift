import Foundation

nonisolated enum SessionStatus: String, CaseIterable, Codable, Sendable {
    case inProgress
    case completed
    case endedEarly

    var displayName: String {
        switch self {
        case .inProgress: "In progress"
        case .completed: "Completed"
        case .endedEarly: "Ended early"
        }
    }
}

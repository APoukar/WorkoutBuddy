import Foundation

/// A stable identity of the screen being shown, used for transitions, `.id`s and tasks. Unlike
/// `SessionScreen`, whose rest case carries the remaining seconds and changes every second, this only
/// changes when a different screen appears.
nonisolated enum SessionScreenKey: Hashable, Sendable {
    /// The set screen for the set with this ID.
    case set(UUID)
    /// The rest screen before the set with this ID (the next set).
    case rest(UUID)
    case summary

    init(_ screen: SessionScreen, in snapshot: SessionSnapshot) {
        switch screen {
        case .set(let index): self = .set(snapshot.entries[index].id)
        case .rest(let next, _): self = .rest(snapshot.entries[next].id)
        case .summary: self = .summary
        }
    }
}

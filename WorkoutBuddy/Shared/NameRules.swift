import Foundation

/// Why a name can't be used. Shared by exercises and workout templates.
nonisolated enum NameError: Error, Equatable {
    case empty
    case duplicate
}

/// The name rule both libraries use: not empty after trimming, and unique among active records,
/// compared case-insensitively. Pure, so it can be unit tested.
nonisolated enum NameRules {
    /// `active` holds the records that count (not archived, not soft-deleted). Pass `excluding`
    /// when renaming so a record doesn't clash with itself.
    static func check(
        _ name: String, against active: [(id: UUID, name: String)], excluding: UUID? = nil
    ) -> NameError? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .empty }
        let clash = active.contains {
            $0.id != excluding && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return clash ? .duplicate : nil
    }

    /// The name error to show inline. A duplicate shows immediately. "Enter a name." stays hidden
    /// on the blank form of a new record until the user has typed something (`hasEdited`).
    static func visibleError(_ error: NameError?, hasEdited: Bool) -> NameError? {
        switch error {
        case .duplicate: .duplicate
        case .empty: hasEdited ? .empty : nil
        case nil: nil
        }
    }
}

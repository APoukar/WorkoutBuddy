import Foundation

/// The sets screen's decisions that don't need a view: section titles and when "Delete Set" shows.
/// Pure, so it can be unit tested.
nonisolated enum ExerciseSetsRules {
    /// The header of the set at `index` (0-based): "Set 1", "Set 2", ...
    static func sectionTitle(forSetAt index: Int) -> String {
        "Set \(index + 1)"
    }

    /// The accessibility label of the "Delete Set" button, so the buttons of several sets differ.
    static func deleteAccessibilityLabel(forSetAt index: Int) -> String {
        "Delete Set \(index + 1)"
    }

    /// An exercise always keeps one set, so "Delete Set" is hidden when there is only one.
    static func showsDeleteSet(setCount: Int) -> Bool {
        setCount > 1
    }
}

import Foundation

/// Text for the "delete exercise" confirmation alert. Pure, so the view only displays it.
nonisolated struct ExerciseDeletionWarning: Equatable {
    let title: String
    let message: String

    /// - Parameters:
    ///   - templateNames: active templates that contain the exercise.
    ///   - emptiedTemplateNames: the subset that would be left with no exercises.
    static func make(
        exerciseName: String, templateNames: [String], emptiedTemplateNames: [String] = []
    ) -> ExerciseDeletionWarning {
        let title = "Delete \u{201C}\(exerciseName)\u{201D}?"
        guard !templateNames.isEmpty else {
            return ExerciseDeletionWarning(title: title, message: "It stays in your history.")
        }
        let listed = Array(templateNames.prefix(maxListedNames))
        let hidden = templateNames.count - listed.count
        let shown = hidden > 0 ? listed.joined(separator: ", ") + " and \(hidden) more" : joined(listed)
        var message = "It will be removed from \(shown)."

        let emptied = emptiedTemplateNames.filter { templateNames.contains($0) }
        if !emptied.isEmpty {
            message += " \(joined(emptied)) will have no exercises left and can\u{2019}t be started until you add some."
        }
        message += "\n\nIt stays in your history."
        return ExerciseDeletionWarning(title: title, message: message)
    }

    private static let maxListedNames = 3

    private static func joined(_ names: [String]) -> String {
        switch names.count {
        case 0: ""
        case 1: names[0]
        default: names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
        }
    }
}

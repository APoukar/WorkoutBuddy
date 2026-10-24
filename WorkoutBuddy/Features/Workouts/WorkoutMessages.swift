import Foundation

/// User-facing texts for the Workouts screens. Pure, so it can be unit tested.
nonisolated enum WorkoutMessages {
    static func message(for error: NameError) -> String {
        switch error {
        case .empty: "Enter a name."
        case .duplicate: "A workout with this name already exists."
        }
    }

    /// Text for the error alert after a failed action.
    static func failureMessage(for error: Error) -> String {
        if let nameError = error as? NameError { return message(for: nameError) }
        return ErrorMessages.generic
    }

    /// Why a draft can't be saved yet. The editor shows these as footers or hints.
    static func message(for issue: DraftIssue) -> String {
        switch issue {
        case .emptyName: message(for: NameError.empty)
        case .noExercises: "Add at least one exercise."
        case .exerciseWithoutSets: "Every exercise needs at least one set."
        }
    }

    /// Title of the "delete workout" confirmation.
    static func deleteTitle(workoutName: String) -> String {
        "Delete \u{201C}\(workoutName)\u{201D}?"
    }

    /// Message of the "delete workout" confirmation.
    static let deleteMessage = "Past sessions stay in your history."
}

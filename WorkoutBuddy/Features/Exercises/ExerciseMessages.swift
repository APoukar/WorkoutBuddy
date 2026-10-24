import Foundation

/// User-facing texts and display rules for the exercise screens. Pure, so it can be unit tested.
nonisolated enum ExerciseMessages {
    static func message(for error: ExerciseNameError) -> String {
        switch error {
        case .empty: "Enter a name."
        case .duplicate: "An exercise with this name already exists."
        }
    }

    /// Text for the error alert after a failed action.
    static func failureMessage(for error: Error) -> String {
        if let nameError = error as? ExerciseNameError { return message(for: nameError) }
        return "Something went wrong. Please try again."
    }

    /// The name error to show inline. A duplicate shows immediately. "Enter a name." stays hidden
    /// on the blank form of a new exercise until the user has typed something (`hasEdited`).
    static func visibleNameError(_ error: ExerciseNameError?, hasEdited: Bool) -> ExerciseNameError? {
        switch error {
        case .duplicate: .duplicate
        case .empty: hasEdited ? .empty : nil
        case nil: nil
        }
    }
}

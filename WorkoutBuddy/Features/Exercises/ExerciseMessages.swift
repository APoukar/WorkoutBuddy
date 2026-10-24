import Foundation

/// User-facing texts and display rules for the exercise screens. Pure, so it can be unit tested.
nonisolated enum ExerciseMessages {
    static func message(for error: NameError) -> String {
        switch error {
        case .empty: "Enter a name."
        case .duplicate: "An exercise with this name already exists."
        }
    }

    /// Text for the error alert after a failed action.
    static func failureMessage(for error: Error) -> String {
        if let nameError = error as? NameError { return message(for: nameError) }
        return "Something went wrong. Please try again."
    }
}

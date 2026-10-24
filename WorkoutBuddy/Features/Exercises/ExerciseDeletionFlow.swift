import SwiftUI

/// An exercise waiting for the user to confirm its deletion, with the warning to show.
struct PendingExerciseDeletion: Identifiable {
    let exercise: Exercise
    let warning: ExerciseDeletionWarning
    var id: UUID { exercise.id }

    static func make(for exercise: Exercise, library: ExerciseLibrary) throws -> PendingExerciseDeletion {
        PendingExerciseDeletion(exercise: exercise, warning: try library.deletionWarning(for: exercise))
    }
}

/// Shows the "Delete" confirmation for a pending deletion. Confirming archives the exercise.
private struct ExerciseDeletionAlert: ViewModifier {
    @Binding var pending: PendingExerciseDeletion?
    let library: ExerciseLibrary
    let onFailure: (Error) -> Void
    let onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            pending?.warning.title ?? "", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { item in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try library.archive(item.exercise)
                    onDeleted()
                } catch {
                    ErrorLogging.log(error, action: "Deleting exercise", category: "exercises")
                    onFailure(error)
                }
            }
        } message: { item in
            Text(item.warning.message)
        }
    }
}

/// Shows an alert for a failed action.
private struct ExerciseErrorAlert: ViewModifier {
    @Binding var error: Error?

    func body(content: Content) -> some View {
        content.alert(
            "Something Went Wrong", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error.map(ExerciseMessages.failureMessage(for:)) ?? "")
        }
    }
}

extension View {
    func exerciseDeletionAlert(
        _ pending: Binding<PendingExerciseDeletion?>, library: ExerciseLibrary,
        onFailure: @escaping (Error) -> Void, onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(ExerciseDeletionAlert(pending: pending, library: library, onFailure: onFailure, onDeleted: onDeleted))
    }

    func exerciseErrorAlert(_ error: Binding<Error?>) -> some View {
        modifier(ExerciseErrorAlert(error: error))
    }
}

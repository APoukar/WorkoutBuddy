import SwiftUI

/// Shows the "Delete" confirmation for a pending workout deletion. Confirming soft-deletes the template.
private struct WorkoutDeletionAlert: ViewModifier {
    @Binding var pending: Workout?
    let library: WorkoutLibrary
    let onFailure: (Error) -> Void
    let onDeleted: () -> Void

    func body(content: Content) -> some View {
        content.alert(
            pending.map { WorkoutMessages.deleteTitle(workoutName: $0.name) } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { workout in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try library.softDelete(workout)
                    onDeleted()
                } catch {
                    ErrorLogging.log(error, action: "Deleting workout", category: "workouts")
                    onFailure(error)
                }
            }
        } message: { _ in
            Text(WorkoutMessages.deleteMessage)
        }
    }
}

extension View {
    func workoutDeletionAlert(
        _ pending: Binding<Workout?>, library: WorkoutLibrary,
        onFailure: @escaping (Error) -> Void, onDeleted: @escaping () -> Void = {}
    ) -> some View {
        modifier(WorkoutDeletionAlert(pending: pending, library: library, onFailure: onFailure, onDeleted: onDeleted))
    }
}

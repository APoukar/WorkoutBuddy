import Foundation
import SwiftData

/// History queries and the delete of a saved session. History is every session with status `completed` or
/// `endedEarly`; one still in progress (running, or finished and waiting for Save) never belongs to it.
@MainActor
struct HistoryLibrary {
    let context: ModelContext

    /// The one definition of "finished": status `completed` or `endedEarly`, oldest start first.
    /// Used by `HistoryView`'s `@Query` and by `finishedSessions()`.
    static func finishedDescriptor() -> FetchDescriptor<WorkoutSession> {
        let completed = SessionStatus.completed.rawValue
        let endedEarly = SessionStatus.endedEarly.rawValue
        return FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.statusRaw == completed || $0.statusRaw == endedEarly },
            sortBy: [SortDescriptor(\.startedAt)])
    }

    func finishedSessions() throws -> [WorkoutSession] {
        try context.fetch(Self.finishedDescriptor())
    }

    /// Lookup by ID. Deliberately has no status filter, and sessions of soft-deleted templates are found too.
    func session(id: UUID) -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            ErrorLogging.log(error, action: "Look up session", category: "history")
            return nil
        }
    }

    /// Deletes a saved session; the cascade removes its exercises and sets. Sessions aren't soft-deleted.
    /// Does nothing on a session still in progress (those go through `SessionLibrary.discard`). Saved at once;
    /// a failed save is rolled back and rethrown. Nothing is reported to `SessionEffects`: no notification
    /// or Live Activity belongs to a saved session.
    func delete(_ session: WorkoutSession) throws {
        guard session.status == .completed || session.status == .endedEarly else { return }
        // Phase 6: recalculate the personal records here.
        context.delete(session)
        do { try context.save() } catch { context.rollback(); throw error }
    }
}

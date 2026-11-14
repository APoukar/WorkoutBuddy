import Foundation
import SwiftData
import Testing

@testable import WorkoutBuddy

@MainActor
struct HistoryPreviewDataTests {
    @Test func buildsFinishedSessionsInOrder() throws {
        let preview = HistoryPreviewData.make()
        let library = HistoryLibrary(context: preview.container.mainContext)
        let finished = try library.finishedSessions()
        #expect(finished.map(\.id) == preview.sessionIDs)
        #expect(library.session(id: preview.endedEarlyID)?.status == .endedEarly)
        #expect(library.session(id: preview.completedID)?.status == .completed)
        // Two sessions on the day before yesterday... on one day.
        let calendar = Calendar.current
        let days = finished.map { calendar.startOfDay(for: $0.startedAt) }
        #expect(finished.count == 5)
        #expect(Set(days).count == 4)
    }

    @Test func deletedTemplateAndArchivedExerciseStillShowNames() throws {
        let preview = HistoryPreviewData.make()
        let context = preview.container.mainContext
        let library = HistoryLibrary(context: context)
        let bodyweight = try #require(library.session(id: preview.bodyweightID))
        #expect(bodyweight.workout?.isSoftDeleted == true)
        let endedEarly = try #require(library.session(id: preview.endedEarlyID))
        let sessions = SessionLibrary(context: context)
        let content = SessionDetailContent(
            sessions.snapshot(of: endedEarly), workoutName: endedEarly.workout?.name,
            exerciseNames: sessions.exerciseNames(of: endedEarly), locale: Locale(identifier: "en_US"))
        #expect(content.workoutName == "Legs")
        #expect(content.endedEarlyText == "Ended early")
        #expect(content.sections.map(\.name) == ["Back Squat", "Leg Press"])
        let statuses = content.sections.flatMap(\.rows).map(\.status)
        #expect(statuses == [.done, .done, .skipped, .notPerformed])
        #expect(content.sections[0].rows[1].plannedText != nil)
    }
}

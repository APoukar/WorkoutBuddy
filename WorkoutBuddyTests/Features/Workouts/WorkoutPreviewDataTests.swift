import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

/// The preview data is compiled in every configuration, so it is checked like any other code.
@MainActor
struct WorkoutPreviewDataTests {
    @Test func buildsTheDocumentedTemplates() throws {
        let container = WorkoutPreviewData.container()
        let library = WorkoutLibrary(context: container.mainContext)

        let push = try #require(WorkoutPreviewData.workout(named: "Push Day", in: container))
        #expect(push.orderedExercises.compactMap { $0.exercise?.name } == ["Bench Press", "Overhead Press"])
        #expect(library.canStart(push))
        #expect(library.lastPerformed(push) == nil)

        let legs = try #require(WorkoutPreviewData.workout(named: "Legs", in: container))
        #expect(legs.orderedExercises.count == 2)
        #expect(library.lastPerformed(legs) != nil)

        let core = try #require(WorkoutPreviewData.workout(named: "Core", in: container))
        #expect(core.orderedExercises.flatMap(\.sets).contains { $0.kg == 0 })

        let empty = try #require(WorkoutPreviewData.workout(named: "Empty", in: container))
        #expect(empty.exercises.isEmpty)
        #expect(!library.canStart(empty))
    }
}

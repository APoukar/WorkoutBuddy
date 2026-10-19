import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

struct ExerciseSeedTests {
    @Test func seedingEmptyStoreInsertsAll43() throws {
        let tc = try TestContainer()
        let inserted = try ExerciseSeed.seedIfNeeded(in: tc.context)
        let all = try tc.context.fetch(FetchDescriptor<Exercise>())
        #expect(inserted)
        #expect(ExerciseSeed.entries.count == 43)
        #expect(all.count == 43)
        #expect(all.allSatisfy { !$0.isCustom && !$0.isArchived })
        #expect(Set(all.map { "\($0.name)|\($0.muscleGroupRaw)" })
            == Set(ExerciseSeed.entries.map { "\($0.name)|\($0.muscleGroup.rawValue)" }))
    }

    @Test func secondCallInsertsNothing() throws {
        let tc = try TestContainer()
        try ExerciseSeed.seedIfNeeded(in: tc.context)
        let inserted = try ExerciseSeed.seedIfNeeded(in: tc.context)
        #expect(!inserted)
        #expect(try tc.context.fetchCount(FetchDescriptor<Exercise>()) == 43)
    }

    @Test func archivedOnlyStoreIsNotSeeded() throws {
        let tc = try TestContainer()
        tc.context.insert(Exercise(name: "Old", muscleGroup: .core, isArchived: true))
        try tc.context.save()
        let inserted = try ExerciseSeed.seedIfNeeded(in: tc.context)
        #expect(!inserted)
        #expect(try tc.context.fetchCount(FetchDescriptor<Exercise>()) == 1)
    }

    @Test func seedNamesAreUniqueCaseInsensitively() {
        let names = ExerciseSeed.entries.map { $0.name.lowercased() }
        #expect(Set(names).count == names.count)
    }

    @Test func everyMuscleGroupHasAnEntry() {
        for group in MuscleGroup.allCases {
            #expect(ExerciseSeed.entries.contains { $0.muscleGroup == group })
        }
    }

    @Test func entryCountPerMuscleGroupMatchesPlan() {
        let expected: [MuscleGroup: Int] = [
            .chest: 6, .back: 6, .shoulders: 6, .biceps: 4, .triceps: 4,
            .legs: 7, .glutes: 3, .core: 4, .fullBody: 3,
        ]
        for group in MuscleGroup.allCases {
            #expect(ExerciseSeed.entries.filter { $0.muscleGroup == group }.count == expected[group])
        }
    }
}

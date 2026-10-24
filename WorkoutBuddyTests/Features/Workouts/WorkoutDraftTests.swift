import Foundation
import SwiftUI
import Testing
@testable import WorkoutBuddy

struct WorkoutDraftTests {
    private let set1 = SetValues(reps: 10, kg: 60, restSeconds: 90)
    private let set2 = SetValues(reps: 8, kg: 70, restSeconds: 120)

    /// A draft with `count` exercises, each with one set.
    private func draft(exerciseCount count: Int) -> WorkoutDraft {
        var draft = WorkoutDraft(name: "Push")
        for _ in 0..<count {
            draft.addExercise(exerciseID: UUID(), firstSet: set1)
        }
        return draft
    }

    private func ids(_ draft: WorkoutDraft) -> [UUID] { draft.exercises.map(\.id) }

    // MARK: Adding

    @Test func addExerciseAppendsWithOneSet() {
        var draft = WorkoutDraft()
        let first = UUID()
        let second = UUID()
        draft.addExercise(exerciseID: first, firstSet: set1)
        draft.addExercise(exerciseID: second, firstSet: set2)
        #expect(draft.exercises.map(\.exerciseID) == [first, second])
        #expect(draft.exercises[0].sets.map(\.values) == [set1])
        #expect(draft.exercises[1].sets.map(\.values) == [set2])
        #expect(draft.contains(exerciseID: first))
        #expect(!draft.contains(exerciseID: UUID()))
    }

    @Test func addingTheSameExerciseTwiceIsIgnored() {
        var draft = WorkoutDraft()
        let exerciseID = UUID()
        draft.addExercise(exerciseID: exerciseID, firstSet: set1)
        let before = draft
        draft.addExercise(exerciseID: exerciseID, firstSet: set2)
        #expect(draft == before)
    }

    // MARK: Removing and moving exercises

    @Test func removeExercisesAtOffsets() {
        var draft = draft(exerciseCount: 5)
        let original = ids(draft)
        draft.removeExercises(atOffsets: IndexSet([1, 3]))
        #expect(ids(draft) == [original[0], original[2], original[4]])
    }

    @Test func removeExercisesIgnoresOutOfRangeOffsets() {
        var draft = draft(exerciseCount: 2)
        let original = ids(draft)
        draft.removeExercises(atOffsets: IndexSet([5, 9]))
        #expect(ids(draft) == original)
        draft.removeExercises(atOffsets: IndexSet([0, 7]))
        #expect(ids(draft) == [original[1]])
    }

    @Test func moveExercisesDownMatchesSwiftUI() {
        var draft = draft(exerciseCount: 4)
        let o = ids(draft)
        // Row 0 dropped between rows 2 and 3 (destination is an index before the move).
        draft.moveExercises(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        #expect(ids(draft) == [o[1], o[2], o[0], o[3]])
    }

    @Test func moveExercisesUpMatchesSwiftUI() {
        var draft = draft(exerciseCount: 4)
        let o = ids(draft)
        draft.moveExercises(fromOffsets: IndexSet(integer: 2), toOffset: 1)
        #expect(ids(draft) == [o[0], o[2], o[1], o[3]])
    }

    @Test func moveExercisesToStartAndEnd() {
        var draft = draft(exerciseCount: 4)
        let o = ids(draft)
        draft.moveExercises(fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(ids(draft) == [o[3], o[0], o[1], o[2]])
        draft.moveExercises(fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(ids(draft) == [o[0], o[1], o[2], o[3]])
    }

    @Test func moveExercisesToOwnPositionChangesNothing() {
        var draft = draft(exerciseCount: 3)
        let o = ids(draft)
        draft.moveExercises(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(ids(draft) == o)
        draft.moveExercises(fromOffsets: IndexSet(integer: 1), toOffset: 2)
        #expect(ids(draft) == o)
    }

    @Test func moveSeveralExercisesKeepsTheirRelativeOrder() {
        var draft = draft(exerciseCount: 5)
        let o = ids(draft)
        draft.moveExercises(fromOffsets: IndexSet([0, 2]), toOffset: 5)
        #expect(ids(draft) == [o[1], o[3], o[4], o[0], o[2]])

        var other = self.draft(exerciseCount: 5)
        let p = ids(other)
        other.moveExercises(fromOffsets: IndexSet([3, 4]), toOffset: 1)
        #expect(ids(other) == [p[0], p[3], p[4], p[1], p[2]])

        var mixed = self.draft(exerciseCount: 5)
        let q = ids(mixed)
        // One row from before the destination, one from after.
        mixed.moveExercises(fromOffsets: IndexSet([0, 4]), toOffset: 2)
        #expect(ids(mixed) == [q[1], q[0], q[4], q[2], q[3]])
    }

    @Test func moveExercisesIgnoresInvalidInput() {
        var draft = draft(exerciseCount: 3)
        let o = ids(draft)
        draft.moveExercises(fromOffsets: IndexSet(integer: 7), toOffset: 0)
        #expect(ids(draft) == o)
        draft.moveExercises(fromOffsets: IndexSet(), toOffset: 0)
        #expect(ids(draft) == o)
        draft.moveExercises(fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(ids(draft) == [o[1], o[2], o[0]])
    }

    /// The hand-written offset helpers must behave exactly like SwiftUI's `Array` helpers, which
    /// `onDelete` and `onMove` are shaped for. Compares every subset of offsets (and every
    /// destination from 0 to count) on arrays of 4 and 5 items.
    @Test func offsetHelpersMatchSwiftUI() {
        for count in 4...5 {
            let base = draft(exerciseCount: count)
            let reference = ids(base)
            for mask in 0..<(1 << count) {
                let offsets = IndexSet((0..<count).filter { mask & (1 << $0) != 0 })

                var removed = base
                removed.removeExercises(atOffsets: offsets)
                var expectedRemoved = reference
                expectedRemoved.remove(atOffsets: offsets)
                #expect(ids(removed) == expectedRemoved, "remove \(Array(offsets)) of \(count)")

                for destination in 0...count {
                    var moved = base
                    moved.moveExercises(fromOffsets: offsets, toOffset: destination)
                    var expectedMoved = reference
                    expectedMoved.move(fromOffsets: offsets, toOffset: destination)
                    #expect(ids(moved) == expectedMoved,
                            "move \(Array(offsets)) to \(destination) of \(count)")
                }
            }
        }
    }

    @Test func moveExerciseByOffset() {
        var draft = draft(exerciseCount: 3)
        let o = ids(draft)
        draft.moveExercise(id: o[1], by: 1)
        #expect(ids(draft) == [o[0], o[2], o[1]])
        draft.moveExercise(id: o[1], by: -2)
        #expect(ids(draft) == [o[1], o[0], o[2]])
    }

    @Test func moveExerciseByOffsetClampsAtTheEnds() {
        var draft = draft(exerciseCount: 3)
        let o = ids(draft)
        draft.moveExercise(id: o[0], by: -1)
        #expect(ids(draft) == o)
        draft.moveExercise(id: o[2], by: 1)
        #expect(ids(draft) == o)
        draft.moveExercise(id: o[0], by: 10)
        #expect(ids(draft) == [o[1], o[2], o[0]])
        draft.moveExercise(id: o[0], by: -10)
        #expect(ids(draft) == o)
    }

    @Test func unknownExerciseIDsChangeNothing() {
        var draft = draft(exerciseCount: 2)
        let before = draft
        let unknown = UUID()
        draft.moveExercise(id: unknown, by: 1)
        draft.addSet(toExercise: unknown)
        draft.removeSet(UUID(), fromExercise: unknown)
        draft.setValues(set2, ofSet: UUID(), inExercise: unknown)
        #expect(draft == before)
        #expect(draft.sets(ofExercise: unknown).isEmpty)
        #expect(draft.values(ofSet: UUID(), inExercise: unknown) == nil)
    }

    // MARK: Sets

    @Test func addSetCopiesTheLastSetWithANewID() {
        var draft = draft(exerciseCount: 2)
        let id = draft.exercises[0].id
        draft.setValues(set2, ofSet: draft.exercises[0].sets[0].id, inExercise: id)
        draft.addSet(toExercise: id)
        draft.addSet(toExercise: id)
        let sets = draft.sets(ofExercise: id)
        #expect(sets.map(\.values) == [set2, set2, set2])
        #expect(Set(sets.map(\.id)).count == 3)
        #expect(draft.exercises[1].sets.count == 1)
    }

    @Test func addSetCopiesOnlyTheLastSet() {
        var draft = draft(exerciseCount: 1)
        let id = draft.exercises[0].id
        draft.addSet(toExercise: id)
        let secondID = draft.exercises[0].sets[1].id
        draft.setValues(set2, ofSet: secondID, inExercise: id)
        draft.addSet(toExercise: id)
        #expect(draft.sets(ofExercise: id).map(\.values) == [set1, set2, set2])
    }

    @Test func addSetDoesNothingWithoutASetToCopy() {
        var draft = WorkoutDraft(exercises: [DraftExercise(exerciseID: UUID(), sets: [])])
        let before = draft
        draft.addSet(toExercise: draft.exercises[0].id)
        #expect(draft == before)
    }

    @Test func removeSetRemovesTheMatchingSet() {
        var draft = draft(exerciseCount: 1)
        let id = draft.exercises[0].id
        draft.addSet(toExercise: id)
        draft.addSet(toExercise: id)
        let setIDs = draft.sets(ofExercise: id).map(\.id)
        draft.removeSet(setIDs[1], fromExercise: id)
        #expect(draft.sets(ofExercise: id).map(\.id) == [setIDs[0], setIDs[2]])
    }

    @Test func removeSetKeepsTheLastSet() {
        var draft = draft(exerciseCount: 1)
        let id = draft.exercises[0].id
        let onlySet = draft.exercises[0].sets[0].id
        draft.removeSet(onlySet, fromExercise: id)
        #expect(draft.sets(ofExercise: id).map(\.id) == [onlySet])

        draft.addSet(toExercise: id)
        let second = draft.exercises[0].sets[1].id
        draft.removeSet(onlySet, fromExercise: id)
        draft.removeSet(second, fromExercise: id)
        #expect(draft.sets(ofExercise: id).map(\.id) == [second])
    }

    @Test func removeSetWithUnknownSetIDChangesNothing() {
        var draft = draft(exerciseCount: 1)
        let id = draft.exercises[0].id
        draft.addSet(toExercise: id)
        let before = draft
        draft.removeSet(UUID(), fromExercise: id)
        #expect(draft == before)
    }

    @Test func valuesByIDReadAndWrite() {
        var draft = draft(exerciseCount: 2)
        let id = draft.exercises[1].id
        draft.addSet(toExercise: id)
        let setIDs = draft.sets(ofExercise: id).map(\.id)
        #expect(draft.values(ofSet: setIDs[0], inExercise: id) == set1)

        draft.setValues(set2, ofSet: setIDs[1], inExercise: id)
        #expect(draft.values(ofSet: setIDs[1], inExercise: id) == set2)
        #expect(draft.values(ofSet: setIDs[0], inExercise: id) == set1)
        #expect(draft.exercises[0].sets.map(\.values) == [set1])
    }

    @Test func setHelpersWithUnknownSetIDChangeNothing() {
        var draft = draft(exerciseCount: 1)
        let id = draft.exercises[0].id
        let before = draft
        draft.setValues(set2, ofSet: UUID(), inExercise: id)
        #expect(draft == before)
        #expect(draft.values(ofSet: UUID(), inExercise: id) == nil)
        // A set ID of another exercise is not found under this one.
        draft.addExercise(exerciseID: UUID(), firstSet: set2)
        let otherSet = draft.exercises[1].sets[0].id
        #expect(draft.values(ofSet: otherSet, inExercise: id) == nil)
    }

    // MARK: Issues

    @Test func validDraftHasNoIssues() {
        #expect(draft(exerciseCount: 2).issues.isEmpty)
    }

    @Test func emptyNameIssue() {
        var draft = draft(exerciseCount: 1)
        draft.name = ""
        #expect(draft.issues == [.emptyName])
        draft.name = "  \n "
        #expect(draft.issues == [.emptyName])
    }

    @Test func noExercisesIssue() {
        #expect(WorkoutDraft(name: "Push").issues == [.noExercises])
    }

    @Test func exerciseWithoutSetsIssue() {
        let draft = WorkoutDraft(name: "Push", exercises: [DraftExercise(exerciseID: UUID(), sets: [])])
        #expect(draft.issues == [.exerciseWithoutSets])
    }

    @Test func issuesComeInFixedOrder() {
        #expect(WorkoutDraft().issues == [.emptyName, .noExercises])
        let draft = WorkoutDraft(name: " ", exercises: [DraftExercise(exerciseID: UUID(), sets: [])])
        #expect(draft.issues == [.emptyName, .exerciseWithoutSets])
    }
}

import Foundation
import SwiftData
import Testing
@testable import WorkoutBuddy

@MainActor
struct WorkoutLibraryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let t1 = Date(timeIntervalSince1970: 2_000_000)
    private let setA = SetValues(reps: 10, kg: 60, restSeconds: 90)
    private let setB = SetValues(reps: 8, kg: 70, restSeconds: 120)

    private func makeExercise(_ name: String, in context: ModelContext) throws -> Exercise {
        let exercise = Exercise(name: name, muscleGroup: .chest)
        context.insert(exercise)
        try context.save()
        return exercise
    }

    private func draft(_ name: String, _ exercises: [(Exercise, [SetValues])]) -> WorkoutDraft {
        WorkoutDraft(
            name: name,
            exercises: exercises.map { exercise, sets in
                DraftExercise(exerciseID: exercise.id, sets: sets.map { DraftSet(values: $0) })
            })
    }

    private func allRows(_ context: ModelContext) throws -> [WorkoutExercise] {
        try context.fetch(FetchDescriptor<WorkoutExercise>())
    }

    private func allSets(_ context: ModelContext) throws -> [PlannedSet] {
        try context.fetch(FetchDescriptor<PlannedSet>())
    }

    // MARK: Validation

    @Test func validateRejectsEmptyAndDuplicateNamesCaseInsensitively() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        #expect(lib.validate(name: "") == .empty)
        #expect(lib.validate(name: "  \n") == .empty)
        #expect(lib.validate(name: "push") == .duplicate)
        #expect(lib.validate(name: "  PUSH ") == .duplicate)
        #expect(lib.validate(name: "Pull") == nil)
    }

    @Test func saveRejectsDuplicateAndEmptyNames() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        #expect(throws: NameError.duplicate) {
            try lib.save(draft("push", [(bench, [setA])]), to: nil, now: t1)
        }
        #expect(throws: NameError.empty) {
            try lib.save(draft("   ", [(bench, [setA])]), to: nil, now: t1)
        }
        #expect(!tc.context.hasChanges)
        #expect(try tc.context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    @Test func softDeletedNameCanBeReused() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let old = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        try lib.softDelete(old)
        #expect(lib.validate(name: "Push") == nil)
        let new = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t1)
        #expect(new.id != old.id)
    }

    @Test func renamingToOwnNameInAnotherCaseIsAllowed() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        #expect(lib.validate(name: "push", excluding: workout) == nil)
        var edited = lib.draft(for: workout)
        edited.name = "push"
        try lib.save(edited, to: workout, now: t1)
        #expect(workout.name == "push")
        // But another template still can't take it.
        let pull = try lib.save(draft("Pull", [(bench, [setA])]), to: nil, now: t1)
        var clash = lib.draft(for: pull)
        clash.name = "PUSH"
        #expect(throws: NameError.duplicate) { try lib.save(clash, to: pull, now: t1) }
        #expect(pull.name == "Pull")
        #expect(!tc.context.hasChanges)
    }

    // MARK: Creating

    @Test func createStoresNameOrderValuesAndDates() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let press = try makeExercise("Press", in: tc.context)
        let workout = try lib.save(
            draft("  Push  ", [(bench, [setA, setB]), (press, [setB])]), to: nil, now: t0)

        #expect(workout.name == "Push")
        #expect(workout.createdAt == t0 && workout.updatedAt == t0)
        #expect(!workout.isSoftDeleted)
        #expect(!tc.context.hasChanges)

        // Read back through a fresh context.
        let fresh = ModelContext(tc.container)
        let fetched = try #require(WorkoutLibrary(context: fresh).workout(id: workout.id))
        #expect(fetched.createdAt == t0 && fetched.updatedAt == t0)
        let rows = fetched.orderedExercises
        #expect(rows.map(\.order) == [0, 1])
        #expect(rows.compactMap { $0.exercise?.name } == ["Bench", "Press"])
        #expect(rows[0].orderedSets.map(\.order) == [0, 1])
        let values = rows[0].orderedSets.map { SetValues(reps: $0.reps, kg: $0.kg, restSeconds: $0.restSeconds) }
        #expect(values == [setA, setB])
        #expect(rows[1].orderedSets.count == 1)
    }

    @Test func draftForNilIsEmptyAndRoundTripsAnExistingTemplate() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        #expect(lib.draft(for: nil) == WorkoutDraft())
        let bench = try makeExercise("Bench", in: tc.context)
        let press = try makeExercise("Press", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA, setB]), (press, [setB])]), to: nil, now: t0)
        let copy = lib.draft(for: workout)
        #expect(copy.name == "Push")
        #expect(copy.exercises.map(\.exerciseID) == [bench.id, press.id])
        #expect(copy.exercises.map(\.id) == workout.orderedExercises.map(\.id))
        #expect(copy.exercises[0].sets.map(\.id) == workout.orderedExercises[0].orderedSets.map(\.id))
        #expect(copy.exercises[0].sets.map(\.values) == [setA, setB])
        #expect(copy.issues.isEmpty)
    }

    @Test func draftSkipsRowsWithoutAnExercise() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)
        let orphan = WorkoutExercise(order: 1, exercise: nil)
        tc.context.insert(orphan)
        orphan.workout = workout
        try tc.context.save()
        #expect(lib.draft(for: workout).exercises.map(\.exerciseID) == [bench.id])
    }

    // MARK: Editing

    @Test func editKeepsRowAndSetIDsOfUnchangedRows() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let press = try makeExercise("Press", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA, setB]), (press, [setA])]), to: nil, now: t0)
        let rowIDs = workout.orderedExercises.map(\.id)
        let setIDs = workout.orderedExercises[0].orderedSets.map(\.id)

        var edited = lib.draft(for: workout)
        edited.setValues(SetValues(reps: 12, kg: 62.5, restSeconds: 60), ofSet: setIDs[0], inExercise: rowIDs[0])
        let same = try lib.save(edited, to: workout, now: t1)

        #expect(same === workout)
        #expect(workout.orderedExercises.map(\.id) == rowIDs)
        #expect(workout.orderedExercises[0].orderedSets.map(\.id) == setIDs)
        #expect(workout.orderedExercises[0].orderedSets[0].reps == 12)
        #expect(workout.orderedExercises[0].orderedSets[0].kg == 62.5)
        #expect(workout.orderedExercises[0].orderedSets[1].reps == setB.reps)
        #expect(workout.updatedAt == t1 && workout.createdAt == t0)
        #expect(try allRows(tc.context).count == 2)
        #expect(try allSets(tc.context).count == 3)
    }

    @Test func editReordersInsertsAndRemovesInOneSave() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let a = try makeExercise("A", in: tc.context)
        let b = try makeExercise("B", in: tc.context)
        let c = try makeExercise("C", in: tc.context)
        let d = try makeExercise("D", in: tc.context)
        let workout = try lib.save(draft("Mix", [(a, [setA]), (b, [setA, setB]), (c, [setB])]), to: nil, now: t0)
        let original = workout.orderedExercises
        let (rowA, rowB, rowC) = (original[0].id, original[1].id, original[2].id)
        let removedSetIDs = original[1].orderedSets.map(\.id)

        var edited = lib.draft(for: workout)
        edited.removeExercises(atOffsets: IndexSet(integer: 1))      // drop B and its 2 sets
        edited.moveExercise(id: rowC, by: -1)                         // C before A
        edited.addExercise(exerciseID: d.id, firstSet: setB)           // new D at the end
        let newRowID = try #require(edited.exercises.last?.id)
        edited.addSet(toExercise: rowA)                                 // A gets a second set
        let newSetID = try #require(edited.exercises[1].sets.last?.id)
        try lib.save(edited, to: workout, now: t1)

        let rows = workout.orderedExercises
        #expect(rows.map(\.id) == [rowC, rowA, newRowID])
        #expect(rows.map(\.order) == [0, 1, 2])
        #expect(rows.compactMap { $0.exercise?.name } == ["C", "A", "D"])
        #expect(rows[1].orderedSets.count == 2)
        #expect(rows[1].orderedSets.last?.id == newSetID)
        #expect(rows[1].orderedSets.map(\.order) == [0, 1])

        // Removed rows and their sets are really gone from the store, not just from the accessor.
        let storedRows = try allRows(tc.context)
        #expect(Set(storedRows.map(\.id)) == [rowC, rowA, newRowID])
        #expect(!storedRows.contains { $0.id == rowB })
        let storedSets = try allSets(tc.context)
        #expect(storedSets.count == 1 + 2 + 1)
        #expect(Set(storedSets.map(\.id)).isDisjoint(with: removedSetIDs))
        #expect(!tc.context.hasChanges)

        // The same result when read back through a fresh context.
        let fresh = ModelContext(tc.container)
        let fetched = try #require(WorkoutLibrary(context: fresh).workout(id: workout.id))
        let freshRows = fetched.orderedExercises
        #expect(freshRows.map(\.id) == [rowC, rowA, newRowID])
        #expect(freshRows.map(\.order) == [0, 1, 2])
        #expect(freshRows.compactMap { $0.exercise?.id } == [c.id, a.id, d.id])
        #expect(freshRows.map { $0.orderedSets.count } == [1, 2, 1])
        #expect(freshRows.map { $0.orderedSets.map(\.order) } == [[0], [0, 1], [0]])
        #expect(freshRows[1].orderedSets.last?.id == newSetID)
    }

    @Test func editRemovesASetFromAKeptRow() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let a = try makeExercise("A", in: tc.context)
        let workout = try lib.save(draft("Solo", [(a, [setA, setB, setA])]), to: nil, now: t0)
        let row = workout.orderedExercises[0]
        let ids = row.orderedSets.map(\.id)
        var edited = lib.draft(for: workout)
        edited.removeSet(ids[0], fromExercise: row.id)
        try lib.save(edited, to: workout, now: t1)
        #expect(row.orderedSets.map(\.id) == [ids[1], ids[2]])
        #expect(row.orderedSets.map(\.order) == [0, 1])
        #expect(try allSets(tc.context).map(\.id).sorted { $0.uuidString < $1.uuidString }
            == [ids[1], ids[2]].sorted { $0.uuidString < $1.uuidString })
    }

    @Test func editCanReplaceAnExerciseInARowThatKeepsItsID() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let a = try makeExercise("A", in: tc.context)
        let b = try makeExercise("B", in: tc.context)
        let workout = try lib.save(draft("Solo", [(a, [setA])]), to: nil, now: t0)
        var edited = lib.draft(for: workout)
        edited.exercises[0].exerciseID = b.id
        try lib.save(edited, to: workout, now: t1)
        #expect(workout.orderedExercises[0].exercise?.id == b.id)
    }

    // MARK: Rejected saves

    @Test func invalidDraftThrowsAndChangesNothing() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)

        var noExercises = lib.draft(for: workout)
        noExercises.name = "Renamed"
        noExercises.exercises = []
        #expect(throws: WorkoutSaveError.invalid) { try lib.save(noExercises, to: workout, now: t1) }

        var noSets = lib.draft(for: workout)
        noSets.name = "Renamed"
        noSets.exercises[0].sets = []
        #expect(throws: WorkoutSaveError.invalid) { try lib.save(noSets, to: workout, now: t1) }

        #expect(throws: WorkoutSaveError.invalid) { try lib.save(WorkoutDraft(name: "New"), to: nil, now: t1) }

        #expect(!tc.context.hasChanges)
        #expect(workout.name == "Push" && workout.updatedAt == t0)
        #expect(workout.orderedExercises.count == 1)
        #expect(try tc.context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    private enum Repeat: CaseIterable { case exercise, rowID, setID }

    private func applyRepeat(_ kind: Repeat, to draft: inout WorkoutDraft, spare: Exercise) {
        switch kind {
        case .exercise:
            // A second row for an exercise that is already in the draft.
            draft.exercises.append(
                DraftExercise(exerciseID: draft.exercises[0].exerciseID, sets: [DraftSet(values: setB)]))
        case .rowID:
            draft.exercises.append(
                DraftExercise(id: draft.exercises[0].id, exerciseID: spare.id, sets: [DraftSet(values: setB)]))
        case .setID:
            let id = draft.exercises[0].sets[0].id
            draft.exercises[0].sets.append(DraftSet(id: id, values: setB))
        }
    }

    @Test func repeatsInAnExistingTemplateThrowAndChangeNothing() throws {
        for kind in Repeat.allCases {
            let tc = try TestContainer()
            let lib = WorkoutLibrary(context: tc.context)
            let bench = try makeExercise("Bench", in: tc.context)
            let spare = try makeExercise("Spare", in: tc.context)
            let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)

            var edited = lib.draft(for: workout)
            edited.name = "Renamed"
            applyRepeat(kind, to: &edited, spare: spare)
            #expect(throws: WorkoutSaveError.invalid, "\(kind)") { try lib.save(edited, to: workout, now: t1) }

            #expect(!tc.context.hasChanges, "\(kind)")
            #expect(workout.name == "Push" && workout.updatedAt == t0, "\(kind)")
            #expect(workout.orderedExercises.count == 1, "\(kind)")
            #expect(workout.orderedExercises[0].orderedSets.count == 1, "\(kind)")
            #expect(try allRows(tc.context).count == 1, "\(kind)")
            #expect(try allSets(tc.context).count == 1, "\(kind)")
        }
    }

    @Test func repeatsInANewTemplateThrowAndChangeNothing() throws {
        for kind in Repeat.allCases {
            let tc = try TestContainer()
            let lib = WorkoutLibrary(context: tc.context)
            let bench = try makeExercise("Bench", in: tc.context)
            let spare = try makeExercise("Spare", in: tc.context)

            var fresh = draft("New", [(bench, [setA])])
            applyRepeat(kind, to: &fresh, spare: spare)
            #expect(throws: WorkoutSaveError.invalid, "\(kind)") { try lib.save(fresh, to: nil, now: t1) }

            #expect(!tc.context.hasChanges, "\(kind)")
            #expect(try tc.context.fetchCount(FetchDescriptor<Workout>()) == 0, "\(kind)")
            #expect(try allRows(tc.context).isEmpty, "\(kind)")
            #expect(try allSets(tc.context).isEmpty, "\(kind)")
        }
    }

    @Test func missingExerciseThrowsAndChangesNothing() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)

        var edited = lib.draft(for: workout)
        edited.name = "Renamed"
        edited.exercises.append(DraftExercise(exerciseID: UUID(), sets: [DraftSet(values: setB)]))
        #expect(throws: WorkoutSaveError.missingExercise) { try lib.save(edited, to: workout, now: t1) }

        #expect(!tc.context.hasChanges)
        #expect(workout.name == "Push" && workout.updatedAt == t0)
        #expect(workout.orderedExercises.count == 1)
        #expect(try allRows(tc.context).count == 1)

        let newDraft = WorkoutDraft(
            name: "Fresh", exercises: [DraftExercise(exerciseID: UUID(), sets: [DraftSet(values: setA)])])
        #expect(throws: WorkoutSaveError.missingExercise) { try lib.save(newDraft, to: nil, now: t1) }
        #expect(!tc.context.hasChanges)
        #expect(try tc.context.fetchCount(FetchDescriptor<Workout>()) == 1)
    }

    @Test func archivedExerciseThrowsAndChangesNothing() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let old = try makeExercise("Old", in: tc.context)
        let workout = try lib.save(draft("Push", [(bench, [setA])]), to: nil, now: t0)

        var edited = lib.draft(for: workout)
        edited.name = "Renamed"
        edited.exercises.append(DraftExercise(exerciseID: old.id, sets: [DraftSet(values: setB)]))
        try ExerciseLibrary(context: tc.context).archive(old)

        #expect(throws: WorkoutSaveError.missingExercise) { try lib.save(edited, to: workout, now: t1) }
        #expect(!tc.context.hasChanges)
        #expect(workout.name == "Push" && workout.updatedAt == t0)
        #expect(workout.orderedExercises.count == 1)
        #expect(try allRows(tc.context).count == 1)
        #expect(try allSets(tc.context).count == 1)
    }

    // MARK: Clamping

    @Test func outOfRangeValuesAreStoredClamped() throws {
        let tc = try TestContainer()
        let lib = WorkoutLibrary(context: tc.context)
        let bench = try makeExercise("Bench", in: tc.context)
        let wild = [
            SetValues(reps: 0, kg: -5, restSeconds: -1),
            SetValues(reps: 9999, kg: 22.3, restSeconds: 99999),
            SetValues(reps: 5, kg: .nan, restSeconds: 30),
        ]
        let workout = try lib.save(draft("Wild", [(bench, wild)]), to: nil, now: t0)
        let sets = workout.orderedExercises[0].orderedSets
        #expect(sets.map(\.reps) == [AppSettings.repsRange.lowerBound, AppSettings.repsRange.upperBound, 5])
        #expect(sets.map(\.kg) == [AppSettings.kgRange.lowerBound, 22.5, AppSettings.kgRange.lowerBound])
        #expect(sets.map(\.restSeconds) == [AppSettings.restRange.lowerBound, AppSettings.restRange.upperBound, 30])
    }

    // MARK: Sessions

    @Test func editingATemplateLeavesPastSessionsAlone() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        let press = try makeExercise("Press", in: ctx)
        let workout = try lib.save(draft("Push", [(bench, [setA, setB]), (press, [setB])]), to: nil, now: t0)

        // A session that copied the template's planned numbers.
        let session = WorkoutSession(workout: workout, startedAt: t0, endedAt: t0, status: .completed)
        ctx.insert(session)
        for (index, row) in workout.orderedExercises.enumerated() {
            let sessionRow = SessionExercise(order: index, exercise: row.exercise)
            ctx.insert(sessionRow)
            sessionRow.session = session
            for (setIndex, planned) in row.orderedSets.enumerated() {
                let set = SessionSet(
                    order: setIndex, plannedReps: planned.reps, plannedKg: planned.kg,
                    plannedRestSeconds: planned.restSeconds)
                ctx.insert(set)
                set.sessionExercise = sessionRow
            }
        }
        try ctx.save()

        // Change values in the template and remove an exercise.
        var edited = lib.draft(for: workout)
        let firstRow = edited.exercises[0]
        edited.setValues(SetValues(reps: 1, kg: 5, restSeconds: 10), ofSet: firstRow.sets[0].id, inExercise: firstRow.id)
        edited.removeExercises(atOffsets: IndexSet(integer: 1))
        try lib.save(edited, to: workout, now: t1)

        #expect(workout.orderedExercises.count == 1)
        #expect(session.workout === workout)
        let rows = session.orderedExercises
        #expect(rows.compactMap { $0.exercise?.id } == [bench.id, press.id])
        #expect(rows.map { $0.orderedSets.count } == [2, 1])
        let first = rows[0].orderedSets[0]
        #expect(first.plannedReps == setA.reps && first.plannedKg == setA.kg && first.plannedRestSeconds == setA.restSeconds)
        let last = rows[1].orderedSets[0]
        #expect(last.plannedReps == setB.reps && last.plannedKg == setB.kg && last.plannedRestSeconds == setB.restSeconds)
        #expect(try ctx.fetchCount(FetchDescriptor<SessionSet>()) == 3)
        #expect(try ctx.fetchCount(FetchDescriptor<SessionExercise>()) == 2)
    }

    // MARK: Soft delete

    @Test func softDeleteHidesFromActiveFetchButKeepsLookupAndSessions() throws {
        let tc = try TestContainer()
        let ctx = tc.context
        let lib = WorkoutLibrary(context: ctx)
        let bench = try makeExercise("Bench", in: ctx)
        let workout = try lib.save(draft("Push", [(bench, [setA, setB])]), to: nil, now: t0)
        let session = WorkoutSession(workout: workout, startedAt: t0, endedAt: t0, status: .completed)
        ctx.insert(session)
        try ctx.save()

        try lib.softDelete(workout)

        let active = try ctx.fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isSoftDeleted }))
        #expect(active.isEmpty)
        let found = try #require(lib.workout(id: workout.id))
        #expect(found.isSoftDeleted)
        #expect(lib.workout(id: UUID()) == nil)
        #expect(session.workout?.id == workout.id)
        // Rows stay.
        #expect(found.orderedExercises.count == 1)
        #expect(try allSets(ctx).count == 2)
        #expect(!ctx.hasChanges)
        // Persisted.
        let fresh = ModelContext(tc.container)
        #expect(WorkoutLibrary(context: fresh).workout(id: workout.id)?.isSoftDeleted == true)
    }
}

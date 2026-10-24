import Foundation

/// One set in a template draft. `id` is the existing `PlannedSet.id`, or a new one.
nonisolated struct DraftSet: Equatable, Sendable {
    var id: UUID
    var values: SetValues

    init(id: UUID = UUID(), values: SetValues) {
        self.id = id
        self.values = values
    }
}

/// One exercise row in a template draft. `id` is the existing `WorkoutExercise.id`, or a new one.
/// Only the exercise's ID is stored: names are always looked up.
nonisolated struct DraftExercise: Equatable, Sendable {
    var id: UUID
    var exerciseID: UUID
    var sets: [DraftSet]

    init(id: UUID = UUID(), exerciseID: UUID, sets: [DraftSet]) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
    }
}

/// Why a draft can't be saved yet. Name uniqueness needs the store, so it isn't covered here.
nonisolated enum DraftIssue: Equatable, Sendable {
    case emptyName
    case noExercises
    case exerciseWithoutSets
}

/// A value-type copy of a template that the editor changes. Save writes it to the store; Cancel
/// throws it away. Every operation that takes an ID does nothing when the ID isn't found.
nonisolated struct WorkoutDraft: Equatable, Sendable {
    var name: String
    var exercises: [DraftExercise]

    init(name: String = "", exercises: [DraftExercise] = []) {
        self.name = name
        self.exercises = exercises
    }

    // MARK: Exercises

    func contains(exerciseID: UUID) -> Bool {
        exercises.contains { $0.exerciseID == exerciseID }
    }

    /// Appends the exercise with one set. Does nothing if the exercise is already in the draft.
    mutating func addExercise(exerciseID: UUID, firstSet: SetValues) {
        guard !contains(exerciseID: exerciseID) else { return }
        exercises.append(DraftExercise(exerciseID: exerciseID, sets: [DraftSet(values: firstSet)]))
    }

    /// Same as SwiftUI's `remove(atOffsets:)`, which `onDelete` calls. Offsets out of range are ignored.
    mutating func removeExercises(atOffsets offsets: IndexSet) {
        for index in offsets.reversed() where exercises.indices.contains(index) {
            exercises.remove(at: index)
        }
    }

    /// Same as SwiftUI's `move(fromOffsets:toOffset:)`, which `onMove` calls: the moved rows keep
    /// their relative order and land before the row that was at `destination` (an index in the
    /// array as it is before the move; `exercises.count` means the end). Offsets out of range are
    /// ignored and `destination` is clamped to the array.
    mutating func moveExercises(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { exercises.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let target = min(max(destination, 0), exercises.count)
        let moved = valid.map { exercises[$0] }
        let removedBeforeTarget = valid.filter { $0 < target }.count
        for index in valid.reversed() {
            exercises.remove(at: index)
        }
        exercises.insert(contentsOf: moved, at: target - removedBeforeTarget)
    }

    /// For VoiceOver "Move Up" (-1) and "Move Down" (+1). Clamps at both ends.
    mutating func moveExercise(id: UUID, by offset: Int) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = min(max(index + offset, 0), exercises.count - 1)
        guard newIndex != index else { return }
        let exercise = exercises.remove(at: index)
        exercises.insert(exercise, at: newIndex)
    }

    // MARK: Sets

    /// Appends a copy of the exercise's last set, with a new set ID. Does nothing when the
    /// exercise has no set to copy.
    mutating func addSet(toExercise id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              let last = exercises[index].sets.last
        else { return }
        exercises[index].sets.append(DraftSet(values: last.values))
    }

    /// An exercise always keeps at least one set, so removing its last set does nothing.
    /// Removing the exercise is the way to get rid of it.
    mutating func removeSet(_ setID: UUID, fromExercise id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              exercises[index].sets.count > 1,
              let setIndex = exercises[index].sets.firstIndex(where: { $0.id == setID })
        else { return }
        exercises[index].sets.remove(at: setIndex)
    }

    func sets(ofExercise id: UUID) -> [DraftSet] {
        exercises.first { $0.id == id }?.sets ?? []
    }

    func values(ofSet setID: UUID, inExercise id: UUID) -> SetValues? {
        exercises.first { $0.id == id }?.sets.first { $0.id == setID }?.values
    }

    mutating func setValues(_ values: SetValues, ofSet setID: UUID, inExercise id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }),
              let setIndex = exercises[index].sets.firstIndex(where: { $0.id == setID })
        else { return }
        exercises[index].sets[setIndex].values = values
    }

    // MARK: Validation

    /// What stops the draft from being saved, in a fixed order. Empty when it can be saved.
    var issues: [DraftIssue] {
        var result: [DraftIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.append(.emptyName)
        }
        if exercises.isEmpty {
            result.append(.noExercises)
        }
        if exercises.contains(where: { $0.sets.isEmpty }) {
            result.append(.exerciseWithoutSets)
        }
        return result
    }
}

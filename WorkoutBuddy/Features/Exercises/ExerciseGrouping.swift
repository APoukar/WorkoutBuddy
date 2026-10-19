import Foundation

/// One muscle group and its exercises, for sectioned lists.
nonisolated struct ExerciseSection: Identifiable {
    let group: MuscleGroup
    let exercises: [Exercise]

    var id: MuscleGroup { group }
}

nonisolated enum ExerciseGrouping {
    /// Sections in spec order (empty ones left out), exercises sorted by name.
    /// An empty (or whitespace-only) query matches everything. `group` limits the result to one muscle group.
    static func grouped(_ exercises: [Exercise], matching query: String, in group: MuscleGroup? = nil) -> [ExerciseSection] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return MuscleGroup.allCases.compactMap { current in
            guard group == nil || group == current else { return nil }
            let matches = exercises
                .filter { $0.muscleGroup == current }
                .filter { trimmed.isEmpty || $0.name.localizedStandardContains(trimmed) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return matches.isEmpty ? nil : ExerciseSection(group: current, exercises: matches)
        }
    }
}

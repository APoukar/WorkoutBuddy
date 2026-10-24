import Foundation

/// Where the template editor's navigation stack can go. Steps 8 and 9 add the destination views.
nonisolated enum WorkoutEditorRoute: Hashable {
    /// The sets screen of one exercise row. The ID is the `DraftExercise.id` (the row in the draft),
    /// not the ID of the `Exercise` it points to.
    case sets(draftExerciseID: UUID)
    case picker
}

/// The editor's decisions that don't need a view: when to save, when to ask before discarding,
/// and when to show the "no exercises" footer. Pure, so it can be unit tested.
nonisolated enum WorkoutEditorRules {
    /// Save is enabled when the name is valid (including uniqueness, which the caller checks against the store)
    /// and the draft has no issues.
    static func canSave(_ draft: WorkoutDraft, nameError: NameError?) -> Bool {
        nameError == nil && draft.issues.isEmpty
    }

    /// Whether Cancel and swipe-down must be guarded: the draft differs from the one the editor started with.
    static func hasChanges(initial: WorkoutDraft, current: WorkoutDraft) -> Bool {
        initial != current
    }

    /// What Save does once the draft is valid.
    enum SaveAction: Equatable {
        /// Write the draft to the store, then close.
        case write
        /// Close without writing, so `updatedAt` (and the "last used" ordering) doesn't move.
        case closeOnly
    }

    /// Saving an existing template that wasn't changed just closes the editor. A new template is always written.
    static func saveAction(hasChanges: Bool, isNew: Bool) -> SaveAction {
        hasChanges || isNew ? .write : .closeOnly
    }

    /// The only draft issue the editor shows as text besides the inline name error. `.emptyName` is
    /// shown by the name field, and `.exerciseWithoutSets` can't happen through the UI.
    static func footerIssue(for draft: WorkoutDraft) -> DraftIssue? {
        draft.issues.contains(.noExercises) ? .noExercises : nil
    }
}

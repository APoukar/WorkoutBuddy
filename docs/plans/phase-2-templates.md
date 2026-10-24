# Phase 2 — Workout templates

Covers `FEATURES.md` §7 phase 2: workout templates (F2), including each exercise's own defaults for new sets (the F1 editor fields) and the F2 first-set rule. It builds on phase 1 (`docs/plans/phase-1-foundation.md`), whose "Hooks left for later phases" this plan answers. `architect-reviewer` reviewed this plan, and it was agreed with the user on 2026-10-24.

The phase is split in two parts, each implemented in its own session:
- **Part A — data and logic (steps 1–5).** Schema fields, the exercise defaults, the template draft, the template library and the template queries. Almost everything is covered by unit tests.
- **Part B — UI (steps 6–10).** Shared UI pieces, the template editor, the exercise picker, the sets screen, and the Workouts tab with the template detail. These need manual checks in the simulator.

Both parts go on the branch `phase-2-templates`, with one PR at the end of part B.

## Workflow
The main session only orchestrates. It writes no Swift app or test code. For every step:
1. Run `implementer` with this plan's path and the step number.
2. Handle anything it lists under "Needs main session".
3. Run `code-reviewer` with the plan, the step and the implementer's report.
4. Present the findings to the user and discuss them. Agreed fixes go through `implementer` too, never as direct edits.
5. Once the build and tests are green, commit the step as `Phase 2, step N: <what it did>`. If the plan changed because of the step, commit the plan in the same commit.

**Session hand-off after step 5:** do the part A manual check (see "Verification"), then update the phase 2 progress memory with the last commit, any decisions made outside this plan, and "part B starts at step 6". Part B starts in a fresh session from that memory, this plan and `git log`.

## Decisions
- **"Values last used in a template" (§6):** the first set of that exercise in the active template that was **saved most recently**. "Saved" means created or edited through the template editor. Tapping Save without any change closes the editor without writing, so it doesn't make the template "last used" (step 7 review). This needs a new `Workout.updatedAt`. Soft-deleted templates are ignored. A template whose row for that exercise has no sets is skipped. Ties are broken by `createdAt`, then `id`, so the result is deterministic.
- **The first-set rule is resolved per value:** reps, kg and rest each come from the exercise's own default if set, then from the last-used set, then from Settings. A template's unsaved edits never count as "last used".
- **An exercise can appear only once in a template.** The picker shows exercises already in the template as disabled, with an "Added" label. This keeps "Exercise 2 of 5", per-session progress points and the last-used rule unambiguous. Supersets and warm-up sets are out of scope (§5).
- **Template names are unique** among active (not soft-deleted) templates, compared case-insensitively and trimmed at the ends, the same as exercise names. A soft-deleted template's name can be reused. Both libraries use one shared name rule.
- **The editor edits a value-type draft, not the models.** Save writes the draft to the store in one `save()`. Cancel throws the draft away, and asks "Discard Changes?" first when it has changes. This answers the phase 1 hook about unsaved edits: the main context never holds unsaved template edits, so `ExerciseLibrary`'s `save()` and `rollback()` can't commit or discard them by accident.
- **Saving keeps row IDs stable.** The draft remembers the `id` of each existing `WorkoutExercise` and `PlannedSet`. Save updates the matching rows, inserts new ones and deletes removed ones. Stable IDs matter for export (phase 7).
- **A template that can't start** (no exercises, which only happens after its last exercise was deleted in Settings) can still be opened and edited, but its editor can't save until it has an exercise again. The list and the detail view show that it needs exercises.
- **Start Workout** is laid out in the detail view with its real enabled state in phase 2. Its action is deliberately empty until phase 3 wires it to the session, so phase 2 merges a button that does nothing yet (agreed).
- **Swiping down the editor with unsaved changes is blocked** (`.interactiveDismissDisabled`) without a prompt. The HIG asks for a "Discard Changes?" action sheet here, which needs a UIKit bridge (`presentationControllerDidAttemptToDismiss`). Accepted as a known limitation for v1; Cancel still asks.
- **The picker stays open while adding.** It's pushed inside the editor's navigation (no sheet on a sheet). Tapping an exercise adds it and marks it "Added"; Back returns to the editor.
- **0 kg is shown as "Bodyweight"** wherever a weight is displayed as text (summaries, set rows; spoken "bodyweight"). Editing controls still show the number 0. Later phases (set screen, history, progress) follow the same rule.
- **The Workouts list is sorted by name** (`localizedStandardCompare`), in memory.
- **Deleting a template asks for confirmation** ("Delete “Push”?" / "Past sessions stay in your history.") from both the list's swipe action and the editor. It soft-deletes; there's no restore in v1.
- **Each exercise default can be left unset.** The exercise editor has a toggle per value ("Custom Reps", "Custom Weight", "Custom Rest"). A value that isn't set starts at the current Settings default when the editor opens; turning a toggle off and on again keeps its value.
- **Schema V1 is still edited in place.** No real data is on a device yet (the app has only run in the simulator), so new fields need no migration plan.

## Scope
- **In scope:**
  - `Exercise.defaultReps/defaultKg/defaultRestSeconds` and `Workout.updatedAt`
  - the defaults section in the exercise editor, and new wording for the Settings defaults footer
  - the F2 first-set rule and "Add set copies the previous set"
  - the Workouts tab: list, template detail, template editor, exercise picker, sets screen
  - template validation, name uniqueness and soft delete
  - the last-performed date (finished sessions only; phase 3 creates them, so for now it comes from preview and test data)
- **Out of scope:** starting and running a session (phase 3), the History tab (phase 5), Export (phase 7).

## Folder layout
- `WorkoutBuddy/Models/`: `SetValues` and `ExerciseDefaults` (phase 3 reuses `SetValues` for sessions)
- `WorkoutBuddy/Features/Workouts/`: the draft, `WorkoutLibrary`, the template queries and all Workouts tab views
- `WorkoutBuddy/Shared/`: the shared name rule and the error alert, moved here from `Features/Exercises/` so both features use them
- `WorkoutBuddyTests/` mirrors these folders

## Key design decisions
- **Actor isolation**, as in phase 1: `SetValues`, `ExerciseDefaults`, the draft types, `NameRules`, `FirstSetDefaults` and `SetSummary` are `nonisolated` and pure. `WorkoutLibrary` and the views stay on `MainActor`. Computed properties on models (`Exercise.defaults`) are declared **inside the class body** in `SchemaV1.swift`, next to `muscleGroup`, so they stay nonisolated for a later `@ModelActor` (phase 7).
- **`WorkoutLibrary`** is a `@MainActor` struct wrapping a `ModelContext`, like `ExerciseLibrary`. Every change saves explicitly, rolls back on failure and rethrows. It reuses `ExerciseLibrary.exercise(id:)` for lookups by ID, which doesn't filter out archived exercises.
- **Model rules from phase 1 still apply:** children are removed with `context.delete`; orders are renumbered **before** deletes; every change is committed in one `save()`; lookups by ID never filter on `isArchived` or `isSoftDeleted`. New children are inserted and then linked by setting their to-one (`row.workout = workout`, `set.workoutExercise = row`), never by appending to the parent's array.
- **No `#Predicate` through optional relationships** (such as `$0.exercise?.id` or `$0.workout?.isSoftDeleted`): they're unreliable on iOS 18. Fetch with a simple predicate (`!$0.isSoftDeleted`) and filter in memory, as `ExerciseLibrary.archive` does.
- **Names are never copied.** The draft stores exercise IDs only. Views look names up through `ExerciseLibrary.exercise(id:)` or the model relationship.
- **Values stay in range.** Saving clamps reps and rest and snaps kg with the `AppSettings` helpers, so a draft built in code can't store out-of-range values.
- **Numeric input** uses the phase 1 controls only (`RepsStepper`, `WeightField`, `RestStepper`). Never use SwiftUI's `.keyboard` toolbar placement.
- **Plurals** use automatic grammar agreement (`^[\(count) exercise](inflect: true)` in views, or an equivalent tested helper in pure code), so "1 exercise", "1 set" and "1 rep" come out right. The UI is English only.
- **Logging** uses `ErrorLogging.log` with a fixed action string and the category `"workouts"`.
- **Previews:** `Features/Workouts/WorkoutPreviewData.swift` builds on `ExercisePreviewData.container()` (which already has "Push Day" with Bench Press). It adds Overhead Press to "Push Day", a "Legs" template with one finished session (for the last-performed date), a "Core" template with a 0 kg set (for "Bodyweight"), and an "Empty" template with no exercises. It's compiled in every configuration, with no `#if DEBUG`, because a Debug-only helper broke the Release build in phase 1.

## Steps

### Part A — data and logic

**Step 1 — Schema fields**
- `SchemaV1.Exercise`: add `defaultReps: Int?`, `defaultKg: Double?`, `defaultRestSeconds: Int?`, all `nil` by default. Add them to the initializer as optional parameters defaulting to `nil`.
- `SchemaV1.Workout`: add `updatedAt: Date`. The initializer takes it as an optional parameter and sets it to `createdAt` when it isn't given.
- The seed leaves the new exercise fields `nil`.
- Tests (extend `SchemaV1Tests`):
  - the new fields default to `nil` and to `createdAt`
  - they persist after `save()` and a fresh fetch
  - setting a default back to `nil` persists
- Also run the tests on iPhone 16 / iOS 18.2.

**Step 2 — Exercise defaults (F1 editor fields)**
- `Models/ExerciseDefaults.swift` (`nonisolated`, `Equatable`, `Sendable`): `reps: Int?`, `kg: Double?`, `restSeconds: Int?`, `static let none`, and `clamped()`, which clamps reps and rest and snaps kg with the `AppSettings` helpers and keeps `nil`s.
- `Exercise.defaults: ExerciseDefaults`: a computed property inside the class body that reads and writes the three fields.
- `ExerciseLibrary`:
  - `add(name:muscleGroup:defaults: ExerciseDefaults = .none)`
  - `update(_:name:muscleGroup:defaults:)`, replacing the current `update`. It still validates, sets every field and saves once, with rollback, so an edit is never half saved. Defaults are stored clamped.
- `ExerciseEditorView`: a new section "Defaults for new sets" below the muscle group:
  - Three toggles, "Custom Reps", "Custom Weight" and "Custom Rest". When a toggle is on, the matching control (`RepsStepper`, `WeightField`, `RestStepper`, with their own default labels "Reps", "Weight", "Rest") appears right under it, animated. The toggle names differ from the control labels so the screen and VoiceOver don't repeat the same label twice (step 2 review).
  - A value that isn't set starts at `AppSettings.current()` when the editor opens. Turning a toggle off and on again keeps the value that was there, so an accidental tap never replaces a saved default with the Settings value (step 2 review). Turning a toggle off clears that default on save.
  - Footer: "Used for this exercise’s first set when you add it to a workout. Values that are off come from the last workout you saved with this exercise, then from Settings."
  - Save passes the defaults to `add` or `update`.
- `SettingsView`: change the defaults footer to "Used for a new exercise’s first set when the exercise has no defaults of its own and isn’t in any saved workout."
- Tests:
  - `ExerciseDefaults.clamped()` with values in range, out of range, off the 0.5 grid, and `nil`
  - `add` and `update` store the defaults, store them clamped, and clear them with `nil`
  - a rejected update (duplicate name) leaves the name and the defaults unchanged
  - update the existing `ExerciseLibraryTests` calls to the new signatures
- Also run the tests on iOS 18.2.

**Step 3 — Template draft and display helpers (pure)**
- `Models/SetValues.swift` (`nonisolated`, `Equatable`, `Hashable`, `Sendable`): `reps`, `kg`, `restSeconds`.
- `Features/Workouts/WorkoutDraft.swift` (`nonisolated`, all `Equatable` and `Sendable`, **no SwiftUI import**):
  - `DraftSet`: `id: UUID`, plus `values: SetValues`.
  - `DraftExercise`: `id: UUID` (the existing `WorkoutExercise.id`, or a new one), `exerciseID: UUID`, `sets: [DraftSet]`.
  - `WorkoutDraft`: `name: String`, `exercises: [DraftExercise]`, and these operations. Every operation that takes an ID does nothing when the ID isn't found.
    - `contains(exerciseID:)`
    - `addExercise(exerciseID:firstSet:)` appends the exercise with one set. It does nothing if the exercise is already in the draft.
    - `removeExercises(atOffsets: IndexSet)` and `moveExercises(fromOffsets: IndexSet, toOffset: Int)`, shaped for `onDelete` and `onMove`, but implemented by hand (SwiftUI's `Array` helpers aren't available without importing SwiftUI). Their semantics match SwiftUI's `remove(atOffsets:)` and `move(fromOffsets:toOffset:)`.
    - `moveExercise(id:by offset: Int)` for the VoiceOver "Move Up" / "Move Down" actions; it clamps at the ends.
    - `addSet(toExercise id:)` appends a copy of the exercise's last set, with a new set ID.
    - `removeSet(_ setID:, fromExercise id:)`. It does nothing when it would remove the exercise's last set: an exercise always keeps at least one set, and removing the exercise is the way to get rid of it.
    - `sets(ofExercise id:) -> [DraftSet]`, `values(ofSet:inExercise:) -> SetValues?` and `setValues(_:ofSet:inExercise:)`: the sets screen builds its bindings from these, by ID, never by array index.
    - `issues: [DraftIssue]`: `.emptyName`, `.noExercises` and `.exerciseWithoutSets`, in that order. The editor saves only when it's empty. Name uniqueness needs the store, so `WorkoutLibrary` checks it.
- `Shared/Formatters.swift`: add `weight(_ kg:)` → "22.5 kg", or "Bodyweight" for 0, and its spoken form ("22.5 kilograms" / "bodyweight"). The number and "kg" are joined by a non-breaking space (U+00A0), also in ranges ("60–80 kg"), so "kg" never wraps onto its own line (step 3 review). Spoken numbers follow the region like the screen does ("22,5 kilograms" in a Czech region); the locale-specific tests use `en_CZ`, the locale an English-only app actually runs with in a Czech region.
- `Features/Workouts/SetSummary.swift` (`nonisolated`): text for sets, using `Formatters`:
  - one set's line for detail rows: "10 × 60 kg", "10 × Bodyweight", with the spoken "10 reps at 60 kilograms" / "10 reps, bodyweight"
  - a one-line summary of an exercise's sets for list rows:
    - all sets equal: "3 × 10 × 60 kg", or "3 × 10 · Bodyweight" at 0 kg
    - otherwise: "3 sets · 8–12 reps · 60–80 kg", leaving out a range whose values are all equal ("3 sets · 10 reps · 60–80 kg"). A range that includes 0 shows as "0–20 kg"; "Bodyweight" is used only when every set is 0 kg ("3 sets · 8–12 reps · Bodyweight").
    - with one set: "1 × 10 × 60 kg"
    - plus a spoken form for VoiceOver ("3 sets of 10 reps at 60 kilograms")
  - singular forms are correct everywhere: "1 set", "1 rep", "3 sets of 1 rep"
- Tests, with no SwiftData:
  - add, duplicate add (ignored), remove and move exercises, including moves to the start and end, and `moveExercise(id:by:)` at both ends
  - `addSet` copies the last set and gets a new ID
  - `removeSet` keeps the last set
  - the ID-based set helpers, including unknown IDs (no change, `nil`)
  - each issue, and an empty list for a valid draft
  - `Formatters.weight` for 0 and non-zero, in fixed `en_US` and `en_CZ` locales
  - every summary case, including Bodyweight, ranges with 0, and the singular forms, in both visual and spoken forms

**Step 4 — Shared name rule, and `WorkoutLibrary`: validation, save and soft delete**
- `Shared/NameRules.swift` (`nonisolated`, pure):
  - `NameError`: `.empty`, `.duplicate`. It replaces `ExerciseNameError`.
  - `check(_ name:, against active: [(id: UUID, name: String)], excluding: UUID?) -> NameError?`: trimmed at the ends, compared case-insensitively, skipping `excluding`.
  - `visibleError(_:hasEdited:)`, moved from `ExerciseMessages.visibleNameError`: a duplicate shows immediately, and "Enter a name." waits until the user has typed something.
  - `ExerciseLibrary` and `ExerciseMessages` switch to these, with no change in behaviour. `ExerciseMessages` keeps its exercise-specific texts. Update `ExerciseLibraryTests` and `ExerciseMessagesTests`.
- `Features/Workouts/WorkoutLibrary.swift`:
  - `validate(name:excluding:) -> NameError?` against active templates, using `NameRules.check`. It has a throwing private version that `save` uses.
  - `draft(for workout: Workout?) -> WorkoutDraft`: an empty draft for a new template, or the template's exercises and sets in order, with their row IDs. Rows whose `exercise` is `nil` are skipped.
  - `save(_ draft:, to workout: Workout?, now: Date = .now) throws -> Workout`. Everything that can fail is checked **before the first change** to the context:
    1. Check the name with the throwing validation. Throw `WorkoutSaveError.invalid` if `draft.issues` isn't empty, or if the draft repeats an exercise, a row ID, or a set ID within a row. The editor can't produce repeats, but a draft built in code could, and they would break the "each exercise once" rule or leave stale rows behind (step 4 review). No `DraftIssue` is added for this.
    2. Look up every `exerciseID` with `ExerciseLibrary.exercise(id:)`. A missing **or archived** exercise throws `WorkoutSaveError.missingExercise`: a template must never get a deleted exercise back.
    3. Only then change the context: insert a new `Workout(name:, createdAt: now)` when `workout` is `nil`; set the trimmed name and `updatedAt = now`.
    4. Reconcile the rows by ID: update the order, the exercise and the set values of matching rows; insert new rows with the draft's IDs and link them by their to-one; set every `order` from the draft's position; only **then** delete the rows and sets the draft no longer has (`context.delete`).
    5. Store values clamped and snapped, and commit with one `save()`. Any error after the first change calls `rollback()` and rethrows.
  - `softDelete(_:)` sets `isSoftDeleted` and saves. It keeps the template's rows, so sessions still reference the template.
  - `workout(id:)`, which doesn't filter out soft-deleted templates.
- Tests:
  - `NameRules.check` and `visibleError` (moved from the exercise tests, plus `excluding`)
  - creating a template from a draft with a fixed `now`: name, order of exercises and sets, values, `createdAt == updatedAt == now`
  - editing: unchanged rows keep their IDs; reorder, insert and remove all land correctly; removed rows and their sets are gone from the store after save (fetch them, not just the accessor); `updatedAt` becomes the new `now`
  - duplicate and empty names are rejected; a soft-deleted template's name can be reused; renaming a template to its own name in another case is allowed
  - an invalid draft, a draft with a repeated exercise, row ID or set ID, a missing exercise and an archived exercise each throw and leave the context with no changes (`context.hasChanges` is false, and the template is unchanged)
  - the edit test also reads the result back through a fresh `ModelContext(tc.container)`: row IDs, orders, exercises and set orders
  - out-of-range values are stored clamped
  - editing a template leaves past sessions alone: build a session with `SessionSet`s from the template, then change values and remove an exercise in the template; the session's planned values and its `SessionExercise.exercise` are unchanged
  - soft delete hides the template from active fetches, `workout(id:)` still finds it, and its sessions keep their workout reference
- Also run the tests on iOS 18.2.

**Step 5 — Template queries: first-set values, last performed, start readiness**
- `Features/Workouts/FirstSetDefaults.swift` (`nonisolated`): `resolve(exercise: ExerciseDefaults, lastUsed: SetValues?, settings: AppSettings.Values) -> SetValues`, applying the rule per value.
- `WorkoutLibrary`:
  - `lastUsedFirstSet(forExerciseID:) throws -> SetValues?`: see the "values last used" decision. Fetch the active templates and filter in memory.
  - `firstSetValues(for exercise: Exercise, settings: AppSettings.Values) -> SetValues`: the full rule. A failed fetch falls back to skipping the "last used" source and is logged.
  - `lastPerformed(_ workout: Workout) -> Date?`: the latest `startedAt` among the template's sessions whose status is `completed` or `endedEarly`. Sessions in progress don't count.
  - `canStart(_ workout: Workout) -> Bool`: the template has at least one exercise and every exercise has at least one set. Rows whose `exercise` is `nil` are ignored, the same as in `draft(for:)` (step 5 review). (A per-reason enum isn't needed: the only way it fails in practice is a template emptied by deleting exercises.)
- Tests:
  - `resolve`: each value from each source, mixed sources (e.g. reps from the exercise with kg and rest from last used, or reps from the exercise with kg and rest from Settings; last used supplies all three values or none), and every source missing except Settings
  - `lastUsedFirstSet`, using fixed `now` dates through `save(_:to:now:)` or the `Workout` init: the most recently saved template wins over an older one; a soft-deleted template is ignored; a template saved again becomes the most recent; it takes the **first** set; the tie-break; `nil` when no active template has the exercise
  - `lastPerformed`: picks the latest finished session, ignores in-progress ones, and is `nil` with no sessions
  - `canStart`: true for a valid template, false with no exercises, false when the only row has no exercise
- Also run the tests on iOS 18.2.

**→ End of part A.** Do the part A manual check and the session hand-off described under "Workflow".

### Part B — UI

**Step 6 — Shared UI pieces**
- Move the error alert to `Shared/ErrorAlert.swift` as `.errorAlert($failure, message:)`, where `message` maps an error to its text (each feature passes its own `failureMessage(for:)`). Update the exercise screens to use it, with no change in behaviour.
- `Features/Workouts/WorkoutMessages.swift`: the name errors ("Enter a name." / "A workout with this name already exists."), `failureMessage(for:)`, the delete confirmation title and message, and the issue texts ("Add at least one exercise.").
- `Features/Workouts/WorkoutDeletionFlow.swift`: a `.workoutDeletionAlert($pending, library:, onFailure:, onDeleted:)` modifier on the pattern of `ExerciseDeletionAlert`. Confirming calls `softDelete`. Steps 7 and 10 both use it.
- `Features/Workouts/WorkoutPreviewData.swift`: see "Previews" above.
- Tests: the `WorkoutMessages` texts and `failureMessage(for:)`.

**Step 7 — Template editor**
- `Features/Workouts/WorkoutEditorView.swift`: one sheet for both creating and editing, with its own `NavigationStack(path:)`. The path holds a small `Hashable` route enum, `WorkoutEditorRoute` in `WorkoutEditorRules.swift` (`.sets(draftExerciseID: UUID)`, carrying the `DraftExercise.id`, and `.picker`); steps 8 and 9 replace the placeholder destinations (step 7 review).
  - Holds the draft in `@State`, built once from `WorkoutLibrary.draft(for:)`, and keeps the starting draft to detect changes.
  - **Name** section: a text field, focused when creating, with the inline name error (`NameRules.visibleError`) and the VoiceOver announcement, as in the exercise editor.
  - **Exercises** section, with an **Edit/Done** button in its header that switches `editMode` for the list:
    - One row per draft exercise, keyed by draft exercise ID, showing the exercise name and its `SetSummary`.
    - In edit mode, rows show delete and reorder controls (`onDelete`, `onMove`). Outside edit mode, rows open the sets screen (step 9) and still support swipe-to-delete.
    - Each row has VoiceOver actions "Move Up" and "Move Down" (`draft.moveExercise(id:by:)`), offered only when the move is possible (no "Move Up" on the first row, no "Move Down" on the last).
    - An "Add Exercise" row comes last; step 8 makes it open the picker.
    - When the draft has `.noExercises`, the section footer says "Add at least one exercise."
  - The editor shows only these two messages: the inline name error under the name field, and the "Add at least one exercise." footer. `.emptyName` isn't shown a second time anywhere, and `.exerciseWithoutSets` can't happen through the UI, so neither gets its own text on screen (step 6 review).
  - Toolbar: Cancel, and Save, which is disabled while the name is invalid or the draft has issues. Save calls `WorkoutLibrary.save` and dismisses. With no changes, Save only dismisses, without writing (step 7 review).
  - The name field is focused only the first time the editor appears when creating, not again after returning from the picker or the sets screen (step 7 review). iOS restores a text field's focus when a pushed screen is popped, so "Add Exercise" and the exercise rows clear the name focus before they push (a button that sets the focus to `false` and then appends to the path, with a trailing chevron so it still looks like a navigation row) (step 8 review). In Edit mode the exercise rows don't open the sets screen and hide their chevron, like system navigation rows; "Add Exercise" keeps working and keeps its chevron (agreed with the user).
  - Cancel with changes shows a "Discard Changes?" confirmation dialog, attached to the Cancel button. Swipe-to-dismiss is disabled while there are changes (`.interactiveDismissDisabled`); see the Decisions for why there's no prompt.
  - When editing, a destructive **Delete Workout** button at the bottom uses `.workoutDeletionAlert`. After the deletion it calls an `onDeleted` callback and dismisses; the caller decides what to pop (step 10).
  - Errors use `.errorAlert`.
- Previews: new template, editing "Push Day", editing "Empty".

**Step 8 — Exercise picker**
- `Features/Workouts/ExercisePickerView.swift`: pushed inside the editor's `NavigationStack` (the `.picker` route), not presented as a sheet.
  - A `@Query` of active exercises, in sections from `ExerciseGrouping.grouped(_:matching:in:)`, with `.searchable`.
  - The muscle-group filter is a toolbar `Menu` holding a `Picker` with "All Muscle Groups" plus each group. The menu's icon shows when a filter is active (`line.3.horizontal.decrease.circle` / `.fill`). VoiceOver reads the accessibility label "Muscle Group Filter" with the current filter as its value ("Chest" or "All Muscle Groups") (step 8 review).
  - No matches shows `ContentUnavailableView.search`. A filter with no exercises shows "No Exercises" / "No exercises in Chest.", and this wins over the search result. With no exercises at all it shows "No Exercises" / "Add exercises in Settings → Exercises." (step 8 review). Searching inside a filter doesn't hint at other groups; the filled filter icon is the only sign that a filter is on (accepted).
  - Exercises already in the draft are disabled and show a trailing "Added" label, read by VoiceOver. The row is a `LabeledContent`, so "Added" moves below the name at accessibility text sizes. After a pick, VoiceOver announces "Bench Press added" (step 8 review).
  - Tapping an exercise calls `onPick(exercise)` and the picker stays open; the row turns "Added". Back returns to the editor. There's no Cancel.
  - The picker can't create exercises (F2).
- `WorkoutEditorView`: "Add Exercise" pushes the picker. A pick runs `draft.addExercise(exerciseID:firstSet:)` with `WorkoutLibrary.firstSetValues(for:settings: AppSettings.current())`.
- Previews: the picker with nothing added, and with Bench Press already added.

**Step 9 — Sets screen**
- `Features/Workouts/ExerciseSetsView.swift`: the `.sets(draftExerciseID:)` destination. It takes `@Binding var draft: WorkoutDraft` and the draft exercise ID, and builds every binding through the draft's ID-based helpers (step 3). If the exercise is no longer in the draft, it shows nothing and doesn't crash.
  - Title: the exercise name, passed in by the editor, which already looks it up (step 9 review).
  - One section per set, `ForEach` keyed by **set ID** (`WeightField` keeps its text in `@State`, so index keys would show stale text after a delete), headed "Set 1", "Set 2", …, with `RepsStepper`, `WeightField` and `RestStepper`.
  - Each section ends with a destructive "Delete Set" button, hidden when it's the only set.
  - An "Add Set" button at the end runs `draft.addSet`, which copies the previous set.
  - Changes go straight into the draft; Save in the editor commits them.
- Previews: Bench Press with one set and with three different sets.

**Step 10 — Workouts tab and template detail**
- `Features/Workouts/WorkoutListView.swift`, in the Workouts tab of `RootTabView`, replacing the placeholder:
  - A `NavigationStack(path:)` whose path is an array of workout IDs, owned by the list. Rows use `NavigationLink(value: workout.id)`, and `navigationDestination` resolves the ID with `WorkoutLibrary.workout(id:)`.
  - The large title "Workouts" and a `@Query` of active templates, sorted by name in memory with `localizedStandardCompare`.
  - Each row shows the name, then "5 exercises · Last done 12 Oct 2026" or "5 exercises · Not done yet". A template that can't start shows "No exercises" with an orange warning symbol instead of the count (only the symbol is orange; the text keeps the normal subtitle style, because orange text is too faint on white), and VoiceOver reads "Needs exercises". The last-done part stays ("No exercises · Last done 12 Oct 2026") (step 10 review). Dates use `formatted(date: .abbreviated, time: .omitted)`.
  - A toolbar "+" button (accessibility label "New Workout") opens `WorkoutEditorView` to create a template.
  - Each row has a trailing **Delete** swipe action, red-tinted, without full swipe, using `.workoutDeletionAlert`.
  - With no templates: `ContentUnavailableView` "No Workouts", "Create a workout to plan your sets.", with a "New Workout" button.
- `Features/Workouts/WorkoutDetailView.swift`:
  - Title: the template name. Toolbar "Edit" opens `WorkoutEditorView` for the template as a sheet.
  - One section per exercise (name as header). Each set is a row: "Set 1", the `SetSummary` line ("10 × 60 kg" or "10 × Bodyweight"), and the rest ("1:30"), with a combined VoiceOver label. At accessibility text sizes the three parts stack vertically (step 10 review).
  - A template with no exercises shows `ContentUnavailableView` "No Exercises", "Edit this workout to add exercises."
  - A **Start Workout** button pinned at the bottom with `.safeAreaInset(edge: .bottom)` and a `.bar` background, so rows don't show through it on iOS 18. `.borderedProminent`, `.controlSize(.large)`, full width. It's disabled when `canStart` is false, with "Add an exercise to start this workout." under it. Its action is empty until phase 3. On iOS 26 and later it uses `.safeAreaBar(edge: .bottom)` without the `.bar` background, so the list gets the system's soft scroll-edge effect; `.safeAreaInset` with `.bar` is the iOS 18 fallback (step 10 review).
  - **Deleting from the editor:** the editor's `onDeleted` sets a flag in the detail view. The editor sheet's `onDismiss` checks the flag and asks the list to remove the workout's ID from its path, so the pop happens once, after the sheet is gone.
- Previews: the list with the preview data, an empty list, the detail of "Push Day", "Core" and "Empty".

## Hooks left for later phases
- **Phase 3:** the Start Workout action, the "only one active session" rule, and creating the session from the template, copying the planned numbers (`SetValues` is in `Models/` for this). `WorkoutLibrary.canStart` is the start check; Start must also refuse a soft-deleted template (`isSoftDeleted`), because the detail keeps showing a template that was deleted while it was open (step 10 review). `lastPerformed` starts showing real data once sessions are saved. The set screen shows 0 kg as "Bodyweight" through `Formatters.weight`.
- **Phase 5:** History reaches templates through `WorkoutSession.workout`, including soft-deleted ones (`workout(id:)` doesn't filter them). Set rows use `Formatters.weight`. Each Workouts list row runs `lastPerformed`, which loads all of the template's sessions on every list redraw; if the list gets slow with real history, compute the subtitles once per body run or move the row into its own view (step 10 review).
- **Phase 7:** export includes `Workout.updatedAt` and the exercise defaults. Row IDs are stable across edits.
- **Later:** a "Discard Changes?" prompt when the editor is swiped down with changes (needs a UIKit presentation-controller bridge).

## Verification
- Each step: the CLAUDE.md build and test commands on iPhone 17 / OS 27.0 come out green, the tests also pass on iPhone 16 / OS 18.2, and `code-reviewer` reviews the step. Run the Release build locally for steps that touch previews or preview data (steps 6–10); CI runs it on every push anyway.
- At the end of the phase, run the full test suite on iOS 18.2 once more.
- **Part A manual check** (end of step 5), on iOS 27 and iOS 18.2:
  - In Settings → Exercises, turn on each default for an exercise, change it, save and reopen: the values are kept. Turn one off: it stays off. Turn a saved one off and on again before saving: it keeps its value. The rows slide in and out.
  - The kg default field accepts 22,5 and has its Done bar; the section lays out at the largest accessibility text size.
  - The Settings defaults footer shows the new wording.
- **Part B manual check** (end of step 10), on iOS 27 and iOS 18.2:
  - Create "Push" with Bench Press and Overhead Press. Each first set uses the Settings defaults.
  - Give Bench Press its own reps default in Settings → Exercises. Adding it to a new template takes reps from it and kg and rest from "Push".
  - "Add Set" copies the previous set. The last set can't be deleted.
  - Reorder with Edit/Done and remove exercises, save, reopen: the order and the sets are kept. With VoiceOver, "Move Up" and "Move Down" reorder too.
  - Create "push": it's rejected as a duplicate. Delete "Push", then create "Push": it's allowed.
  - The picker shows exercises already in the template as "Added", stays open after each pick, and the muscle-group filter and search work together. On iOS 27 the search field and the filter menu don't overlap, and the filter icon doesn't look like a circle inside the toolbar button's own circle; if it does, use the plain `line.3.horizontal.decrease` on iOS 26+ (step 8 review). With VoiceOver, a pick is announced ("Bench Press added").
  - Cancel after an edit asks "Discard Changes?", shown from the Cancel button on iOS 27. Swiping the sheet down is blocked while there are changes. Save without changes just closes the editor.
  - The name field is focused when the New Workout sheet opens. Going back from the picker or the sets screen doesn't reopen the keyboard.
  - In Edit mode, "Add Exercise" and "Delete Workout" still work. Swiping a row to delete it doesn't briefly switch the header's Edit button to "Done".
  - Delete a template's only exercise in Settings → Exercises: the list and detail show it needs exercises, Start Workout is disabled, and the editor can't save until an exercise is added.
  - Delete a template from its editor: the app returns to the list once, without a double pop.
  - A 0 kg set shows "Bodyweight" in the editor summary and the detail.
  - kg fields in the sets screen: type 22,5 with a Czech region and with a US region; every kg field has its Done bar (the screen lives in a sheet, where SwiftUI's keyboard toolbar used to fail); the kg field of the last set isn't hidden by the keyboard. On iOS 27 the Done bar is the system's round checkmark button above the keyboard, not the word "Done". The iOS 18.2 simulators have a hardware keyboard connected, so press ⌘K (I/O → Keyboard → Toggle Software Keyboard) to check that the last kg field stays above the on-screen keyboard; on iOS 27 this was confirmed in the step 9 review.
  - The list scrolls under the Start Workout bar without rows showing through; on iOS 27 it fades softly into the bar.
  - The orange warning symbol and the "No exercises" text are readable in light and dark mode.
  - VoiceOver reads the list rows, set rows, the "Added" label and the summaries sensibly.
  - With VoiceOver and a Czech region, a 22.5 kg set is read sensibly ("22,5 kilograms"). If it isn't, revisit the spoken number format (step 3 review).
  - Largest accessibility text size: the editor, the sets screen and the detail still lay out without clipping.

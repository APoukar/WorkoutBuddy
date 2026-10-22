# Phase 1 — Foundation

Covers `FEATURES.md` §7 phase 1: the SwiftData models, the exercise seed, Settings → Exercises (F1) and the basic F9 settings. `architect-reviewer` reviewed this plan, and it was agreed with the user on 2026-10-19.

## Decisions
- **Weight step options are 0.5 / 1 / 2.5 kg.** The 1.25 option is dropped, so every weight stays on the 0.5 kg grid.
- **No restore of deleted exercises in v1.** Their names can be reused. Two exercises with the same name can then appear in history and progress, and that's accepted.
- **The full §4 data model is defined now,** in schema V1.
- **No migration plan until V2.** V1 can be edited in place while it's in development, and it's frozen once real data is on a device.
- **The action is labelled "Delete"** (it archives the exercise under the hood).
- **Deleting an exercise removes it from templates,** after a warning that names the templates using it.
- **All exercises, built-in or custom, can be renamed, regrouped and deleted.**

## Scope
- **In scope:**
  - the full §4 data model (schema V1) and the container setup
  - the exercise seed, run only on the first launch
  - the tab bar shell, with Workouts, History and Progress as placeholders
  - Settings: Exercises management (F1), defaults for new sets, the weight step, and the rest-end alert toggles (F9)
  - reusable value controls (reps, kg, rest) that phase 2's set editor will also use
- **Out of scope:** template editing (phase 2), sessions and their UI (phase 3), and Export (phase 7). Settings gets no Export row until phase 7.

## Folder layout
Both folders are synchronized, so new files join their targets automatically.
- `WorkoutBuddy/App/`: the app entry point and the root tab view
- `WorkoutBuddy/Models/`: the domain enums
- `WorkoutBuddy/Persistence/`: the schema, the container factory and the seed
- `WorkoutBuddy/Features/Exercises/`, `WorkoutBuddy/Features/Settings/`
- `WorkoutBuddy/Shared/`: formatters, settings, and the reusable controls
- `WorkoutBuddyTests/` mirrors these folders

## Key design decisions
- **Actor isolation.** The project's default isolation is `MainActor`, which clashes with SwiftData's nonisolated protocols. So mark these `nonisolated`:
  - `nonisolated enum SchemaV1`, and `@Model nonisolated final class` for every model
  - the domain enums (`MuscleGroup`, `SessionStatus`, `SetStatus`, `WeightStep`)
  - the pure helpers (formatters, settings ranges and clamping, `ExerciseGrouping`)

  `ExerciseLibrary` and the views stay on `MainActor`. A later `@ModelActor` (export in phase 7) relies on the models being nonisolated.
- **Enums are stored as raw strings.** Models store `muscleGroupRaw` and `statusRaw`, and a computed property gives the typed value. This keeps `#Predicate` reliable on iOS 18. `SetStatus` gets `pending` in addition to the §4 statuses, for sets that haven't been reached yet (phase 3).
- **Soft-delete flag:** `Workout.isSoftDeleted`, because `PersistentModel` already has an `isDeleted` property. Exercise uses `isArchived`.
- **Explicit order.** Every ordered child has `order: Int`, and the parent has a sorted accessor (`orderedExercises`, `orderedSets`).
- **Relationships and delete rules:**
  - Parent → child relationships cascade: Workout → WorkoutExercise → PlannedSet, and WorkoutSession → SessionExercise → SessionSet.
  - Every parent → child relationship has an explicit `inverse:` back to the parent (`WorkoutExercise.workout`, `PlannedSet.workoutExercise`, `SessionExercise.session`, `SessionSet.sessionExercise`). Without these, a deleted child stays in the parent's array after save, and on iOS 18 it can come back (found in the step 1 review).
  - **A child is always removed with `context.delete`.** Removing it only from the parent's array leaves an orphaned row in the store.
  - To-many arrays are **non-optional** (`= []`). CloudKit sync is out of scope.
  - `Workout.sessions` is the inverse of `WorkoutSession.workout`, with the `.nullify` delete rule. Phase 2 uses it for the last-performed date.
  - References to `Exercise` are plain optional relationships, with no inverse on Exercise.
  - Exercise and Workout are never hard-deleted.
- **Every model has a stable `id: UUID`.** ID lookups never filter on `isArchived` or `isSoftDeleted`.
- **Schema versioning:**
  - Use `SchemaV1: VersionedSchema` with top-level typealiases (`typealias Exercise = SchemaV1.Exercise`, …). The container uses `Schema(versionedSchema: SchemaV1.self)` with **no migration plan**, so adding fields during development migrates automatically.
  - `AppMigrationPlan` is added in the same commit as SchemaV2.
  - **Rule:** V1 is frozen the first time the app goes onto a device with real data.
- **Container failures and tests:**
  - When the app runs as the test host (the implementer finds a reliable check, e.g. the `XCTestConfigurationFilePath` environment variable), it uses an in-memory container. Tests never touch the real store.
  - If the store fails to load: **in the simulator only** (`#if targetEnvironment(simulator)`), delete the store files and retry once. On a device, in any build, stop with a `fatalError` and a clear message, so real history is never deleted.
- **Name uniqueness is checked in code, not with `#Unique`.** Names are trimmed. The check compares case-insensitively against active exercises only, and skips the exercise being renamed.
- **Settings use `@AppStorage`:**
  - `AppSettings` holds the keys, defaults and valid ranges.
  - `AppSettings.current(in: UserDefaults)` returns clamped values for code outside views (phases 2 and 3).
  - `WeightStep` uses String raw values, so `@AppStorage` can store it, plus a computed `kg: Double`.
- **Seeding:** insert the seed list when the store has **no Exercise records at all**. Deleted (archived) exercises still count as records.
- **Deleting an exercise:**
  - `ExerciseLibrary.archive` sets `isArchived` and deletes the `WorkoutExercise` rows (cascading to their planned sets) that reference the exercise in any template. This includes soft-deleted templates, so no hidden references remain. The remaining exercises in each template are renumbered **before** the deletes, and everything is committed in **one** `save()`. If the save fails, `context.rollback()` runs and the error is rethrown.
  - Sessions are never touched.
  - A template can end up with no exercises. Phase 2 must show such a template as needing exercises and must not let it start.
- **Formatting follows the user's locale:**
  - kg uses `formatted(.number.precision(.fractionLength(0...1)))`.
  - Rest uses `Duration.seconds(n).formatted(.time(pattern: .minuteSecond))`.
  - Durations also get a spoken label for VoiceOver (e.g. "1 minute 30 seconds").
- **Saving:** every `ExerciseLibrary` change calls `context.save()` explicitly.
- **Logging errors** (applies to all phases): use `Logger`. Log an error's domain and code as `privacy: .public`, and keep the full error description private (the default), because SwiftData errors can contain record values.
- **Names are only trimmed at the ends.** Spaces inside a name are kept as typed (agreed in the step 3 review).

## Steps

**Step 1 — Domain enums and SwiftData models (schema V1)**
- `Models/MuscleGroup.swift`, `SessionStatus.swift`, `SetStatus.swift`: `nonisolated`, String-backed, `CaseIterable`, `Codable`, each with a display name.
- `Persistence/SchemaV1.swift`. Models and fields:

  | Model | Fields |
  |---|---|
  | `Exercise` | id, name, muscleGroupRaw, isCustom, isArchived |
  | `Workout` | id, name, createdAt, isSoftDeleted, exercises, sessions |
  | `WorkoutExercise` | id, order, workout?, exercise?, sets |
  | `PlannedSet` | id, order, workoutExercise?, reps, kg: Double, restSeconds: Int |
  | `WorkoutSession` | id, workout?, startedAt, endedAt?, pausedDuration: TimeInterval, statusRaw, exercises |
  | `SessionExercise` | id, order, session?, exercise?, sets |
  | `SessionSet` | id, order, sessionExercise?, plannedReps, plannedKg, plannedRestSeconds, actualReps?, actualKg?, statusRaw, completedAt? |

  Each model also gets the typealias and the sorted accessors.
- `Persistence/ModelContainerFactory.swift`:
  - `make(inMemory: Bool = false) throws -> ModelContainer`, with the simulator-only reset-and-retry.
  - A test helper that keeps the container alive, not just its `mainContext`.
- Tests:
  - Build a full workout and session graph, and check that the sorted accessors return children in `order`.
  - Deleting a Workout cascades to its children, **after `save()`**, and leaves the referenced Exercise in place.
  - Deleting a single child (a `WorkoutExercise`, a `PlannedSet`, a `SessionSet`) and saving removes it from the parent's ordered accessor, and it doesn't come back after a further edit.
  - `Workout.sessions` contains the workout's sessions.
  - The raw values convert back to the right enum cases.
- Also run the tests on iPhone 16 / iOS 18.2.

**Step 2 — Exercise seed**
- `Persistence/ExerciseSeed.swift`: the static list, and `seedIfNeeded(in:)`, which inserts the list with `isCustom = false` when the store has no Exercise records, then saves.
- The list has 43 entries:
  - Chest: Bench Press, Incline Bench Press, Dumbbell Bench Press, Incline Dumbbell Press, Dumbbell Fly, Push-Up
  - Back: Deadlift, Pull-Up, Lat Pulldown, Barbell Row, Dumbbell Row, Seated Cable Row
  - Shoulders: Overhead Press, Dumbbell Shoulder Press, Lateral Raise, Front Raise, Rear Delt Fly, Face Pull
  - Biceps: Barbell Curl, Dumbbell Curl, Hammer Curl, Preacher Curl
  - Triceps: Triceps Pushdown, Skull Crusher, Overhead Triceps Extension, Close-Grip Bench Press
  - Legs: Back Squat, Leg Press, Romanian Deadlift, Leg Extension, Leg Curl, Walking Lunge, Standing Calf Raise
  - Glutes: Hip Thrust, Glute Bridge, Bulgarian Split Squat
  - Core: Crunch, Hanging Leg Raise, Cable Crunch, Ab Wheel Rollout
  - Full body: Power Clean, Kettlebell Swing, Thruster
- Tests:
  - Seeding an empty store inserts all 43 entries.
  - A second call inserts nothing.
  - A store that holds only archived exercises isn't seeded again.
  - Seed names are unique when compared case-insensitively.
  - Every muscle group has at least one entry.
- Also run the tests on iOS 18.2.

**Step 3 — Exercise library logic**
- `Features/Exercises/ExerciseLibrary.swift` is a `@MainActor` struct wrapping a `ModelContext`:
  - `validate(name:excluding:) -> ExerciseNameError?`, where the error is `.empty` or `.duplicate`. The editor calls it on every keystroke, and `add` and `rename` call it before saving.
  - `add(name:muscleGroup:)` and `update(_:name:muscleGroup:)`. Step 6 replaced the original `rename` and `setMuscleGroup` with the single `update`, which saves once.
  - `workoutsUsing(_ exercise:) throws -> [Workout]`: the active templates (not soft-deleted) that contain the exercise, sorted by name. The delete warning uses it.
  - `archive(_:)`: see "Deleting an exercise" above.
  - `exercise(id:)`, which doesn't filter out archived exercises.
- `Features/Exercises/ExerciseGrouping.swift` (`nonisolated`):
  - `grouped(_ exercises:, matching query:, in group: MuscleGroup? = nil) -> [ExerciseSection]`. `ExerciseSection` is a small `Identifiable` struct with the group and its exercises.
  - Groups are in spec order and names are alphabetical. Search uses `localizedStandardContains`, and an empty query matches everything.
  - Phase 2's picker uses the group filter, and the Progress list in phase 6 reuses this.
- `ExerciseDeletionWarning` (`nonisolated`, pure): builds the confirmation title and message from the exercise name and the affected template names. The rules:
  - The title is always `Delete “<name>”?`.
  - With no templates, the message is "It stays in your history."
  - With templates, the names go **inline** in one sentence, because alerts centre their text. At most 3 names are listed, then "and N more": "It will be removed from Push, Upper A and Full Body." or "It will be removed from Push, Pull, Legs and 2 more."
  - If templates would be left with no exercises, a sentence follows in the same paragraph: "Push will have no exercises left and can’t be started until you add some." For several, use "Push and Legs …". Emptied templates are always named here, even when the cap left them out of the first sentence. Only names that are also in the template list are used.
  - The message ends with a blank line, then "It stays in your history."
  - `deletionWarning(for:)` on `ExerciseLibrary` builds the warning for a given exercise and `throws`.
- Tests:
  - add, rename and change muscle group
  - empty and whitespace-only names
  - duplicates that differ only in case
  - adding a name that only an archived exercise has is allowed
  - renaming an exercise to its own name in a different case
  - archiving hides the exercise from active fetches, but `exercise(id:)` still finds it
  - archiving removes the exercise's `WorkoutExercise` rows and planned sets from templates, renumbers the remaining ones, and leaves sessions untouched
  - `workoutsUsing` leaves out soft-deleted templates
  - each case of the warning text
  - the grouping order, the group filter, search matching, and an empty query
- Also run the tests on iOS 18.2.

**Step 4 — Settings, formatters and reusable value controls**
- `Shared/AppSettings.swift`:
  - The keys and defaults: reps 10, kg 20, rest 90 s, weight step 2.5, sound on, haptics on.
  - The valid ranges: reps 1–100, kg 0–500 on the 0.5 grid, rest 0–600 s.
  - `current(in: UserDefaults)` returns clamped values.
  - `WeightStep` has the values 0.5, 1 and 2.5, with 2.5 as the default, String raw values and `kg: Double`.
- `Shared/Formatters.swift`: the kg format, the m:ss rest format, and the spoken duration label.
- Reusable controls in `Shared/Controls/`, which take a binding and use the `AppSettings` ranges:
  - `RepsStepper`.
  - `WeightField`: a decimal-pad text field plus a stepper. The field reads the weight step from `@AppStorage` itself, so every screen follows the Settings value.
    - The binding is updated on every keystroke that parses, snapped to the 0.5 grid. A button tapped mid-edit (e.g. Save or Done) therefore sees what's on screen.
    - The value from when the field gained focus is remembered. While the text is empty or doesn't parse, the binding goes back to that value, so clearing the field never leaves an in-between value such as 2 from deleting "22.5". This stays the value from before editing even after a +/− press while focused (user's choice).
    - While focused, the text is rewritten only when the binding changes to a value the text doesn't already stand for, using the same rule as the text handler: empty or invalid text stands for the value from focus time. So the field never refills itself while you clear it, and +/− presses and outside changes still update the text. The decision is a small `nonisolated` helper with tests.
    - On focus loss, the field only reformats its text from the binding.
    - The stepper uses `AppSettings.kgRange`, so − and + are disabled at 0 and 500 kg.
    - VoiceOver: one stop for the field (reading its own text) and one for the stepper.
    - The layout works at accessibility text sizes: no fixed width, and the row stacks vertically at accessibility sizes.
    - The text → committed-value logic is a small `nonisolated` helper with unit tests.
  - `RestStepper`: steps of 15 s, displayed as m:ss, with the spoken label for VoiceOver.
- Tests:
  - the formatters with a fixed locale (`en_US` and `cs_CZ`), so "22.5" and "22,5" both come out right
  - parsing and snapping kg input. **Both "." and "," are accepted as the decimal separator in every locale.** Weights are at most 500, so there are no grouping separators. Only digits plus at most one separator, with **at most two digits after it**, are allowed, and anything else is rejected (nil): e.g. "12abc", "22.5.3", "1,000", "22.555". "22.55" is accepted and snaps to 22.5. Agreed in the step 4 review: the lenient locale parse turned "22,5" into 22 in en_US.
  - clamping in `current(in:)`, using a separate `UserDefaults(suiteName:)` instance, never `.standard`
  - `WeightStep` values and the default

**Step 5 — App shell**
- `App/WorkoutBuddyApp.swift`: build the container with the factory (in memory when running as the test host), run `ExerciseSeed.seedIfNeeded` at launch, and attach the container with `.modelContainer`.
- `App/RootTabView.swift`: a `TabView` using the iOS 18 `Tab` API, with tabs Workouts (`dumbbell`), History (`calendar`), Progress (`chart.line.uptrend.xyaxis`) and Settings (`gearshape`). All four tabs show a `ContentUnavailableView` placeholder for now. Step 6 replaces the Settings one.
- Delete `ContentView.swift`. Replace the placeholder test with tests of the app's real launch seeding helper: on a fresh in-memory container it gives 43 exercises, and running it again still gives 43. Also test that the test host is detected. If seeding fails at launch, the app rolls back, logs the error (see "Logging errors") and keeps running, and seeding is retried on the next launch.

**Step 6 — Settings → Exercises management (F1)**
- `Features/Exercises/ExerciseListView.swift`:
  - A `@Query` of active exercises, shown in sections from `grouped(_:matching:)`, with `.searchable`. A search with no matches shows `ContentUnavailableView.search`.
  - A toolbar "+" button (with an accessibility label) opens the editor to add an exercise. Tapping a row opens the editor for that exercise.
  - Each row has a trailing **Delete** swipe action. It's red-tinted but has no destructive role, and full swipe is off.
  - Delete keeps the exercise in `@State` and shows **one** `.alert` attached to the list. The alert text comes from `ExerciseDeletionWarning` (using `workoutsUsing`), with Cancel and a destructive "Delete". Confirming calls `archive`.
- `Features/Exercises/ExerciseEditorView.swift`:
  - One sheet for both adding and editing, with a name field and a muscle-group picker.
  - Validation runs live through `validate`. Save is disabled while the name is invalid, and the error appears inline.
    - For a new exercise, "Enter a name." is hidden on the blank form. It appears once the user has typed anything and then left the name empty. A duplicate error shows immediately. VoiceOver announces the error when it appears.
    - The cursor starts in the name field when adding.
    - Save calls a single `ExerciseLibrary.update(_:name:muscleGroup:)`, which validates, sets both fields and saves once with rollback, so an edit is never half saved. Library tests cover it.
  - Errors show one alert with the neutral title "Something Went Wrong". The shared error-logging helper lives in `Shared/` and is also used by the app's launch seeding. The action label is logged as public.
  - The delete-warning building code lives once in the shared delete flow.
  - The list shows `ContentUnavailableView` "No Exercises" when every exercise has been deleted.
  - Previews include editing Bench Press with the sample template. The preview data is compiled in every configuration, with no `#if DEBUG`, because a Debug-only helper broke the Release build.
  - When editing, a destructive **Delete Exercise** button at the bottom runs the same warning flow.
- Previews use an in-memory, seeded container with one sample template.

**Step 7 — Settings screen (F9 basics)**
- `Features/Settings/SettingsView.swift`: a `NavigationStack` wrapping a `Form`, with these sections:
  - **Library:** a link to `ExerciseListView`.
  - **Defaults for new sets:** `RepsStepper`, `WeightField` and `RestStepper`.
  - **Weight step:** a picker.
  - **Rest-end alert:** Sound and Haptics toggles.
- Everything is bound to `@AppStorage` through the `AppSettings` keys. The Settings tab in `RootTabView` now shows `SettingsView`.

## Hooks left for later phases
- `SetStatus.pending`, the session fields and `Workout.sessions` are already in V1. Phase 3 may add more V1 fields, such as pause and rest timestamps, until V1 is frozen.
- **Phase 2: unsaved edits and the shared context.** `ExerciseLibrary` calls `save()` and `rollback()` on the whole main context, so they also commit or discard any unsaved edits elsewhere. Phase 2's plan must decide how the template editor keeps its unsaved edits apart, for example a separate `ModelContext` or saving after every edit.
- Phase 2 must handle templates left with no exercises after an exercise is deleted. It reuses `ExerciseGrouping` (with the group filter), the value controls and `AppSettings.current`.
- Phase 4: the Haptics toggle may not be honoured while the app is in the background (local notifications follow system settings). Revisit its wording then.
- Every model has a stable `id` for the export in phase 7.

## Verification
- Each step: the CLAUDE.md build and test commands on iPhone 17 / OS 27.0 come out green, and code-reviewer reviews the step.
- Steps 1–3: also run the tests on `iPhone 16, OS=18.2`. At the end of the phase, run the full iOS 18.2 test run once more. CI doesn't cover iOS 18.
- Manual check in the simulator:
  - The first launch shows 43 exercises, grouped by muscle group.
  - Add "bench press": it's rejected as a duplicate.
  - Delete Bench Press: the warning says it stays in history. Then add "Bench Press": it's allowed.
  - Relaunch: nothing is seeded twice.
  - Change the settings and relaunch: the values persist.
  - Entering 22,5 in a Czech region is accepted.
  - The delete alert's title doesn't go blank while the alert closes (step 6 review, finding 5).
  - When adding an exercise, the cursor starts in the name field.
  - kg field editing, which was traced by hand in review but can't be unit-tested: backspace a value to empty and type a new one; clear it and tap Done (the original value comes back); press +/− while editing; type 22,5 with a US region.


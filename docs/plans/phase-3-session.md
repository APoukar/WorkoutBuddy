# Phase 3 — Active session, summary and save

Covers `FEATURES.md` §7 phase 3: running a workout in the foreground (F3) and the workout summary with Save (F5). It builds on phase 2 (`docs/plans/phase-2-templates.md`), whose "Hooks left for later phases" this plan answers for phase 3.

**How this plan was agreed.** The user asked for phase 3 to be planned and built autonomously overnight (2026-10-25). The main session therefore settled the `architect-reviewer` and `code-reviewer` findings itself instead of discussing them first. Every such decision is listed under "Review decisions made without the user" at the end, with the reason, so the user can revisit any of them in the morning.

All work goes on the branch `phase-3-session`. Nothing is pushed and no PR is opened without the user.

## Workflow
The main session only orchestrates. It writes no Swift app or test code. For every step:
1. Run `implementer` with this plan's path and the step number.
2. Handle anything it lists under "Needs main session".
3. Run `code-reviewer` with the plan, the step and the implementer's report.
4. Settle the findings (normally with the user; this time by the main session, logged at the end of this plan). Agreed fixes go through `implementer` too, never as direct edits.
5. Once the build and tests are green, commit the step as `Phase 3, step N: <what it did>`. If the plan changed because of the step, commit the plan in the same commit.

## Scope
- **In scope:** F3 (start, set screen, rest screen with the in-app alert and auto-advance, skip set, skip rest, undo, pause, end early, discard, keeping the screen awake, recovery after the app was killed) and F5 (summary with duration, set counts and volume; Save). The Workouts list's "Last done" date starts showing real sessions.
- **Out of scope, for later phases:**
  - Phase 4: the Live Activity, the rest-end local notification, the notification permission prompt. Phase 3 plays the rest-end sound and haptic only while the app is in the foreground.
  - Phase 5: the History tab and session detail.
  - Phase 6: personal records. The summary doesn't show a "New records" section yet (see Decisions).

## Decisions
- **One state machine, stored on the models.** The session's progress lives entirely in SwiftData, saved after every action, so a killed app resumes exactly where it was. Two fields are added to `WorkoutSession` (schema V1 is still edited in place; no data is on a device yet):
  - `pausedAt: Date?` — set while the workout is paused.
  - `restEndsAt: Date?` — set while a rest countdown runs (and, after it expires, until the next action clears it).
  - `lastActionAt: Date?` — when the last action ran (added in the step 4 review), so End & Save can end a recovered workout at the right time.
  Everything else is derived: the current set is the **first pending set** in order (sets are always done in order); the session is **resting** when `restEndsAt` is later than the effective time; it is **finished** (waiting for Save on the summary) when `endedAt` is set while the status is still `inProgress`.
- **Effective time.** All derived values are computed at `endedAt ?? pausedAt ?? now`, so a finished or paused workout is frozen. Elapsed time = effective time − `startedAt` − `pausedDuration`. Rest remaining = `restEndsAt` − effective time, rounded **up** to whole seconds, so the countdown reads 0:01 until it really ends.
- **Pause and resume.** Pause sets `pausedAt = now`. Resume adds `now − pausedAt` to `pausedDuration` and, if a rest is still running, moves `restEndsAt` later by the same amount, then clears `pausedAt`. Pausing is possible on the set screen and the rest screen.
- **Every action first clears an expired rest.** If `restEndsAt` is at or before the effective time, it's set to `nil` before the action runs. This keeps a stale `restEndsAt` from being moved into the future by a later resume.
- **Actions name the set they act on.** Done, Skip Set and Undo pass the ID of the set the screen showed. If it isn't the set the action applies to now (the current set, or the Undo target), the action does nothing. A double tap on Done for a set with 0 rest, or a tap on the outgoing screen during the cross-fade, can't complete or skip the next set too (architect finding 1).
- **Done** saves the shown reps and kg as the actual values, the status `done` and `completedAt = now`. Then:
  - if no pending set is left, the workout **finishes** (`endedAt = now`) and the summary shows;
  - else if the set's planned rest is above 0, `restEndsAt = now + plannedRestSeconds` and the rest screen shows;
  - else the next set opens right away.
- **Skip set** saves the set as `skipped`, clears any actual values (an Undo may have left some), stamps `completedAt = now` and never starts a rest. It opens the next set, or finishes the workout if it was the last one. `completedAt` therefore means "resolved at" for done and skipped sets; the model comment says so (architect finding 12).
- **Finishing always clears the transient state.** Every path that sets `endedAt` (Done or Skip Set on the last set, End Workout, End & Save) also sets `pausedAt = nil` and `restEndsAt = nil`, after folding a running pause into `pausedDuration` (architect finding 3).
- **Undo (§6 default).** The rest screen has an **Undo** button. It turns the set whose rest is running (the last `done` set before the current pending set) back to `pending`, clears its `completedAt` and the rest, and **keeps its actual values**, so the set screen opens with what was entered. The set screen pre-fills from the actual values when they exist, otherwise from the plan. There's no undo for the last set (it has no rest screen) and none after the rest has ended.
- **Edits on the set screen** are view state until Done. A kill mid-edit restores the pre-fill. A change to kg applies to that set only (§6 default): the next set pre-fills from its own plan.
- **Rest end in the foreground.** When the countdown reaches 0 while the app is active, the app plays the rest-end haptic and sound (each only if its Settings toggle is on), clears the rest (an action, saved) and shows the next set. Coming back to the app after the rest ended in the background shows the next set already, with no sound (phase 4's notification covers the background). "Reached 0 while active" means the app noticed within 2 seconds of `restEndsAt`.
  - Haptic: `UINotificationFeedbackGenerator` `.success`. Sound: the bundled `WorkoutBuddy/Resources/RestEnd.caf` (a short two-tone chime, synthesized by the main session, so there are no licence questions), registered once with `AudioServicesCreateSystemSoundID` and played with `AudioServicesPlaySystemSound`. It follows the ring/silent switch and mixes with music. Phase 4 reuses the same file for the notification sound (`UNNotificationSound(named:)`) (architect finding 15).
- **End early.** "End Workout" is reached from the pause overlay (F3). If at least one set is `done`, a confirmation "End Workout?" / "The remaining sets will be saved as not performed." with **End Workout** (destructive) and Cancel. Confirming marks every pending set `notPerformed` (clearing any actual values left by an Undo), folds a running pause into `pausedDuration`, clears the rest, sets `endedAt = now` and shows the summary. If **no** set is `done` (skipped sets don't count), the confirmation instead reads "Discard Workout?" / "No sets were completed, so nothing will be saved." with **Discard Workout** (destructive) and Cancel; discarding deletes the session.
- **Summary and Save (F5).** The summary is part of the full-screen session view. Its title is "Workout Complete", or "Workout Ended" when any set is `notPerformed`. It shows the workout name, the duration excluding pauses, sets completed and skipped (and "not performed" when the workout ended early), and the total volume. **Save** sets the status (`endedEarly` when any set is `notPerformed`, otherwise `completed`) and closes the full-screen view.
- **A workout with no done set is never saved** (architect finding 4; a gap in the spec, decided without the user — see the log at the end). If every set was skipped, the workout still finishes and shows the summary, but instead of Save the summary offers **Discard Workout** (destructive, with the same "Discard Workout?" confirmation). This applies F3's end-early rule to the natural end too, so History never gets a dot and the list never gets a "Last done" date for a workout where nothing was lifted. Until Save, the session stays `inProgress` with `endedAt` set, so it isn't in history and doesn't count for "Last done"; a kill on the summary brings the summary back on the next launch.
- **Volume** = Σ actual reps × actual kg over `done` sets. It is shown as a number with "kg" ("4,250 kg"), and 0 shows as "0 kg", not "Bodyweight", because it's a total, not a set's weight.
- **Duration** is shown as hours and minutes ("1 hr, 5 min"), or "45 sec" under a minute, using the system's abbreviated unit style.
- **No personal records yet.** F5 lists new PRs in the summary, but PR detection is F8, built in phase 6. The summary leaves a clearly marked place for it (see Hooks).
- **Only one active session.** "Active" means status `inProgress` (running or waiting for Save). `SessionLibrary.start` refuses to start while one exists. In the UI the full-screen session covers everything, so the user can't reach Start Workout anyway.
- **Start refuses** a soft-deleted template and one that can't start (`WorkoutLibrary.canStart`). It copies the template's rows that have an exercise, in order, with their planned numbers (`SessionSet.planned…`). Names are never copied.
- **Recovery after the app was killed.** On launch, an active session that is running (no `endedAt`) is not shown straight away. An alert asks first: "Resume Workout?" / "“Push Day” was still in progress." (or "Your workout was still in progress." if the template reference is gone) with **Resume** and **End & Save**; when no set is `done`, the second button is **Discard** (destructive) instead. A session waiting for Save on launch reopens its summary without asking.
  - **End & Save** ends the workout early and saves it straight to history (`endedEarly`), without the summary. Its `endedAt` is the **last recorded activity** (`pausedAt` if paused, else the latest of `lastActionAt`, the `completedAt` of done or skipped sets, and `startedAt`), not the launch time, so a workout recovered the next morning doesn't last 14 hours. A running pause is folded in up to that time.
  - "On launch" means once per process: a session found running when the app process starts was interrupted. The "launch check done" flag lives in a process-wide static and starts `false`; the cover isn't presented until the check has run, so it can't flash up before the alert (architect finding 11).
- **Save and End & Save share one `finalize`** that sets the final status. Phase 6 hooks PR detection into it, so sessions saved either way get their records (architect finding 12).
- **No undo from the summary** (architect finding 5, kept as the §6 default). An accidental Done on the last set, or on a set with 0 rest, can't be undone. Offered to the user as a possible later addition.
- **Keep awake.** `UIApplication.shared.isIdleTimerDisabled` is true while the full-screen session view is shown, and reset when it closes.
- **Presentation.** `RootTabView` presents the session with `.fullScreenCover`, driven by a `@Query` of `inProgress` sessions (raw-string predicate, as the schema comment requires) sorted by `startedAt` descending, so Start, Save, Discard and recovery only change the store and the cover follows. The cover and `SessionLibrary.activeSession()` both use the first (newest) result. The cover gets only the session **ID**, never a model. The cover has no swipe-to-dismiss.
- **Deleted sessions never crash the view** (architect finding 2). `ActiveSessionView` reads its session with its own `@Query(filter: #Predicate { $0.id == sessionID })` and builds the value snapshot in `body`; when the row is gone (after Discard, before the cover closes) it renders `Color.clear`. Every child view (set, rest, paused, summary) gets only the snapshot and plain values, never a model.

## Folder layout
- `WorkoutBuddy/Features/Session/`: the pure session logic, `SessionLibrary`, the texts and all session views.
- `WorkoutBuddy/Shared/Controls/`: the large reps and kg controls.
- `WorkoutBuddyTests/Features/Session/` mirrors it.

## Key design decisions
- **Actor isolation**, as in earlier phases: the pure types (`SessionSnapshot`, `SessionProgress`, `SessionStats`, `SessionMessages`, `LaunchRecovery`, `RestAlertRules`) are `nonisolated`, `Equatable` where useful, and take `now`/`locale` as parameters for tests. `SessionLibrary` and the views stay on `MainActor`.
- **`SessionSnapshot`** is a value copy of a session (timing fields plus an ordered list of sets with exercise index, set index, exercise ID, planned and actual values, status). Every decision ("what's on screen", "what Undo reverts", stats) is a pure function of a snapshot and a time, so it's unit tested without SwiftData. `SessionLibrary` builds a snapshot from the models, decides with the pure code, and writes back.
- **`SessionLibrary`** is a `@MainActor` struct wrapping a `ModelContext`, like `WorkoutLibrary`. Every action takes `now: Date = .now`, applies "clear an expired rest" first, saves once, rolls back on failure and rethrows. An action that doesn't apply in the current state (Done while resting, Undo with no rest, Resume when not paused) does nothing and doesn't throw. Phase 4 hooks its notification and Live Activity updates into these actions, so every state change goes through them.
- **Model rules from earlier phases still apply:** children are inserted and linked by their to-one (`sessionExercise.session = session`), orders come from the template's order, `#Predicate` never goes through optional relationships, and lookups by ID never filter.
- **Timer texts are rendered by the system** (architect finding 10): `Text(timerInterval:pauseTime:countsDown:showsHours:)`, the same API the Live Activity uses in phase 4. Elapsed: the interval starts at `startedAt + pausedDuration`, with `pauseTime: pausedAt` while paused. Rest: the interval ends at `restEndsAt`, counting down, with `pauseTime: pausedAt` while paused. They tick exactly on the second, keep running without redraws, and VoiceOver reads them (marked `.updatesFrequently`). Only the rest progress ring uses a `TimelineView` (`.animation` schedule, or `.periodic(from: restStart, by: 1)` with Reduce Motion). The rest auto-advance is a `.task(id:)` that sleeps until `restEndsAt` and then re-checks the stored state; it's cancelled by pause, skip, undo and leaving the screen. Scene-phase changes re-read the state.
- **Numeric input** on the set screen: large − / + buttons around a large value, which can also be typed into, using the phase 1 UIKit `DecimalTextField` (number pad for reps, decimal pad for kg) with its own Done bar. Never SwiftUI's `.keyboard` toolbar placement. The text ↔ value handling of `WeightField` (follow every keystroke that parses, keep `valueAtFocus` for empty or invalid text, reformat on blur, rewrite only when needed) is extracted once, generic over the value with `parse`/`format` closures, and shared by `WeightField` and both large controls (architect finding 7).
- **Big numbers** (architect finding 6): `DecimalTextField` gets a font configuration (base point size, weight, rounded design, monospaced digits, the text style it scales with, and a maximum point size), built with `UIFontMetrics(forTextStyle:).scaledFont(for:maximumPointSize:)` and keeping `adjustsFontForContentSizeCategory`. The default stays today's body font. At accessibility text sizes the − / + buttons move under the value, as `WeightField` already stacks.
- **Gym use:** the Done button is the biggest target on the screen (`.borderedProminent`, `.controlSize(.extraLarge)`, full width). − and + are at least 60 pt. The content scrolls at accessibility text sizes instead of clipping.
- **Pinned bottom actions** (architect finding 8): `WorkoutDetailView`'s private `StartBar` moves to `Shared/BottomActionBar.swift` as `.bottomActionBar { … }` taking a view builder (`safeAreaBar` on iOS 26+, `safeAreaInset` with a `.bar` background before). The detail's Start button, Done / Skip Set, Skip Rest / Undo and Save all use it, so the main action is always at the bottom in thumb reach, even at the largest text size.
- **Shared formatting** lives in `Formatters` (architect finding 9), so History (phase 5) and the Live Activity (phase 4) can reuse it: `duration(seconds:)` ("1 hr, 5 min", "45 sec") with a spoken form, and `volume(_:)` (`kg(_) + "\u{00A0}kg"`, no Bodyweight substitution). The rest countdown's static texts use the existing `Formatters.rest` and `spokenDuration`.
- **Logging** uses `ErrorLogging.log` with a fixed action string and the category `"session"`. Failed actions show `.errorAlert` with `SessionMessages.failureMessage(for:)`.
- **Previews:** `Features/Session/SessionPreviewData.swift` builds on `WorkoutPreviewData.container()` and starts sessions of "Push Day" in useful states (first set, resting, paused, finished, ended early). Compiled in every configuration (no `#if DEBUG`).

## Steps

**Step 1 — Schema fields and the pure session snapshot**
- `SchemaV1.WorkoutSession`: add `pausedAt: Date?` and `restEndsAt: Date?`, both `nil` by default, as optional init parameters.
- `Features/Session/SessionSnapshot.swift` (`nonisolated`, `Equatable`, `Sendable`, no SwiftData or SwiftUI import):
  - `SessionSnapshot.Entry` (not `Set`, which would shadow `Swift.Set`): `id`, `exerciseIndex`, `setIndex` (within its exercise), `exerciseID: UUID?`, `planned: SetValues`, `actualReps: Int?`, `actualKg: Double?`, `status: SetStatus`, `completedAt: Date?`.
  - `SessionSnapshot`: `startedAt`, `endedAt`, `pausedDuration`, `pausedAt`, `restEndsAt`, `status: SessionStatus`, `exerciseCount`, `entries: [Entry]` in session order, and `setCount(ofExercise:)`.
  - Derived, all taking `now`:
    - `effectiveTime(now:)` = `endedAt ?? pausedAt ?? now` (a finished session is frozen at `endedAt`).
    - `elapsed(now:) -> TimeInterval` (never negative).
    - `currentSetIndex` (first pending set, or `nil`), `isFinished` (`endedAt != nil`), `isPaused` (`pausedAt != nil && endedAt == nil`), `hasDoneSet`.
    - `restRemaining(now:) -> Int?`: whole seconds rounded up, `nil` when there's no rest or it has expired.
    - `screen(now:) -> SessionScreen`: `.set(index)`, `.rest(index of the next set, remaining)`, `.summary`. A rest whose next set doesn't exist can't happen (the workout finishes instead), but if the data says so, show `.summary` when finished or the set screen otherwise.
    - `undoTargetIndex(now:)`: the done set right before the current set, only while resting.
    - `prefill(forSetAt:) -> (reps: Int, kg: Double)`: actual values if present, else planned.
    - `lastActivity`: `pausedAt`, else the latest `completedAt` of a done or skipped set, else `startedAt`. (Step 4 review: also `lastActionAt`, see the decisions.)
- `SchemaV1.SessionSet.completedAt` gets a comment: "when the set was resolved (done or skipped)".
- Tests (`SessionSnapshotTests`), no SwiftData, fixed dates:
  - elapsed: running, paused (frozen), after resume with `pausedDuration`, finished (frozen at `endedAt`, even if `pausedAt` were left set), never negative
  - `isPaused` is false once finished
  - rest remaining: rounding up (e.g. 89.2 s → 90), exactly at `restEndsAt` → `nil`, frozen while paused
  - screen: first set, rest, rest expired → next set, last set done → summary, all skipped → summary
  - undo target: only while resting; `nil` after expiry and on the set screen
  - prefill: from plan, from actual values after an undo
  - `lastActivity` in each case
- Extend `SchemaV1Tests`: the new fields default to `nil` and persist.
- Also run the tests on iOS 18.2.

**Step 2 — Session texts and stats (pure)**
- `Shared/Formatters.swift`: `duration(seconds:)` ("1 hr, 5 min", "45 sec", using the system's abbreviated units) with `spokenDuration`-style spoken form if it differs, and `volume(_:)` ("4,250 kg", "0 kg"). Tests in `FormattersTests`.
- `Features/Session/SessionStats.swift` (`nonisolated`): from a snapshot — `doneCount`, `skippedCount`, `notPerformedCount`, `volume` (Σ actual reps × actual kg over done sets), `duration` (= `elapsed` at `endedAt`), `endedEarly` (any not performed), `canSave` (`doneCount > 0`).
- `Features/Session/SessionMessages.swift` (`nonisolated`), every text with a spoken form where it's read differently:
  - positions: "Exercise 2 of 5", "Set 3 of 4"
  - the "Next" preview on the set screen: "Next: Set 4 · 10 × 60 kg" within the same exercise, "Next: Overhead Press · 8 × 40 kg" for the next exercise (the name is passed in; names are looked up by the caller), "Last set" when none is left. Uses `SetSummary.line`, so 0 kg reads "Bodyweight".
  - the rest screen's "Up next" line, which always names the exercise (the rest screen has no exercise title): "Bench Press · Set 2 · 8 × 62.5 kg".
  - summary: title ("Workout Complete" / "Workout Ended"), set counts ("8 completed", "1 skipped", "3 not performed") with correct singulars, using `Formatters.duration` and `Formatters.volume`. For a workout with no done set, the note above the Discard button: "No sets were completed, so this workout can't be saved."
  - confirmations: "End Workout?" and "Discard Workout?" titles and messages, the recovery alert title and message ("“Push Day” was still in progress.", the name passed in by the caller from the reference, soft-deleted or not; "Your workout was still in progress." when there's no name).
  - `failureMessage(for:)` mapping `SessionError` (step 3) and other errors (`ErrorMessages.generic`).
- Tests: every text, singulars, 0 kg and Bodyweight, `en_US` and `en_CZ` for numbers (the volume grouping and decimal separator), and the stats, including volume with Bodyweight sets (0) and ignoring skipped and not-performed sets.

**Step 3 — `SessionLibrary`: start, active session and the set actions**
- `Features/Session/SessionLibrary.swift`. It uses `SessionError` (`.alreadyActive`, `.cannotStart`) from `Features/Session/SessionError.swift`, which step 2 created; don't declare it again.
- `activeSession() throws -> WorkoutSession?`: the session with status `inProgress` (raw-string predicate). If several exist (only possible through a bug), the newest `startedAt` wins and the result is logged.
- `snapshot(of:) -> SessionSnapshot`, built from `orderedExercises` / `orderedSets`.
- `start(_ workout: Workout, now:) throws -> WorkoutSession`: refuses `.alreadyActive` and `.cannotStart` (soft-deleted, or `!WorkoutLibrary.canStart`) before changing anything; inserts the session, its `SessionExercise`s (rows with an exercise only, renumbered from 0) and `SessionSet`s with the planned numbers copied and status `pending`; saves once.
- Actions, each as described in the Decisions: `completeSet(in:setID:reps:kg:now:)` (reps clamped, kg snapped), `skipSet(in:setID:now:)`, `skipRest(in:now:)`, `undo(in:setID:now:)`, `finishRest(in:now:)` (the foreground auto-advance: clears an expired rest; a no-op otherwise). The set actions do nothing unless `setID` is the set they apply to right now (the current set; for Undo, the undo target), so a stale screen or a double tap can't touch the wrong set. Done, Skip Set, Skip Rest and Undo also do nothing while paused (the overlay hides them, and Done would compute the rest from the frozen time); `finishRest` still clears a rest that expired before the pause (step 3 implementer, accepted in review).
- Tests (in-memory container, fixed dates):
  - start copies rows in order, the planned numbers and the exercise refs; skips rows without an exercise; doesn't copy names (renaming the exercise later changes what the session shows); refuses a second session, a soft-deleted template and an empty template without changing the store
  - editing the template after start leaves the session's planned numbers alone
  - done with rest → resting; with rest 0 → next set; last set → finished with `endedAt`
  - actual values are stored clamped and snapped
  - skip → next set without rest, `completedAt` stamped; skipping the last set finishes; finishing clears `pausedAt` and `restEndsAt`
  - skip rest, undo (values kept, `completedAt` cleared), undo after expiry does nothing; undo then skip leaves no actual values
  - a second Done or Skip with the previous (stale) set ID changes nothing, also for a set with 0 rest; Undo with a wrong ID changes nothing
  - an expired rest is cleared by the next action
  - every action reads back correctly from a fresh `ModelContext(tc.container)` (progress is saved)
  - an action on a finished session does nothing
- Also run the tests on iOS 18.2.

**Step 4 — `SessionLibrary`: pause, end, discard, save and recovery**
- `pause(in:now:)`, `resume(in:now:)` (shifts a running rest).
- `endEarly(in:now:)`: refuses (no-op) when no set is done; otherwise marks pending sets `notPerformed`, clears their actual values, folds a running pause in and clears `pausedAt`, clears the rest, sets `endedAt`.
- `discard(_:)`: deletes the session (cascade removes its exercises and sets).
- `save(_:)`: on a finished session with a done set, calls `finalize`; refuses (no-op) without a done set.
- `endAndSave(_:)` for recovery: ends early at `lastActivity` (clearing `pausedAt` and the rest) and calls `finalize`, committed in one `save()`.
- private `finalize(_:)`: sets the status from `SessionStats.endedEarly`. Phase 6 adds PR detection here.
- `Features/Session/LaunchRecovery.swift` (`nonisolated`): `decide(snapshot) -> .nothingToRecover / .askResume(canSave: Bool) / .showSummary`. A session with no pending set but no `endedAt` (only bad data can produce it) counts as `.showSummary`, and `save` first sets its `endedAt` to `lastActivity`, so the user is never stuck (step 1 review).
- Tests:
  - pause freezes elapsed and rest remaining; resume adds to `pausedDuration` and shifts `restEndsAt`; pause after the rest expired and resume later doesn't bring the rest back
  - end early while paused: not paused afterwards (`pausedAt == nil`, `isPaused` false), and the duration equals the active time only (the pause isn't subtracted twice)
  - end early: not-performed marking, actual values of an undone set cleared, duration excludes pauses; refused with no done set (also when sets were skipped)
  - save refuses a finished session where every set was skipped
  - a session with every set resolved but no `endedAt`: recovery shows the summary, and save sets `endedAt = lastActivity` and finalizes
  - discard removes the session and its children from the store (fetch them)
  - save: completed vs ended early; the session then counts for `WorkoutLibrary.lastPerformed` and is no longer active
  - end and save: `endedAt` = last activity in each case, status `endedEarly`
  - recovery decisions for each state
- Also run the tests on iOS 18.2.

**Step 5 — Large value controls and the shared bottom bar**
- Extract the text ↔ value handling from `WeightField` into a shared piece in `Shared/Controls/` (for example a `NumericTextEditing` view modifier), generic over the value with `parse` and `format` closures. `WeightField` uses it and behaves exactly as before.
- `Formatters.parseReps(_:)` → `Int?` (ASCII digits only, no sign or separator) and `Formatters.committedReps(text:current:)` (parsed and clamped to `repsRange`, or `current`), matching `committedKg`.
- `DecimalTextField` gains a font configuration (see "Big numbers"), defaulting to today's body font so existing uses don't change.
- `Shared/Controls/LargeRepsControl.swift` and `LargeWeightControl.swift`: label above ("Reps", "Weight (kg)"), − button, big value that can be tapped and typed into, + button. Reps step 1 within `AppSettings.repsRange`; kg step from Settings (`WeightStep`), snapped, within `kgRange`. The kg control shows the number (0 stays "0", as in other editing controls). − and + are disabled at the ends of the range, at least 60 pt, and move under the value at accessibility text sizes.
- VoiceOver (architect finding 13): each control is **one** adjustable element ("Reps, 10"; "Weight, 60 kilograms") with increment/decrement, plus a named action "Edit Value" that focuses the text field. The − / + buttons are hidden from VoiceOver.
- Move `WorkoutDetailView`'s private `StartBar` layout to `Shared/BottomActionBar.swift` as `.bottomActionBar { … }` with a view builder; `WorkoutDetailView` uses it with no visible change.
- Tests: `parseReps`, `committedReps`; the existing `WeightField`/`Formatters` tests stay green unchanged.
- Previews: both controls at default and accessibility text sizes.
- Run the Release build too (previews).

**Step 6 — Set screen, rest screen and pause overlay (views only)**
- Views take plain values and callbacks, no model access, so they're previewable:
  - A shared header: the workout name, the elapsed time (system timer text, see "Timer texts"; label "Elapsed time") and a Pause button (`pause.fill`, label "Pause").
  - `SetScreenView`: the header; exercise name (large title), "Exercise 2 of 5 · Set 3 of 4"; `LargeRepsControl` and `LargeWeightControl` bound to view state pre-filled from `prefill`; the "Next: …" line; **Done** and **Skip Set** (`.bordered`, secondary) in `.bottomActionBar`. The pre-fill state is keyed by set ID so it resets for each new set. Done and Skip report the set ID they were shown for.
  - `RestScreenView`: the header; "Rest" title; a large system countdown (monospaced digits, `lineLimit(1)`, `minimumScaleFactor`) inside a circular progress ring (`Circle().trim`, no animation under Reduce Motion); "Up next" with exercise name and `SetSummary.line`; **Skip Rest** (prominent) and **Undo** (secondary, `arrow.uturn.backward`) in `.bottomActionBar`. VoiceOver reads the countdown with the label "Rest remaining" and the `.updatesFrequently` trait.
  - `PausedOverlayView`: dimmed material over the screen, "Paused", the frozen elapsed time, **Resume** (prominent) and **End Workout** (destructive). Traps VoiceOver focus (`.accessibilityAddTraits(.isModal)`).
- Previews for each with sample values, including Bodyweight (0 kg) and a long exercise name, and at an accessibility text size.
- Run the Release build too.

**Step 7 — Active session view and summary**
- `Features/Session/RestAlertRules.swift` (pure): `shouldPlayAlert(restEndsAt:noticedAt:)` with the 2-second window; tests.
- `Features/Session/RestAlert.swift`: plays the haptic and the bundled `RestEnd.caf` (already in `WorkoutBuddy/Resources/`, added by the main session) according to `AppSettings.current()`. The sound ID is created once and reused; a missing file is logged, not fatal.
- `Features/Session/SessionSummaryView.swift` (values only, no models): title, workout name, duration, the counts, volume, and **Save** (prominent) in `.bottomActionBar`. Without a done set: the note and **Discard Workout** (destructive, with confirmation) instead of Save. A comment marks where phase 6 adds "New Records".
- `Features/Session/ActiveSessionView.swift`: takes the session **ID**, reads the session with its own `@Query(filter: #Predicate { $0.id == sessionID })`, builds the snapshot in `body` (renders `Color.clear` when the row is gone), and shows the set screen, rest screen or summary from `screen(now:)`, with the paused overlay on top when paused. It wires every callback to `SessionLibrary`, shows `.errorAlert` on failure, runs the rest auto-advance task (calls `finishRest`, then `RestAlert` if `shouldPlayAlert`), re-reads on scene-phase changes, shows the end/discard confirmation from the pause overlay (`confirmationDialog` anchored to the End Workout button), and keeps the screen awake while it's on screen. Screen changes use a short cross-fade (none with Reduce Motion). Transitions, `.id`s and tasks are keyed on a stable screen key (`.set(setID)`, `.rest(setID)`, `.summary`), never on `SessionScreen` itself, whose rest case carries the remaining seconds and changes every second; the auto-advance task is keyed on `restEndsAt` (step 1 review).
- Previews from `SessionPreviewData` (this step creates it): first set, resting, paused, finished, ended early.
- Run the Release build too.

**Step 8 — Wiring: Start Workout, the full-screen cover and recovery**
- `WorkoutDetailView`: Start Workout calls `SessionLibrary.start(workout)`; errors show `.errorAlert`. The button is also disabled for a soft-deleted template (the detail can still be open after a delete).
- `RootTabView`: `@Query` for `inProgress` sessions sorted by `startedAt` descending; `.fullScreenCover` with `ActiveSessionView(sessionID:)` for the first one, presented only after the launch check has run and while recovery isn't pending. The launch check runs once per process (a static flag): `LaunchRecovery.decide` → `.askResume` shows the recovery alert (Resume → shows the cover; End & Save → `endAndSave`; Discard → `discard`), `.showSummary` and `.none` let the cover follow the query.
- The Workouts list shows the real "Last done" date after a save (no code change expected; check it).
- Run the Release build too.

## Hooks left for later phases
- **Phase 4:** every state change goes through `SessionLibrary` actions: hook the rest notification (schedule on a rest start, cancel on skip rest, undo, pause, end and discard; reschedule on resume) and the Live Activity there. `SessionSnapshot` already carries everything the Live Activity needs (exercise index, set number, planned/prefill values, `restEndsAt`, elapsed), and the on-screen timers already use the same `Text(timerInterval:…)` API. Request notification permission on the first Start. The notification uses the bundled `RestEnd.caf`. Revisit the Settings "Haptics" wording (phase 1 hook).
- **Phase 5:** history shows `completed` and `endedEarly` sessions only (an `inProgress` one with `endedAt` is waiting for Save). Session names come from `session.workout`, which may be soft-deleted. Use `SessionStats`, `Formatters.duration` and `Formatters.volume`.
- **Phase 6:** the summary's "New Records" section; PRs computed in `SessionLibrary.finalize` (used by both Save and End & Save) and recalculated on delete.
- **Later (user's call):** an Undo on the summary for an accidental Done on the last set.
- **Phase 7:** export includes `pausedAt`, `restEndsAt` (normally `nil` for saved sessions) and `lastActionAt`.

## Verification
- Each step: the CLAUDE.md build and test commands on iPhone 17 / OS 27.0 come out green, the tests also pass on iPhone 16 / OS 18.2 (with `-parallel-testing-enabled NO` if the clone fails), and `code-reviewer` reviews the step. Run the Release build locally for steps that touch previews.
- At the end of the phase, run the full test suite on iOS 18.2 once more.
- **Manual check** (by the user, at the laptop; driving the simulator remotely is unreliable here), on iOS 27 and iOS 18.2:
  - Start "Push Day": the set screen opens full screen, the timer runs, the screen doesn't dim.
  - Change reps and kg with − / + and by typing (22,5 with a Czech region); Done saves them; the next set pre-fills from its own plan.
  - The rest countdown runs, Skip Rest and Undo work, and at 0 the phone plays the haptic and sound (toggle each off in Settings to check) and opens the next set.
  - A set with 0 rest goes straight to the next set; the last set goes straight to the summary.
  - Skip Set goes to the next set without rest.
  - Pause on the set and rest screens freezes both timers; Resume continues them; the summary's duration excludes the pause.
  - End Workout from the pause overlay: with a done set it asks to end and shows "Workout Ended" with not-performed sets; with none it offers Discard.
  - Background the app during a rest and come back after it ended: the next set is showing, without the sound.
  - Skip every set: the summary offers Discard Workout, not Save.
  - Discard from the pause overlay and from the summary closes the cover without a crash.
  - VoiceOver "Edit Value" on the reps and kg controls opens the keyboard.
  - The rest-end chime sounds right (it's synthesized; replace it if it doesn't).
  - Kill the app mid-workout and relaunch: no flash of the workout before the alert; Resume continues where it was (paused stays paused); End & Save saves it as ended early with a sensible duration; with no done set the alert offers Discard. Kill on the summary: it comes back.
  - Save: the Workouts list shows "Last done" today.
  - VoiceOver: the controls are adjustable, the countdown is readable, the paused overlay traps focus.
  - Largest accessibility text size: the set, rest and summary screens scroll without clipping; Done stays reachable.
  - Light and dark mode.

## Review decisions made without the user
The user was asleep, so the main session settled these. Each can be revisited.

**Architect review (2026-10-25), verdict "Approve with changes", 15 findings:**
1. Double tap on Done/Skip for a 0-rest set hits the next set → **accepted**: actions take the shown set ID and ignore a stale one.
2. Discard could crash a view still reading the deleted session → **accepted**: the session view uses its own ID `@Query`, children get values only, the cover gets only the ID.
3. Ending while paused left `pausedAt` set (double-subtracted pause, overlay over the summary) → **accepted**: finishing clears `pausedAt`/`restEndsAt`; `effectiveTime = endedAt ?? pausedAt ?? now`; `isPaused` false once ended.
4. **Needs the user (spec gap):** a workout with every set skipped could be saved as "completed" → **decided**: never save a session without a done set; the summary offers Discard instead of Save. `FEATURES.md` F3/F5 don't say this yet; the user should confirm and the spec be updated.
5. **Needs the user (optional):** no undo for an accidental Done on the last set → **kept the §6 default** (Undo only on the rest screen); listed under Hooks as a later option.
6. A text-style font parameter can't make the big typed number → **accepted**: `DecimalTextField` gets a scaled font configuration with a maximum size.
7. Reps would copy the kg text sync → **accepted**: the sync is extracted generically; `Formatters.committedReps` added.
8. Three screens would rewrite `StartBar` → **accepted**: shared `.bottomActionBar`.
9. Duration/volume formatting belongs in `Formatters` → **accepted**.
10. `TimelineView` ticks drift from the timestamps → **accepted the system-rendered timer texts** (`Text(timerInterval:pauseTime:countsDown:showsHours:)`); `TimelineView` only drives the ring.
11. The cover could flash before the recovery alert; cover vs `activeSession()` could pick different rows → **accepted**: process-wide launch flag gates the cover; both use the newest `startedAt`.
12. End & Save would bypass phase 6's PR hook; skips had no timestamp → **accepted**: shared `finalize`; skipped sets stamp `completedAt` ("resolved at").
13. The VoiceOver design of the large controls contradicted itself → **accepted**: one adjustable element plus an "Edit Value" action.
14. Test gaps and the `Set` name → **accepted**: undo → skip test, `SessionSnapshot.Entry`, recovery message fallback.
15. Undocumented system sound IDs → **accepted**: the main session synthesized `WorkoutBuddy/Resources/RestEnd.caf` (two-tone chime, 0.95 s, 16-bit PCM) for phase 3 and phase 4.

**Step 1 code review, verdict "Approve", 3 minor findings:**
1. All sets resolved but no `endedAt` (bad data only) would leave Resume → a summary whose Save does nothing → **accepted** into step 4: recovery shows the summary and `save` sets `endedAt = lastActivity`.
2. `SessionScreen.rest` changes every second → **accepted** into step 7: key transitions and tasks on a stable screen key and `restEndsAt`.
3. `FEATURES.md` §4 didn't list the new fields → **updated** §4 with `pausedAt`, `restEndsAt` and the "resolved at" meaning of `completedAt` (wording only, no behaviour change).

**Step 2 code review, verdict "Approve with fixes", 4 findings** (plus the implementer's deviations, accepted: `SessionError` defined in step 2 in its own file because `failureMessage` needs it; `SessionStats.init(_:now:)`; volume falls back to planned values for a done set without actual values, bad data only):
1. The rest screen's "Up next" dropped the exercise name within an exercise → **accepted**: it always names the exercise and the set ("Bench Press · Set 2 · 8 × 62.5 kg"); the set screen's "Next" keeps its rule.
2. The `.cannotStart` text advised adding an exercise, also for a deleted template → **accepted**: neutral "This workout can't be started."
3. Step 3 still said it defines `SessionError` → **accepted**: plan updated.
4. `duration` and `spokenDuration` look like a pair but aren't → **accepted**: cross-referencing doc comments, no rename.

**Step 3 code review, verdict "Approve with fixes", 4 minor findings** (plus the implementer's deviation, **accepted**: the set actions are no-ops while paused):
1. Missing tests for `finishRest` while paused and for `start` refusing while a session waits for Save → **accepted**, both added.
2. A test name promised a pause fold it couldn't reach → **accepted**: renamed; step 4's "end early while paused" covers the fold.
3. The last-set test didn't check the `endedAt` value → **accepted**.
4. The doc comment overstated the paused guard → **accepted**: names the set actions exactly.

**Step 4 code review, verdict "Approve with fixes", 5 findings:**
1. End & Save after a pause and resume that came after the last done set ended the workout too early, down to a 0-second duration → **accepted option (a)**: new `WorkoutSession.lastActionAt`, stamped by `start` and every action; `lastActivity` = `pausedAt` if paused, else the latest of `lastActionAt`, the set `completedAt`s and `startedAt`. `FEATURES.md` §4 lists the field.
2. `LaunchRecovery.none` clashes with `Optional.none` → **accepted**: renamed `.nothingToRecover`.
3. `discard` could delete a saved session → **accepted**: only in-progress sessions; history delete is a separate phase 5 operation.
4. Duplicated save/rollback code and test fixture → **accepted**: `commit` reused; shared `SessionFixture` for the session tests.
   - Follow-on (main session): every call that reaches `perform` stamps `lastActionAt`, including no-op taps (a stale ID, Done while paused). A tap still shows the user was there, so that's accepted; the "changes nothing" tests compare snapshots without `lastActionAt`.
5. End & Save on the bad-data case untested → **accepted**: test added; it saves as `completed`, because no set is left pending (only a caller bug reaches it; recovery shows the summary there).

**Step 5 code review, verdict "Approve with fixes", 3 minor findings** (plus the implementer's deviation, **accepted**: a shared `LargeValueControlLayout` for the two large controls). The reviewer rendered the controls in a scratch demo app on iOS 27 (default, XXXL, AX5) and iOS 18.2 (dark): nothing clips, "127,5" fits, the buttons move under the value at AX sizes.
1. The tested `Formatters.needsTextRewrite` was dead code and the rule the app runs was untested → **accepted**: the rule moved into `NumericTextEditing` and its existing tests now target it (an existing test changed, against the plan's "unchanged"; logged here), plus reps cases.
2. Font tests passed regardless of the code → **accepted**: exact sizes at given content sizes, rounded design and monospaced digits checked.
3. VoiceOver read "bodyweight" while the large kg control showed "0" → **accepted**: editing controls say "0 kilograms" (new `Formatters.spokenKilograms`, also used by `WeightField`, fixing its "1 kilograms").

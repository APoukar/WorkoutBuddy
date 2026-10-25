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
  - `lastActionAt: Date?` — when the last action ran (added in the step 4 review), so ending a recovered workout uses the right time.
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
- **Finishing always clears the transient state.** Every path that sets `endedAt` (Done or Skip Set on the last set, End Workout, the recovery End Workout) also sets `pausedAt = nil` and `restEndsAt = nil`, after folding a running pause into `pausedDuration` (architect finding 3).
- **Undo (§6 default).** The rest screen has an **Undo** button. It turns the set whose rest is running (the last `done` set before the current pending set) back to `pending`, clears its `completedAt` and the rest, and **keeps its actual values**, so the set screen opens with what was entered. The set screen pre-fills from the actual values when they exist, otherwise from the plan. There's no undo for the last set (it has no rest screen) and none after the rest has ended.
- **Edits on the set screen** are view state until Done. A kill mid-edit restores the pre-fill. A change to kg applies to that set only (§6 default): the next set pre-fills from its own plan.
- **Rest end in the foreground.** When the countdown reaches 0 while the app is active, the app plays the rest-end haptic and sound (each only if its Settings toggle is on), clears the rest (an action, saved) and shows the next set. Coming back to the app after the rest ended in the background shows the next set already, with no sound (phase 4's notification covers the background). "Reached 0 while active" means the app noticed within 2 seconds of `restEndsAt`.
  - Haptic: `UINotificationFeedbackGenerator` `.success`. Sound: the bundled `WorkoutBuddy/Resources/RestEnd.caf` (a short two-tone chime, synthesized by the main session, so there are no licence questions), registered once with `AudioServicesCreateSystemSoundID` and played with `AudioServicesPlaySystemSound`. It follows the ring/silent switch and mixes with music. Phase 4 reuses the same file for the notification sound (`UNNotificationSound(named:)`) (architect finding 15).
- **End early.** "End Workout" is reached from the pause overlay (F3). If at least one set is `done`, a confirmation "End Workout?" / "The remaining sets will be saved as not performed." with **End Workout** (destructive) and Cancel. Confirming folds a running pause into `pausedDuration`, clears the rest, sets `endedAt = now` and shows the summary. The pending sets stay pending until Save, which marks them `notPerformed` (clearing any actual values left by an Undo) (step 9). If **no** set is `done` (skipped sets don't count), the confirmation instead reads "Discard Workout?" / "No sets were completed, so nothing will be saved." with **Discard Workout** (destructive) and Cancel; discarding deletes the session.
- **Summary and Save (F5).** The summary is part of the full-screen session view. Its title is "Workout Complete", or "Workout Ended" when any set is `notPerformed`, a finished workout still has pending sets (step 9), or no set is done (step 7 review). It shows the workout name, the duration excluding pauses, sets completed and skipped (and "not performed" when the workout ended early), and the total volume. **Save** sets the status (`endedEarly` when any set is `notPerformed`, otherwise `completed`) and closes the full-screen view.
- **A workout with no done set is never saved** (architect finding 4; a gap in the spec, decided without the user — see the log at the end). If every set was skipped, the workout still finishes and shows the summary, but instead of Save the summary offers **Discard Workout** (destructive, with the same "Discard Workout?" confirmation). This applies F3's end-early rule to the natural end too, so History never gets a dot and the list never gets a "Last done" date for a workout where nothing was lifted. Until Save, the session stays `inProgress` with `endedAt` set, so it isn't in history and doesn't count for "Last done"; a kill on the summary brings the summary back on the next launch.
- **Volume** = Σ actual reps × actual kg over `done` sets. It is shown as a number with "kg" ("4,250 kg"), and 0 shows as "0 kg", not "Bodyweight", because it's a total, not a set's weight.
- **Duration** is shown as hours and minutes ("1 hr, 5 min"), or "45 sec" under a minute, using the system's abbreviated unit style.
- **No personal records yet.** F5 lists new PRs in the summary, but PR detection is F8, built in phase 6. The summary leaves a clearly marked place for it (see Hooks).
- **Only one active session.** "Active" means status `inProgress` (running or waiting for Save). `SessionLibrary.start` refuses to start while one exists. In the UI the full-screen session covers everything, so the user can't reach Start Workout anyway.
- **Start refuses** a soft-deleted template and one that can't start (`WorkoutLibrary.canStart`). It copies the template's rows that have an exercise, in order, with their planned numbers (`SessionSet.planned…`). Names are never copied.
- **Recovery after the app was killed.** On launch, an active session that is running (no `endedAt`) is not shown straight away. An alert asks first: "Resume Workout?" / "“Push Day” was still in progress." (or "Your workout was still in progress." if the template reference is gone) with **Resume** and **End Workout** (step 9; was End & Save); when no set is `done`, the second button is **Discard** (destructive) instead. A session waiting for Save on launch reopens its summary without asking.
  - **End Workout** (step 9) ends the workout and opens the summary, where Save stores it (until step 9 it was "End & Save", which saved straight to history). Its `endedAt` is the **last recorded activity** (`pausedAt` if paused, else the latest of `lastActionAt`, the `completedAt` of done or skipped sets, and `startedAt`), not the launch time, so a workout recovered the next morning doesn't last 14 hours. A running pause is folded in up to that time.
  - "On launch" means once per process: a session found running when the app process starts was interrupted. The "launch check done" flag lives in a process-wide static and starts `false`; the cover isn't presented until the check has run, so it can't flash up before the alert (architect finding 11).
- **Every save goes through one `finalize`**, which marks the pending sets not performed and sets the final status. Phase 6 hooks PR detection into it, so sessions saved either way get their records (architect finding 12).
- **Back to Workout from the summary** (step 9; architect finding 5 had first kept the §6 default of no undo there). It reopens the workout, and after Done or Skip on the last set it brings that set back.
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
- **Timer texts are rendered by the system** (architect finding 10): `Text(timerInterval:pauseTime:countsDown:showsHours:)`, the same API the Live Activity uses in phase 4. Elapsed: the interval starts at `startedAt + pausedDuration`, with `pauseTime: pausedAt` while paused, and `showsHours: true` ("12:34", "1:02:03"). Rest: the interval ends at `restEndsAt`, counting down. **`pauseTime` doesn't freeze a countdown** (checked on iOS 27 and 18.2 in the step 6 review), so a paused rest shows a static `Formatters.rest` text of the frozen remaining time instead. They tick exactly on the second, keep running without redraws, and VoiceOver reads them (marked `.updatesFrequently`). Only the rest progress ring uses a `TimelineView` (`.animation` schedule, or `.periodic(from: restStart, by: 1)` with Reduce Motion). The rest auto-advance is a `.task(id:)` that sleeps until `restEndsAt` and then re-checks the stored state; it's cancelled by pause, skip, undo and leaving the screen. Scene-phase changes re-read the state.
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
- `RootTabView`: `@Query` for `inProgress` sessions sorted by `startedAt` descending; `.fullScreenCover` with `ActiveSessionView(sessionID:)` for the first one, presented only after the launch check has run and while recovery isn't pending. The launch check runs once per process (a static flag): `LaunchRecovery.decide` → `.askResume` shows the recovery alert (Resume → shows the cover; End Workout → `endForRecovery` (step 9; was End & Save → `endAndSave`); Discard → `discard`), `.showSummary` and `.none` let the cover follow the query.
- The Workouts list shows the real "Last done" date after a save (no code change expected; check it).
- Run the Release build too.

**Step 9 — Back to Workout from the summary; remaining sets marked on Save; recovery ends to the summary** (added after the user's manual check, 2026-10-25)
- **The summary is "ended, nothing final yet".** `endEarly` no longer marks pending sets: it only finishes (folds a running pause, sets `endedAt`, clears `pausedAt` and the rest). Pending sets stay pending, with any actual values an Undo left, until Save.
- **`SessionStats`:** in a finished session, pending sets count as not performed (`notPerformedCount`, `endedEarly`). The summary view and its texts don't change.
- **Save** (`save` → `finalize`): marks pending sets `notPerformed` (clearing their actual values and `completedAt`), then sets the status. Saved sessions never have pending sets.
- **`backToWorkout(in:now:)`:** only on a finished, unsaved session (`inProgress` with `endedAt`). Adds `now − endedAt` to `pausedDuration` (time on the summary doesn't count), clears `endedAt`, stamps `lastActionAt`. If no pending set is left (it ended by Done or Skip on the last set), the last resolved set goes back to `pending`, keeping its actual values and clearing `completedAt`, like Undo. The workout continues on the set screen, not paused. A rest that was running when the workout ended isn't restored.
- **Summary view:** a secondary **Back to Workout** button (`.bordered`) under Save or Discard Workout in the bottom bar.
- **Recovery:** the alert's second button is **End Workout** (not End & Save) when a set is done. It calls `endForRecovery(_:)` (replacing `endAndSave`): finish at `lastActivity`, no marking, no finalize, so the cover opens on the summary, where Save stores it. Discard is unchanged. `SessionMessages`: `recoveryEndButton` replaces `recoveryEndAndSaveButton`; add `backToWorkoutButton`.
- **`FEATURES.md`:** F3 robustness "offers Resume or End (which shows the summary)"; F5 "Back to Workout returns to the workout; time on the summary doesn't count"; §6 accidental Done also covers the last set via Back to Workout.
- Tests: update the step 4 tests that expected `notPerformed` right after `endEarly` (now: pending until Save, and not-performed after Save); stats count pending as not performed only when finished; `backToWorkout` after an early end (pending kept, pause and summary time excluded from the duration), after Done on the last set (that set back to pending with its values), after Skip on the last set, refused on a running or saved session; `endForRecovery` ends at `lastActivity` and leaves the session waiting for Save, then Save gives `endedEarly` with not-performed sets; recovery rules and messages.
- Run the full tests on **iPhone 17e** / OS 27.0 (the user is using iPhone 17 for the manual check) and on iPhone 16 / OS 18.2, and the Release build.

**Step 10 — Look back at earlier sets and correct them** (added after the user's manual check, 2026-10-25; the user chose "look back and edit" over "rewind", on the set screen and the summary; reviewed by `architect-reviewer` and agreed with the user, see the step 10 decisions at the end)
- **What it does.** From the set screen or the summary, the user can look at earlier finished sets (done or skipped), correct the reps and kg of a done set, mark a skipped set as done, or mark a done set as skipped. The workout's position, rests and timers don't change. Not available on the rest screen (the user's choice; Undo covers the set just done there).
- **Pure rules** (`SessionSnapshot`, tested): `reviewableIndices` = entries with status `done` or `skipped`, in order (before the current set while running; all of them once finished; not-performed and pending sets are never reviewable). `previousReviewIndex(from:)` and `nextReviewIndex(from:)`, where `from == nil` means "the current set or the summary"; `nextReviewIndex` returns `nil` past the newest reviewable set (back to the current set or summary).
- **`SessionLibrary`** (none of these goes through `perform`, which refuses finished sessions; none touches rests or pauses; stale IDs, other statuses and saved sessions are no-ops):
  - `editDoneSet(in:setID:reps:kg:now:)`: only on a `done` set of an `inProgress` session (running, or finished and waiting for Save). Stores clamped reps and snapped kg as the actual values; keeps `completedAt`. Does nothing at all (no save, no stamp) when the clamped and snapped values equal the stored ones. Stamps `lastActionAt` only while running, so a finished session keeps its `endedAt` and duration. Intermediate typed values are saved too (typing "100" saves 1, 10, 100); that's accepted.
  - `markSkippedAsDone(in:setID:reps:kg:now:)`: only on a `skipped` set; status `done` with the given values (clamped/snapped); keeps the skip's `completedAt`. Same stamping rule.
  - `markDoneAsSkipped(in:setID:now:)`: only on a `done` set; status `skipped`, actual values cleared (skipped sets have none), keeps `completedAt`. Same stamping rule. If it leaves a finished session without a done set, the summary switches to Discard as usual (`canSave`).
- **View structure** (architect findings 1, 8, 9):
  - The review is a **layer above** the live screen (`ZStack`): the set screen (or summary) underneath stays alive, so its unsaved reps and kg survive a look back; while reviewing, the layer underneath gets `.allowsHitTesting(false)` and `.accessibilityHidden(true)`. Text editing ends before review opens.
  - `ActiveSessionView` holds the reviewed entry **ID** in `@State`. Whether review shows is decided by looking the ID up in `reviewableIndices`; if it's no longer there (Discard, Back to Workout, bad data), the normal screen shows. The transition identity is (screen key, reviewed ID). The paused overlay and `.accessibilityHidden(paused)` cover the review layer too.
  - The set editor's scrolling content (title, position, large controls) is extracted from `SetScreenView` into a shared view with a slot (the "Next" line on the set screen, the status badge on the review screen). Each screen keeps its own bottom bar.
- **`SetReviewView`** (values and callbacks only, previewable):
  - Header: from the set screen, the live session header with Pause; from the summary, the time frozen at `endedAt` and **no Pause** (architect finding 2).
  - Exercise name, "Exercise 1 of 1 · Set 2 of 3", a status badge with a symbol and text ("Done" `checkmark.circle.fill` / "Skipped" `forward.fill`, not colour alone), `LargeRepsControl` and `LargeWeightControl`, seeded once per set ID (never re-seeded from the snapshot).
  - **Done set:** each change saves through `editDoneSet`, fired from `onChange` only (never on appear). A secondary **Mark as Skipped** button.
  - **Skipped set:** the controls start from the plan and can be changed; **Mark as Done** (the only prominent button) saves them. Leaving without marking discards those edits.
  - Bottom bar: **Back to Current Set** or **Back to Summary**, plus one compact row with **Previous** and **Next** (chevrons with text). At the newest set, Next acts as Back, matching the swipe (architect findings 6, 7).
- **Gestures** (architect finding 3): a UIKit `UISwipeGestureRecognizer` (left and right) through `UIGestureRecognizerRepresentable` (iOS 18+, no `#available`), recognising simultaneously with the scroll view so vertical scrolling and the steppers keep working. It's attached to the scrolling content, not the bottom bar (the home-indicator edge), and is off while a text field is focused or the workout is paused. Swipe right = previous; swipe left = next / back. Visible alternatives: a **Previous Set** button on the set screen (`chevron.backward` with text, near the position line; hidden when nothing is reviewable) and a **Review Sets** row on the summary. VoiceOver gets the same as named actions. Transitions slide from the matching edge; a cross-fade under Reduce Motion.
- **`FEATURES.md` F3:** "Earlier sets: on the set screen or the summary, swipe right (or tap Previous Set / Review Sets) to look back at finished sets. A done set's reps and kg can be corrected, a skipped set can be marked as done and a done set as skipped; the workout's position and timers don't change."
- Tests: the review index rules (running, finished, ended early with pending sets, nothing reviewable, skipping over not-performed); `editDoneSet` (clamped/snapped values, `completedAt` kept, a no-op edit changes nothing and doesn't stamp `lastActionAt`, a finished session's `endedAt` and duration unchanged, refused on pending/skipped/saved, stale ID); `markSkippedAsDone` (status and values; an all-skipped workout becomes saveable; refused on done, pending, not-performed and saved sets); `markDoneAsSkipped` (values cleared; the only done set → `canSave` false; refused otherwise); stats and volume reflect edits.
- Previews: review of a done set, a skipped set, Bodyweight, from the summary, an accessibility text size.
- Runtime check by the code reviewer on iOS 18.2 and 27 (scratch copy with another bundle ID): scrolling, − / +, typing and swiping together; the current set's draft surviving a look back.
- Run the full tests on iPhone 17e / OS 27.0 and iPhone 16 / OS 18.2, and the Release build. The iPhone 17 and iPhone 16 Pro simulators belong to the user's manual check.

## Hooks left for later phases
- **Phase 4:** every state change goes through `SessionLibrary` actions: hook the rest notification (schedule on a rest start, cancel on skip rest, undo, pause, end and discard; reschedule on resume) and the Live Activity there. `SessionSnapshot` already carries everything the Live Activity needs (exercise index, set number, planned/prefill values, `restEndsAt`, elapsed), and the on-screen timers already use the same `Text(timerInterval:…)` API. A paused rest must not rely on `pauseTime` for the countdown (it keeps ticking); show the frozen remaining time instead. Request notification permission on the first Start. The notification uses the bundled `RestEnd.caf`. Revisit the Settings "Haptics" wording (phase 1 hook).
- **Phase 5:** history shows `completed` and `endedEarly` sessions only (an `inProgress` one with `endedAt` is waiting for Save). Session names come from `session.workout`, which may be soft-deleted. Use `SessionStats`, `Formatters.duration` and `Formatters.volume`.
- **Phase 6:** the summary's "New Records" section; PRs computed in `SessionLibrary.finalize` (every save goes through it) and recalculated on delete.
- ~~**Later (user's call):** an Undo on the summary for an accidental Done on the last set.~~ Done in step 9 (Back to Workout).
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
  - Kill the app mid-workout and relaunch: no flash of the workout before the alert; Resume continues where it was (paused stays paused); End Workout opens the summary, and Save stores it as ended early with a sensible duration; with no done set the alert offers Discard. Kill on the summary: it comes back.
  - Save: the Workouts list shows "Last done" today.
  - VoiceOver: the controls are adjustable, the countdown is readable, the paused overlay traps focus.
  - Largest accessibility text size: the set, rest and summary screens scroll without clipping; Done stays reachable.
  - Light and dark mode. On iOS 18.2 in light mode, check that the bordered secondary buttons (Skip Set, Undo, End Workout) stand out enough from the bottom bar's `.bar` background (step 6 review).
  - With VoiceOver, the rest countdown reads "Rest remaining" before the time.

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

**Step 6 code review, verdict "Approve with fixes", 7 findings** (plus the implementer's deviations: Undo disabled without a target and combined accessibility elements with visible captions, **accepted**; `showsHours: false`, **rejected**, see 1). The reviewer rendered every screen in a scratch app on iOS 27 and 18.2, default and AX sizes, light and dark.
1. [Blocker] The elapsed time read "62:37" after an hour; `showsHours: true` gives "12:34" and "1:02:03" on both OS versions → **accepted**.
2. [Major] `pauseTime` doesn't freeze a countdown → **accepted**: a paused rest shows a static frozen time; the phase 4 hook says so.
3. The header squeezed the content at AX5 → **accepted**: the workout name is one line and the header's text size is capped at AX1.
4. The overlay's "Elapsed time" caption wasn't centred → **accepted**.
5. The rest countdown might read its value before its label → **accepted**: label first; also on the manual VoiceOver check.
6. The labels test only repeated constants → **kept** as a spelling lock, with the missing caption added.
7. Low contrast of bordered buttons over the iOS 18 `.bar` → **left as is**, added to the manual check.

**Step 7 code review, verdict "Approve with fixes", 7 findings** (plus the implementer's extra pure types `SessionScreenKey`, `SessionConfirmation`, `SessionSummaryContent`, fetching the session fresh by ID for each action, and the `applicationState` check in the rest task, all **accepted**). The reviewer ran the whole flow in a scratch app on iOS 27 and 18.2: auto-advance at 0 with the alert, pause/resume shifting the rest, 0-rest Done, Skip Rest, Undo, End Workout → summary → Save (`endedEarly`), Discard from the overlay and from the all-skipped summary without a crash, a rest ending in the background (cleared, no alert), and the idle timer.
1. The confirmation dialogs floated mid-screen on iOS 26+ instead of coming from their button → **accepted**: anchored to End Workout and Discard Workout, state kept in the owner.
2. The summary title sat on a white band above the grey list and didn't scroll → **accepted**: moved into the list.
3. A hard-coded "Workout" fallback → **accepted**: `SessionMessages.fallbackWorkoutName`.
4. The auto-advance rule was untested view code → **accepted**: `SessionSnapshot.autoAdvanceDeadline` with tests.
5. The expired-rest rule was written twice → **accepted**: `perform` uses `hasExpiredRest`.
6. A failed fetch made actions silently do nothing → **accepted**: logged and shown.
7. **Question for the user:** an all-skipped workout's summary said "Workout Complete" over "0 completed" and a Discard button → **decided**: "Workout Ended" whenever the workout can't be saved. Easy to change.

**Step 8 code review, verdict "Request changes", 3 findings.** The reviewer ran the real app on iOS 27 and 18.2, starting workouts and killing the app with `simctl terminate`: Start opens the cover; after a kill the recovery alert shows with no flash of the cover; Resume returns to the right screen; End & Save saves as ended early at the last activity and the list shows "Last done" today; a kill with no done set offers Discard; a kill on the summary brings the summary back without asking.
1. [Blocker] The Discard variant of the recovery alert got an automatic Cancel button that left the workout stranded behind a cover that never showed → **accepted**: Resume has the cancel role and the alert is driven by the recovery state, so any dismissal means Resume.
2. [Major] A second Start tap while the cover was presenting raised an alert under it that knocked the cover away → **accepted**: `.alreadyActive` is ignored in the detail screen (the cover already shows the workout).
3. [Minor] A failed End & Save or Discard during recovery showed the error at the same moment the cover presented → **accepted**: the recovery question stays and comes back after the error alert.

## Status (2026-10-25, end of the overnight run)
- Steps 1–8 are implemented, reviewed and committed on `phase-3-session`. Nothing is pushed and no PR is open.
- Final runs: the full suite passes on iPhone 17 / iOS 27.0 and on iPhone 16 / iOS 18.2 (430 tests each, counted from the `.xcresult`); the Release build succeeds and contains `RestEnd.caf`.
- Checked at runtime by reviewers (scripted, not by hand): the whole step 7 flow and the step 8 launch/recovery flow on iOS 27 and 18.2 (see the step 7 and step 8 review notes).
- **Still to do by the user:** the manual check under "Verification" (real taps, feel of the haptic, sound of the chime, VoiceOver, AX text sizes, iOS 18.2 contrast).
- **Decisions waiting for the user** (each one is easy to change):
  - Architect finding 4: a workout with no done set is never saved (Discard instead of Save). `FEATURES.md` F3/F5 should say so if agreed.
  - ~~Architect finding 5: no Undo on the summary for an accidental Done on the last set.~~ Added in step 9 (Back to Workout).
  - Step 7 finding 7: an unsaveable summary is titled "Workout Ended".
  - ~~Recovery's "End & Save" saves straight to history without showing the summary.~~ Changed by the user in the manual check: step 9.

**Step 9 code review, verdict "Approve with fixes", 4 findings.** The reviewer ran a scratch copy on iOS 27: Back to Workout after Done on the last set, recovery End Workout → summary → Back to Workout, and recovery after a paused workout → End Workout → Back to Workout → Done → Save all worked.
1. The plan still contradicted step 9 in three places → **fixed** in the plan.
2. Back to Workout did nothing in the bad-data summary (every set resolved, no `endedAt`) → **accepted**: a missing `endedAt` counts as `lastActivity`, as in `save`.
3. Sessions ended by the step 8 build and still waiting for Save already have not-performed sets; Back to Workout behaves oddly on them → **note for the manual check**: save or discard them first (old data only).
4. At AX5, Save plus Back to Workout take about 40% of the screen; the list still scrolls → **kept in the bar**; checked in the manual check at AX5.

**Step 10 architect review, verdict "Approve with changes", 10 findings, discussed with the user:**
1. Opening review would throw away the current set's unsaved values → **accepted**: review is a layer above the live screen.
2. Review from the summary would show a running timer and a dead Pause → **accepted**: frozen time, no Pause.
3. A SwiftUI `DragGesture` blocks scrolling on iOS 18 and clashes with text fields and the home indicator → **accepted**: UIKit swipe recognizer on the content, off while typing or paused.
4. Per-change saving → **kept**, with no-op edits skipped and intermediate typed values accepted.
5. **User's decision:** the skipped set's values can be edited before Mark as Done, and a done set can be marked as skipped.
6. Crowded bottom bar and an ambiguous "Back to Set 3" → **accepted**: compact Previous/Next row, "Back to Current Set".
7. Next at the newest set didn't match the swipe → **accepted**: Next acts as Back there.
8. The review view would rebuild the set editor → **accepted**: shared content view.
9. Review state when the reviewed set goes away → **accepted**: decided by lookup, transition keyed on (screen key, reviewed ID).
10. **User's decision:** not on the rest screen.

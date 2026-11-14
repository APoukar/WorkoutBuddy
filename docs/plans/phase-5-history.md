# Phase 5 — History calendar and session detail

## Context
`FEATURES.md` §7 phase 5 is **F6 — History calendar**: the History tab (today a "Coming soon" placeholder in `RootTabView`) gets a month calendar with a dot on every day that has a saved workout, a day list when a day has several, the session detail, and deleting a session. Phases 1–3 already store everything needed (`WorkoutSession` → `SessionExercise` → `SessionSet`, with planned and actual values and statuses); phase 5 only reads it and adds one delete.

**Where and when (the user's decision, 2026-11-14 night):** all work goes on the branch `phase-5-history`, created from `phase-4-background` at 1637c32 while PR APoukar/WorkoutBuddy#6 (phase 4) was still running CI; it's merged in the morning, and any fixes it needs are merged into this branch. Nothing is pushed and no PR is opened without the user.

**Overnight run (the user's instruction, 2026-11-14):** the user asked for the phase to be built autonomously while they sleep. The main session settles the architect's and the code reviewer's findings itself, logs every decision under "Review decisions made without the user", defers anything that needs the user (step 5's manual check, pushing, the PR) and reports in the morning.

## Parts and sessions
Seven steps is too much for one session once review rounds are counted (phase 4 needed five rounds on one step), and the UI tests are slow and flaky on this Mac. So, like phase 4, two parts, one after the other:
- **Part A — the feature (steps 1–5):** history queries and day rules, the detail texts, the session detail with delete, the calendar wrapper (4a), the History tab with the day list and the `history` scenario (4b), then the user's manual check.
- **Part B — UI tests and wrap-up (steps 6–7), fresh session (overnight: continued in the same session if its context allows):** the UI tests, `FEATURES.md`, push and the PR, CI green.

## Workflow (unchanged from phase 4)
The main session only orchestrates and writes no Swift app or test code. Per step: `implementer` (plan path + step number) → handle "Needs main session" → `code-reviewer` (plan, step, report) → discuss findings with the user (overnight: settled by the main session and logged) → agreed fixes through `implementer` → commit `Phase 5, step N: <what it did>` (plan changes go in the same commit). Steps marked **(user)** are manual checks.

**Test runs:** every subagent builds the app and runs **only the unit test suites the step adds or changes** (`-only-testing:WorkoutBuddyTests/<Suite>`), on iPhone 17 / iOS 27.0 only, plus the Release build where the step says so. The UI test step runs only its own UI test class locally. The full unit suite and the full UI suite run on GitHub CI only. `gh` and `git` need `PATH="/usr/bin:$PATH"`. Every subagent brief repeats this.

## Scope
- **In scope:** F6. The calendar with dots, swiping between months and today highlighted; tapping a day; the day list; the session detail (name, start time, duration, volume, sets as actual `reps × kg`, the plan where it differs, skipped and not-performed sets marked); deleting a session with confirmation; a History UI test scenario and UI tests.
- **Out of scope:** PR badges and the record recalculation on delete (F8, phase 6); opening the exercise progress screen from the detail (F7, phase 6); editing saved sessions (not in the spec); the calendar's visual polish (the UI tidying session).

## Decisions
- **What counts as history:** sessions with status `completed` or `endedEarly`. An `inProgress` one (running, or finished and waiting for Save) never shows (phase 3 hook). Sessions of soft-deleted templates and with archived exercises show normally: names come from the references (`SessionLibrary.exerciseNames(of:)`, `session.workout?.name`), with `SessionMessages.fallbackWorkoutName` / `fallbackExerciseName` when a reference is gone.
- **Which day a session belongs to:** the local calendar day of `startedAt` (`Calendar.current` at display time), so a workout that runs past midnight sits on the day it started, the same date "Last done" uses. A day is a small `nonisolated` `HistoryDay: Hashable` value (year, month, day), not a raw `DateComponents`, so it compares and navigates cleanly; it converts to `DateComponents` for the calendar.
- **The calendar is UIKit's `UICalendarView`** in a `UIViewRepresentable`. It is the system month calendar: swipes between months, highlights today, follows the locale's first weekday, supports Dynamic Type and VoiceOver, and draws **decorations** (the default dot) per day. A hand-made SwiftUI grid would rebuild all of that. Available since iOS 16, so no availability checks.
  - The calendar view's `calendar` and `timeZone` are set from the **same** `Calendar` the rules use, so dots and taps always line up (review finding 5).
  - `availableDateRange` ends at the **start of today** (`UICalendarView` treats the range by day; "start of tomorrow" would let the next month in on a month's last day; finding 4), a pure tested function. `HistoryView` keeps `@State today`, updated on `UIApplication.significantTimeChangeNotification` and when the scene becomes active, and passes it to the wrapper; the wrapper changes the range only when `today` changes (never on every `updateUIView`, which would jump the visible month while swiping). If the today highlight doesn't move by itself at midnight, the view is recreated with `.id(today)` (finding 5).
  - Single-date selection; `canSelectDate` allows **only days with a workout**. That's also the accessible signal: the default dot is probably not read by VoiceOver, while days without a workout read as not enabled (finding 9; days without a workout may be drawn dimmed, accepted). A tap is reported to SwiftUI and the selection is cleared right away, so the same day can be tapped again after coming back.
  - When the set of days changes (a workout saved or deleted while the tab is alive), the coordinator first updates its day set, then reloads decorations for the days that changed (`reloadDecorations(forDateComponents:animated:)`, the diff a pure tested function) **and** calls `selection.updateSelectableDates()`, so a new day becomes tappable and an emptied one stops being tappable (finding 1).
  - A **Today** toolbar button scrolls back to the current month. It's a one-shot command (a trigger counter), not a bound visible month (finding 5).
  - The calendar and the empty-history note sit in a `ScrollView`; the wrapper implements `sizeThatFits(_:uiView:context:)` with `systemLayoutSizeFitting` at the proposed width, so 5- and 6-week months and accessibility text sizes get the right height (finding 6).
  - With no history at all, a short note under the calendar: "No workouts yet" / "Saved workouts appear here."
- **Tapping a day:** one session → the session detail is pushed directly; several → a **day list** is pushed (title: the date, e.g. "Saturday, 14 November"), rows oldest first with the workout name, start time and duration. The decision is a pure rule (`HistoryRules.destination(for:sessions:)`).
- **The finished-sessions rule exists once:** `HistoryLibrary.finishedDescriptor()` (a `FetchDescriptor` with the `statusRaw` predicate, sorted by `startedAt`), used by `HistoryView`'s `@Query` (the `@Query`-in-`init` pattern of `RootTabView`) and by the library's own fetch (finding 8).
- **Navigation:** `HistoryView` owns a `NavigationStack` with a path of `HistoryRoute` (`.day(HistoryDay)` / `.session(UUID)`). Destinations get IDs and look the session up again (like `WorkoutListView`), so a deleted session can't leave a dangling model; a missing one shows "Workout Not Found".
- **Session detail** (pure `SessionDetailContent`, built from `SessionLibrary.snapshot(of:)`, the names, a locale and a time zone):
  - Navigation title: the workout name. Header: the start date and time ("Saturday, 14 November 2026 at 18:30"), and "Ended early" for `endedEarly` (F5 says such a session is marked).
  - Duration and Volume rows exactly like the summary (`SessionStats`, `SessionMessages.durationText` / `volumeText` and their spoken forms; volume 0 reads "0 kg").
  - One section per exercise (header: its name), one row per set in session order: the set number, then
    - **done:** `SetSummary.line` of the actual reps and kg ("8 × 60 kg", Bodyweight for 0 kg); if reps or kg differ from the plan, a secondary line "Planned 10 × 60 kg" (rest isn't shown, so it isn't compared);
    - **skipped / not performed:** "Skipped" / "Not performed" plus "Planned 8 × 62.5 kg", in the secondary style; marked by text, never by colour alone.
  - Each row is one VoiceOver element: "Set 2, 8 reps at 60 kilograms, planned 10 reps at 60 kilograms" / "Set 3, skipped, planned 8 reps at 62.5 kilograms".
  - Sections are identified by the `SessionExercise`'s ID (or index), never by the exercise ID, which can be `nil` for several; the exercise ID is kept on each section as data for phase 6's link to the progress screen (finding 10).
  - Set rows follow `WorkoutDetailView`'s set row: "Set N" through `ExerciseSetsRules.sectionTitle(forSetAt:)`, the stacked layout at accessibility sizes, one combined accessibility element (finding 10).
  - **The view keeps the content, not the model** (finding 3): `SessionDetailView` builds `SessionDetailContent` (a value) once into `@State` (and rebuilds it on appear), and looks the model up by ID only when Delete is confirmed, then calls `onDeleted` after a successful delete. So nothing reads a deleted model, and the screen doesn't flip to "Workout Not Found" while it pops.
- **Deleting a session:** a **Delete** toolbar button on the detail (`Label("Delete", systemImage: "trash")`, with a UI-test identifier because the alert's button has the same label), then an alert "Delete Workout?" / "The workout from Saturday, 14 November will be removed from your history. This can't be undone." (the date names which session; finding 14) with Cancel and a destructive Delete (the `WorkoutDeletionAlert` pattern). `HistoryLibrary.delete` is a real delete (sessions aren't soft-deleted; the cascade removes its exercises and sets), only for `completed` / `endedEarly` sessions (in-progress ones go through `SessionLibrary.discard`), saved immediately with rollback on failure. It never reports to `SessionEffects` (no notification or Live Activity belongs to a saved session). "Last done" on the Workouts list follows by itself (it's computed from the relationship). After the delete the detail is popped, and the day list too if its day is now empty (pure `HistoryRules.path(afterDeleting:…)`).
- **Errors:** failed fetches and deletes are logged with `ErrorLogging.log`, category `"history"`; a failed delete shows `.errorAlert` with the generic message.
- **Texts** live in `HistoryMessages` (pure, tested), date and time texts in `Formatters` with `locale` and `timeZone` parameters for tests; `WorkoutListRules`' "Last done" date uses the same `Formatters` style setup (finding 10).

## Folder layout
- `WorkoutBuddy/Features/History/`: `HistoryLibrary`, `HistoryRules` (+ `HistoryDay`, `HistoryRoute`), `HistoryMessages`, `SessionDetailContent`, `HistoryView`, `HistoryCalendarView`, `HistoryDayView`, `SessionDetailView`, `HistoryPreviewData`.
- `WorkoutBuddyTests/Features/History/` mirrors it.

## Reuse
`SessionLibrary.snapshot(of:)` and `exerciseNames(of:)`; `SessionStats`; `SessionMessages.durationText` / `spokenDurationText` / `volumeText` / `spokenVolumeText` / fallbacks; `SetSummary.line` / `spokenLine`; `Formatters.weight` / `volume` / `duration`; `WorkoutLibrary.workout(id:)` semantics (ID lookups never filter); the `WorkoutDeletionAlert` and `WorkoutListRules.path(afterDeleting:from:)` patterns; `.errorAlert`, `ErrorLogging`; `SessionFixture` in the tests; the `SessionPreviewData` / `UITestingScenario` way of building sessions through `SessionLibrary` with explicit `now:` dates.

## Steps

### Part A — the feature

**Step 1 — History queries and day rules**
- `HistoryLibrary` (`@MainActor` struct with a `ModelContext`): `static func finishedDescriptor()` and `finishedSessions() throws` using it, `session(id:)` (no status filter), `delete(_:) throws` (finished sessions only; a no-op otherwise; rollback on failure; comment: phase 6 recalculates records here).
- `HistoryRules` (`nonisolated`, pure, on `(id, startedAt)` values so it needs no models): `HistoryDay` from a date and calendar (and back to `DateComponents`); the set of days with sessions; the sessions of one day, oldest first; `destination(for:…)` (none / one session / day list); `path(afterDeleting:…)`; the days to reload (the symmetric difference of two day sets); the end of `availableDateRange` (start of today).
- Tests (`HistoryLibraryTests`, `HistoryRulesTests`, in-memory container): running and waiting-for-Save sessions are excluded; sessions of a soft-deleted template and with an archived exercise are included; ID lookup; delete removes the session with its exercises and sets and leaves the template, the exercises and other sessions; delete on an in-progress session does nothing; `lastPerformed` falls back to the previous session after a delete. Day rules with a fixed `Europe/Prague` calendar: 23:59 vs 00:01, a session crossing midnight, the DST change days, several sessions on one day in order, the destination for 0 / 1 / 3 sessions, the path after deleting (detail only; detail over a day list with sessions left; the last session of a day); the reload diff; the range end on the last day of a month stays in that month.

**Step 2 — Session detail texts**
- `SessionDetailContent` and `HistoryMessages` as in Decisions (including the delete message with the date); `Formatters.sessionStart(_:locale:timeZone:)` and the day list's time and day-title texts, sharing the style setup with `WorkoutListRules`' "Last done" date (its tests must still pass).
- Tests: `en_US` and `en_CZ`; done equal to plan (no plan line), reps differ, kg differ, both; skipped and not performed; Bodyweight (actual and planned); volume 0; ended early vs completed; a missing workout and exercise name use the fallbacks; exercise and set order; the spoken forms.

**Step 3 — Session detail view and delete**
- `SessionDetailView(sessionID:onDeleted:)` keeping `SessionDetailContent` in `@State` (Decisions), the Delete toolbar button and alert, "Workout Not Found" when the first lookup fails.
- `HistoryPreviewData`: saved sessions on several days (two on one day, one ended early with a skipped and a changed set, a Bodyweight exercise, a soft-deleted template, an archived exercise), built through `SessionLibrary` with `try` like the UI scenarios. **Order** (finding 11): `start` refuses soft-deleted templates and a second session in progress, and archiving removes the exercise from templates, so every session is started and saved first, oldest first, and only then is the template soft-deleted and the exercise archived. Previews of the detail (complete, ended early, accessibility text size).
- Run the Release build too (previews).

**Step 4a — The calendar wrapper** (finding 12: step 4 split)
- `HistoryCalendarView`: the `UICalendarView` wrapper as in Decisions (calendar and time zone, decorations, selectable days with `updateSelectableDates()`, selection reported and cleared, the range from `today`, the Today trigger, `sizeThatFits`).
- Previews: with the preview data, empty, accessibility text size.
- Run the Release build too.

**Step 4b — History tab, day list, navigation, and the `history` scenario**
- `HistoryDayView`, `HistoryView` (the stack, the `@Query` with `finishedDescriptor()`, `@State today`, the empty note, Today), and `RootTabView` uses `HistoryView` instead of the placeholder.
- The `history` UI-testing scenario, moved here from step 6 so the runtime check and the user's manual check have data (finding 7): `UITestingContract.Scenario.history` and `UITestingScenario.history` as described in step 6, with their unit tests.
- Run the Release build too.
- **Runtime check by the code reviewer** on iPhone 17e / iOS 27 (launch with `-uiTesting YES -uiTestingScenario history`, never the user's iPhone 17 simulator): dots on the right days, previous month by swipe, a one-session day opens the detail, a two-session day opens the list, delete pops back and the emptied day's dot goes away **and the day can't be tapped any more**, saving a workout adds a dot while the tab is alive **and the new day can be tapped**, the Workouts tab's "Last done" is updated after a delete (finding 13).

**Step 5 — Part A manual check (user)** — iPhone 17 / iOS 27 simulator, launched with the `history` scenario for the seeded data (and normally for the empty and save checks); the list under Verification. Anything found becomes a step 5b fix. (Overnight: deferred to the morning; part B goes ahead.)

### Part B — UI tests and wrap-up (fresh session)

**Step 6 — UI tests**
- The `history` scenario (built in step 4b): the templates plus saved "Long Rests" sessions: two **today** and one on the **15th of the previous month** (ended early, one set with changed kg, one skipped). **Today's sessions** (finding 2) are anchored at `max(startOfDay(now), now − 2 h)` plus fixed offsets, and their actions may come after `now` when that's the only way to keep them on today (`SessionLibrary` accepts any `now:`); a unit test seeds with `now` = 00:00:05 and checks every session's day.
- `UITestingContract`: the expected spoken texts, identifiers only where a label is ambiguous (the detail's Delete button).
- First a **probe**: how XCUITest sees `UICalendarView` (day cells' labels in `en_US`, whether a day without a workout reads as not enabled, whether the dot is exposed, how to go to the previous month); the helpers use what works. "The day's dot is gone" is checked through the day cell being not enabled, not the decoration (finding 9).
- `HistoryUITests`: today → day list with two rows → detail (name, volume, a set row); previous month → the 15th → detail directly ("Ended early", the planned line of the changed set, "Skipped", "Not performed"); delete from the detail → the row and then the day's tappability are gone; `onSummary` → Save → History → today → detail with "1,420 kilograms". Every test that depends on "today" calls `XCTSkip` within 15 minutes of local midnight (the `onSummary` session starts 10 minutes before launch; finding 2).
- Run only `HistoryUITests` locally (with `-test-iterations 3 -run-tests-until-failure`), the new scenario's unit tests, and `build-for-testing`.

**Step 7 — Wrap-up**
- `FEATURES.md` F6: the decisions the spec didn't state (a session belongs to the day it started; ended-early sessions are marked; skipped and not-performed sets show their plan).
- This plan's status, the phase 5 memory note.
- Push and the PR (with the user); CI green (full unit and UI suites).

## Hooks left for later phases
- **Phase 6:** PR badges on the detail rows (`SessionDetailContent` gets per-set record flags); tapping an exercise section opens its progress screen (the section keeps the exercise ID); `HistoryLibrary.delete` recalculates records.
- **Phase 7:** nothing new is stored.
- **UI tidying session:** the calendar's and the detail's look.

## Verification
- Each step: the build, the step's unit suites on iPhone 17 / iOS 27.0, the Release build where the step says so, and the `code-reviewer` review (with its runtime check in step 4b). Full unit and UI suites on GitHub CI with the phase PR.
- **Manual check of part A (user, iPhone 17 / iOS 27 simulator):** finish and save a workout → today gets a dot while History is open; swipe back and forth between months, the future isn't reachable, today is highlighted; a day with one workout opens its detail, a day with two opens the list (oldest first); the detail shows the name, start time, duration and volume matching the summary, actual sets, the plan only where changed, skipped and not-performed sets marked; a session of a deleted template and with a deleted exercise still shows their names; delete → confirmation → back, the dot gone when it was the day's last workout, and the Workouts list's "Last done" updated; Today jumps back to the current month; empty history shows the note; Czech region shows "22,5 kg" and the local date format.
- **Real device (with the phase 4 items):** VoiceOver on the calendar (days with workouts recognisable as the enabled ones) and on the detail rows.

## Review decisions made without the user

**Architect review of the plan (2026-11-14, overnight), verdict "Approve with changes", 14 findings, all settled by the main session (the user asked for an autonomous run):**
1. [Major] Selectable days not refreshed after a save or delete → **accepted**: `updateSelectableDates()` after every day-set change; only days with a workout are selectable (dimmed other days accepted); runtime check taps the new and the emptied day.
2. [Major] UI test dates break near local midnight → **accepted**: today's sessions anchored at `max(startOfDay, now − 2 h)`, actions may come after `now`; a 00:00:05 unit test; `XCTSkip` within 15 min of midnight.
3. [Major] The detail could read a deleted model or flash "Not Found" → **accepted**: the content lives in `@State`; the model is looked up only to delete.
4. [Minor] Range end lets next month in → **accepted**: start of today, tested.
5. [Minor] Today highlight, calendar/time zone, range churn → **accepted**: `@State today` with midnight and `.active` refresh, `.id(today)` if needed, same calendar for view and rules, Today as a one-shot trigger.
6. [Minor] Calendar height → **accepted**: `ScrollView`, `sizeThatFits`, accessibility preview.
7. [Minor] No data for the manual and runtime checks → **accepted**: the `history` scenario moves into step 4b.
8. [Minor] Predicate written twice → **accepted**: `finishedDescriptor()` shared.
9. [Minor] VoiceOver and XCUITest can't see the dot → **accepted**: selectability is the accessible signal; the UI test checks enabled state.
10. [Minor] Section identity, row reuse, shared date styles → **accepted**.
11. [Minor] Preview data order → **accepted**.
12. [Minor] Step 4 too big → **accepted**: steps 4a and 4b.
13. [Minor] "Last done" after a delete → **accepted** into the step 4b runtime check.
14. [Question] Alert wording, button label → **main session's choice**: the message names the date; `Label("Delete", systemImage: "trash")` with a UI-test identifier.

**Step 1 code review, verdict "Approve", 2 minor findings, settled by the main session.** 23 tests passed. Implementer's deviations, **accepted**: `path(afterDeleting:from:remaining:calendar:)` takes the path, the remaining entries (it ignores the deleted one itself) and a calendar; `destination(for:sessions:)` takes the day's sessions; `HistoryDay` is also `Comparable`.
1. [Minor] No test caught removing the "ignore the deleted session in `remaining`" filter → **fixed**: the last-session test passes the deleted session in `remaining`.
2. [Minor] `session(id:)` swallowed a fetch error → **fixed**: logged, category `"history"`.

**Step 2 code review, verdict "Approve", 2 minor findings, settled by the main session.** 60 tests passed in the four touched suites; "Last done" unchanged. Small additions beyond the plan (tab title, Today, Delete and Cancel texts; whitespace-only names use the fallback) **accepted**.
1. [Minor] The day-list row texts took a raw duration, which could include pauses → **fixed**: they take `SessionStats` and use `SessionMessages.durationText`.
2. [Minor] A `.pending` set in a saved session untested → **fixed**: reads "Not performed".

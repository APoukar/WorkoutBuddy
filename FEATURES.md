# Workout Buddy — Features (v1)

## 1. Product summary
A personal iPhone app for planning gym workouts, running them set by set with guided rest timers, and tracking history and progress. A workout is a reusable template made of exercises. Each exercise has one or more sets, and each set has reps, weight (kg) and a rest period. Running a template creates a **session**, which is saved to a local database.

## 2. Platform & tech baseline
- iPhone only, **minimum iOS 18**, SwiftUI, English UI, weights in **kg**.
- Local persistence with **SwiftData** (no cloud sync).
- Swift Charts (progress), ActivityKit + WidgetKit extension (Live Activity), UserNotifications (rest-end alert).
- App structure: tab bar with **Workouts · History · Progress · Settings**. An active workout is shown full screen on top of everything.

## 3. Features

### F1 — Exercise library
- Ships with ~40 common exercises, each tagged with a **muscle group** (Chest, Back, Shoulders, Biceps, Triceps, Legs, Glutes, Core, Full body). The list is seeded on first launch only.
- Managed **only from Settings → Exercises**: a list grouped by muscle group, with search.
- Add a custom exercise (name + muscle group). Any exercise, built-in or custom, can be renamed, moved to another muscle group, or deleted.
- Each exercise can optionally have its own **defaults for new sets** (reps, kg, rest), set in the exercise editor. Any of them can be left unset.
- Delete = **archive** (soft-delete). The exercise is hidden from the picker, but history and charts that reference it still work. There is no restore in v1.
- Deleting an exercise that's used in templates first shows a warning naming those templates. Confirming removes it from them, and a template left with no exercises has to be fixed before it can start. Past sessions are never changed.
- Names must be unique among active (non-archived) exercises, case-insensitive. A deleted exercise's name can be reused, so two exercises with the same name can appear in history and progress.

### F2 — Workout templates (planning)
- **Workouts tab**: list of templates showing name, exercise count and last-performed date. Create, edit and delete (soft-delete) templates.
- **Create/edit a template:**
  - Workout name (required).
  - "Add exercise" opens a picker over the predefined list, with search and a muscle-group filter. The picker can't create exercises (that's done in Settings).
  - Reorder and remove exercises.
  - For each exercise, a list of sets. Each set has **reps**, **kg** and **rest period** (seconds, shown as m:ss).
  - "Add set" copies the previous set's values. Sets can be deleted.
  - The **first set** of an exercise takes each value (reps, kg, rest) from the first source that has one:
    1. the exercise's own defaults (F1)
    2. the values last used for that exercise in a template
    3. the defaults from Settings (F9)
- **Validation:** a template needs at least 1 exercise, and every exercise needs at least 1 set. Reps ≥ 1, kg ≥ 0 (0 = bodyweight) in 0.5 kg steps, rest 0–10 min. Wherever a weight is shown as text, 0 kg reads **Bodyweight**.
- Editing a template never changes past sessions.
- From a template's detail view, you can **Start workout**.

### F3 — Active workout session
- **Start:** the overall workout timer starts, and the first set's screen opens full screen. The screen stays awake while a workout is running. Only one session can be active at a time.
- **Set screen** (full page):
  - Exercise name, "Exercise 2 of 5", "Set 3 of 4".
  - Large **reps** and **kg** fields pre-filled from the plan, editable with +/- buttons (kg step comes from Settings). Whatever is shown when you tap Done is saved as the *actual* value.
  - Overall elapsed timer, plus a small "Next: …" preview.
  - Big **Done** button. **Skip set** and **Pause** are secondary actions.
- **Rest screen** (full page), shown after Done:
  - Large countdown from that set's rest period, with a preview of the next set (exercise, reps × kg).
  - **Skip rest** goes straight to the next set.
  - When the countdown reaches 0, the phone plays a haptic and a sound, then **opens the next set's screen automatically**.
  - If the rest period is 0, or it was the last set of the workout, there is no rest screen.
- **Skip set:** the set is saved as *skipped* and the next set opens right away (no rest).
- **Pause:** freezes the overall timer and any rest countdown. A paused overlay offers **Resume** and **End workout**.
- **End early:** asks for confirmation, then shows the summary (F5); when it's saved, the remaining sets are saved as *not performed*. If no set was completed, the app offers to **discard** the session instead (see F5: a workout with no completed set is never saved).
- **Earlier sets:** on the set screen or the summary, swipe right (or tap Previous Set / Review Sets) to look back at finished sets. A done set's reps and kg can be corrected, a skipped set can be marked as done and a done set as skipped; the workout's position and timers don't change.
- **Robustness:** timers are calculated from stored timestamps, not by counting ticks, so they stay correct in the background. Session progress is saved after every action. If the app is killed, the next launch offers **Resume** or **End** (which shows the summary, where **Save** stores it).

### F4 — Lock Screen & background
- **Live Activity** (Lock Screen + Dynamic Island) while a session runs:
  - During a set: exercise, set number, reps × kg, elapsed time.
  - During rest: a live countdown with a progress bar and the up-next set, rendered by the system so it keeps running while the app is suspended.
  - Paused: "Paused", the elapsed time frozen, and the rest left if paused during a rest. Finished, waiting for Save: the summary title and the duration.
  - When a rest ends in the background, the rest-end notification wakes the app and the activity shows the next set a few seconds after 0. If the app can't update it, the activity shows **"Rest over"** with the next set shortly after 0.
  - Save or Discard removes it. An activity swiped away stays away until the app is launched again. Tapping it opens the app.
- A **local notification** ("Rest Over" with the up-next set) fires when rest ends. It is scheduled when rest starts and cancelled on skip rest, undo, pause, end or discard (rescheduled on resume). With **Sound** on it plays the rest-end chime; with only **Haptics** on it plays a silent sound so the phone vibrates; with both off it's a silent banner. When the app is open at rest end, the in-app alert plays instead of the banner, so there is always exactly one alert.
- When you come back to the app after rest has ended, the next set's screen is already showing.
- Notification permission is requested the first time you start a workout. If it's denied, the in-app alert and the Live Activity still work, and Settings shows "Notifications are off" with a button to the system settings.

### F5 — Workout summary
- Shown when the last set finishes or the workout ends early: total duration (excluding pauses), sets completed / skipped, total volume (Σ reps × kg) and **new personal records** hit in this session.
- **Save** stores it to history. A session that ends early is marked as such, and its remaining sets are saved as *not performed*.
- **A workout with no completed set is never saved.** This covers ending early with nothing done and finishing with every set skipped: the summary offers **Discard Workout** instead of Save, and the title reads "Workout Ended". After a kill, such a workout is offered **Resume** or **Discard**.
- **Back to Workout** returns to the workout from the summary. The time spent on the summary doesn't count towards the duration.

### F6 — History calendar
- **History tab**: month calendar, swipeable between months (up to the current one), with today highlighted and a **Today** button. Days with at least one finished session show a **dot**. A session belongs to the day it started, even if it ran past midnight.
- Tap a day with a dot to open the **session detail**. If there were several sessions that day, a short list of them is shown first, oldest first. Days without a session can't be tapped (except today, which stays highlighted).
- **Session detail:** workout name, start time, duration and total volume, and "Ended early" for a session that was ended early. Each exercise lists its sets as actual `reps × kg`. Where the actual value differs from the plan, the plan is shown too. Skipped and not-performed sets are marked and show their plan, and PR sets get a badge.
- A session can be deleted (with confirmation) to correct mistakes.

### F7 — Per-exercise progress charts
- **Progress tab**: exercises that have at least one completed set, grouped by muscle group, with search.
- **Exercise progress screen** (also opened by tapping an exercise in a session detail), with one chart per metric, one data point per session:
  - **Max weight** (heaviest completed set)
  - **Total volume** (Σ reps × kg)
  - **Estimated 1RM** (Epley: kg × (1 + reps/30), best set)
- Time range: 1M · 3M · 6M · 1Y · All.

### F8 — Personal records
- Records are tracked per exercise, from completed sets only:
  - **Heaviest weight**
  - **Best estimated 1RM**
  - **Best single-set volume** (reps × kg)
  - **Best session volume**
- A record is detected when a session is saved. PRs appear in the workout summary (F5), as badges in session detail (F6) and in a "Records" section on the exercise progress screen (F7), each with its date.
- Records are recalculated if a session is deleted.

### F9 — Settings
- **Exercises** (F1 management).
- **Defaults for new sets:** reps (10), kg (20) and rest (90 s). They're used when neither the exercise's own defaults nor values last used in a template exist (F2).
- **Weight step** for the +/- buttons: 0.5 / 1 / 2.5 kg (default 2.5), so weights always stay on the 0.5 kg grid.
- **Rest-end alert:** sound on/off, haptics on/off.
- **Export data** to JSON, as a manual backup through the share sheet.

## 4. Conceptual data model
- **Exercise**: id, name, muscleGroup, isCustom, isArchived, optional defaultReps / defaultKg / defaultRestSeconds
- **Workout** (template): id, name, createdAt, updatedAt (last saved in the editor; used for "values last used in a template"), isSoftDeleted (named so because SwiftData models already have an `isDeleted` property), sessions (inverse of the session's workout ref) → ordered **WorkoutExercise** (exercise ref) → ordered **PlannedSet** (reps, kg, restSeconds)
- **WorkoutSession**: id, workout ref, startedAt, endedAt, pausedDuration, pausedAt, restEndsAt and lastActionAt (only used while a session runs), status (inProgress / completed / endedEarly) → ordered **SessionExercise** (exercise ref) → ordered **SessionSet** (planned reps/kg/rest, actual reps/kg, status pending / done / skipped / notPerformed, completedAt = when it was done or skipped)
- Rules:
  - Sessions **copy the planned numbers**, because templates can change later.
  - Names are **not** copied. They're looked up through references, and workouts and exercises are soft-deleted so those references keep working.

## 5. Out of scope for v1 (candidates for later)
Apple Watch app · iPad · iCloud sync / import · HealthKit · interactive Live Activity buttons (Done / Skip from Lock Screen) · "last time" hints during a session (showing what you lifted last time; this is separate from the first-set defaults in F2) · supersets / warm-up sets · lbs · Czech localization · +30 s rest extension.

## 6. Open points (defaults chosen, revisit when planning)
- **Accidental Done:** default is an **Undo** button on the rest screen that returns to the set. For the last set, which has no rest screen, **Back to Workout** on the summary does the same.
- **Weight changed mid-exercise:** a change applies to the current set only and doesn't carry over to the remaining sets.
- **"Values last used in a template" (F2):** the first set of that exercise in the template that was saved most recently, among active templates. Confirmed in phase 2 planning.

## 7. Suggested implementation phases
1. Foundation: Xcode project, SwiftData models, exercise seed, Settings → Exercises (F1, F9 basics)
2. Workout templates (F2), including per-exercise defaults for new sets (F1 editor fields, F2 first-set rule)
3. Active session in the foreground + summary + save (F3, F5)
4. Background: notifications + Live Activity (F4)
5. History calendar + session detail (F6)
6. Progress charts + personal records (F7, F8)
7. Export (F9)
8. Raise the minimum to iOS 27 (not a feature; planned on its own): set the deployment target of every target to iOS 27.0, including the widget extension, remove the `if #available` checks for older iOS versions, and update §2 and `CLAUDE.md`. Decided 2026-11-12: the app is only for the owner's iPhone, which runs iOS 27; until then, tests run on iOS 27 only and `if #available` branches for older iOS stay minimal.

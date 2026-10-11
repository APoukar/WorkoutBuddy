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
- Add a custom exercise (name + muscle group), rename it, or change its muscle group.
- Delete = **archive** (soft-delete). The exercise is hidden from the picker, but history and charts that reference it still work.
- Names must be unique among active (non-archived) exercises, case-insensitive.

### F2 — Workout templates (planning)
- **Workouts tab**: list of templates showing name, exercise count and last-performed date. Create, edit and delete (soft-delete) templates.
- **Create/edit a template:**
  - Workout name (required).
  - "Add exercise" opens a picker over the predefined list, with search and a muscle-group filter. The picker can't create exercises (that's done in Settings).
  - Reorder and remove exercises.
  - For each exercise, a list of sets. Each set has **reps**, **kg** and **rest period** (seconds, shown as m:ss).
  - "Add set" copies the previous set's values. The first set uses the defaults from Settings. Sets can be deleted.
- **Validation:** a template needs at least 1 exercise, and every exercise needs at least 1 set. Reps ≥ 1, kg ≥ 0 (0 = bodyweight) in 0.5 kg steps, rest 0–10 min.
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
- **End early:** asks for confirmation. Remaining sets are saved as *not performed*, and the session is saved. If no set was completed, the app offers to **discard** the session instead.
- **Robustness:** timers are calculated from stored timestamps, not by counting ticks, so they stay correct in the background. Session progress is saved after every action. If the app is killed, the next launch offers **Resume** or **End & save**.

### F4 — Lock Screen & background
- **Live Activity** (Lock Screen + Dynamic Island) while a session runs:
  - During a set: exercise, set number, reps × kg, elapsed time.
  - During rest: a live countdown, rendered by the system so it keeps running while the app is suspended.
- A **local notification** with sound and vibration fires when rest ends. It is scheduled when rest starts and cancelled on skip rest, pause or end.
- When you come back to the app after rest has ended, the next set's screen is already showing.
- Notification permission is requested the first time you start a workout.

### F5 — Workout summary
- Shown when the last set finishes or the workout ends early: total duration (excluding pauses), sets completed / skipped, total volume (Σ reps × kg) and **new personal records** hit in this session.
- **Save** stores it to history. A session that ends early is marked as such.

### F6 — History calendar
- **History tab**: month calendar, swipeable between months, with today highlighted. Days with at least one finished session show a **dot**.
- Tap a day with a dot to open the **session detail**. If there were several sessions that day, a short list of them is shown first.
- **Session detail:** workout name, start time, duration and total volume. Each exercise lists its sets as actual `reps × kg`. Where the actual value differs from the plan, the plan is shown too. Skipped and not-performed sets are marked, and PR sets get a badge.
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
- **Defaults for new sets:** reps (10), kg (20) and rest (90 s).
- **Weight step** for the +/- buttons: 0.5 / 1 / 1.25 / 2.5 kg (default 2.5).
- **Rest-end alert:** sound on/off, haptics on/off.
- **Export data** to JSON, as a manual backup through the share sheet.

## 4. Conceptual data model
- **Exercise**: id, name, muscleGroup, isCustom, isArchived
- **Workout** (template): id, name, createdAt, isDeleted → ordered **WorkoutExercise** (exercise ref) → ordered **PlannedSet** (reps, kg, restSeconds)
- **WorkoutSession**: id, workout ref, startedAt, endedAt, pausedDuration, status (inProgress / completed / endedEarly) → ordered **SessionExercise** (exercise ref) → ordered **SessionSet** (planned reps/kg/rest, actual reps/kg, status done / skipped / notPerformed, completedAt)
- Rules:
  - Sessions **copy the planned numbers**, because templates can change later.
  - Names are **not** copied. They're looked up through references, and workouts and exercises are soft-deleted so those references keep working.

## 5. Out of scope for v1 (candidates for later)
Apple Watch app · iPad · iCloud sync / import · HealthKit · interactive Live Activity buttons (Done / Skip from Lock Screen) · "last time" hints · supersets / warm-up sets · lbs · Czech localization · +30 s rest extension.

## 6. Open points (defaults chosen, revisit when planning)
- **Accidental Done:** default is an **Undo** button on the rest screen that returns to the set.
- **Weight changed mid-exercise:** a change applies to the current set only and doesn't carry over to the remaining sets.

## 7. Suggested implementation phases
1. Foundation: Xcode project, SwiftData models, exercise seed, Settings → Exercises (F1, F9 basics)
2. Workout templates (F2)
3. Active session in the foreground + summary + save (F3, F5)
4. Background: notifications + Live Activity (F4)
5. History calendar + session detail (F6)
6. Progress charts + personal records (F7, F8)
7. Export (F9)

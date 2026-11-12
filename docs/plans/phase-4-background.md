# Phase 4 — Background: rest-end notification and Live Activity

Covers `FEATURES.md` §7 phase 4: **F4 — Lock Screen & background**. It builds on phase 3 (`docs/plans/phase-3-session.md`), whose "Hooks left for later phases" this plan answers for phase 4, and on the UI test work (`docs/plans/ui-tests.md`), which decided that UI-testing mode never requests notification permission.

All work goes on the branch `phase-4-background` (from `main` at 146bfa3, after PR APoukar/WorkoutBuddy#4). Nothing is pushed and no PR is opened without the user.

## Parts and sessions
The phase is split in two parts, each built in its own session, one after the other (the 8 GB Mac can't run two sessions' builds and simulators at once):
- **Part A — rest-end notification (steps 1–4).** The side-effect seam in `SessionLibrary`, the notification, the permission prompt and the Settings changes. No new target. Ends with the user's manual check of part A.
- **Part B — Live Activity (steps 5–9).** The widget extension target, the shared attributes, the Live Activity content, its coordinator and its views. Starts in a fresh session after part A is checked. Ends with the manual check of the whole phase and one PR.

## Workflow
The main session only orchestrates. It writes no Swift app or test code. For every step:
1. Run `implementer` with this plan's path and the step number. Steps marked **(main session)** or **(user)** are project setup or manual checks; no subagent touches the Xcode project.
2. Handle anything it lists under "Needs main session".
3. Run `code-reviewer` with the plan, the step and the implementer's report.
4. Present the findings to the user and discuss them. Agreed fixes go through `implementer` too, never as direct edits.
5. Once the build and tests are green, commit the step as `Phase 4, step N: <what it did>`. If the plan changed because of the step, commit the plan in the same commit.

**Test runs (the user's choice for this phase; the 8 GB Mac gets overloaded):** every subagent builds the app (`CLAUDE.md` build command) and runs **only the unit test suites the step adds or changes** (`-only-testing:WorkoutBuddyTests/<Suite>`), on iPhone 17 / OS 27.0 and iPhone 16 / OS 18.2, plus the Release build where the step says so. The **full unit suite and the UI suite run on GitHub CI only**, never locally. `gh` and `git` need `PATH="/usr/bin:$PATH"`. Every subagent brief repeats this.

## Scope
- **In scope:** F4 — the rest-end local notification (scheduled when a rest starts, cancelled on skip rest, undo, pause, end and discard, rescheduled on resume), the notification permission request on the first Start, the Live Activity on the Lock Screen and in the Dynamic Island for the set, rest, paused and finished states, and the phase 1 hook to revisit the Settings "Haptics" wording.
- **Already done in phase 3:** "When you come back to the app after rest has ended, the next set's screen is already showing" (`ActiveSessionView.settleExpiredRest`); the bundled chime `WorkoutBuddy/Resources/RestEnd.caf`.
- **Out of scope** (`FEATURES.md` §5 and system limits): interactive Live Activity buttons (Done / Skip from the Lock Screen); push-token updates of the Live Activity (there's no server); custom layouts for the Apple Watch Smart Stack, CarPlay or the Mac menu bar (iOS shows the activity there automatically, built from the compact views); Time Sensitive notifications (the user's choice, see the review log); AlarmKit.

## Decisions

### The side-effect seam
- **One seam in `SessionLibrary`.** Every state change already goes through `SessionLibrary`. It gets an injected `effects: any SessionEffects` (`init(context:effects:)`, defaulting to `SessionEffectsProvider.current`, so existing `SessionLibrary(context:)` calls don't change). After **every successful save** (start, the set actions, review edits, pause, resume, end, back to workout, save, discard, recovery end) it calls `effects.sessionChanged(_ state: SessionEffectsState)`. `commit` is the only place that saves, so it reports after a successful save and never after a rollback; `start` reports too. An action that saves without changing anything (`perform` stamps `lastActionAt`) reports again; that's a harmless extra reconcile.
- **`SessionEffectsState`** is a `nonisolated`, `Equatable`, `Sendable` value: `.none` (no session in progress) or `.active` with the session's ID, its `SessionSnapshot`, the workout name and the exercise names by ID, **looked up through the references** at that moment (names are never copied into the session). `SessionLibrary.effectsState()` builds it from `activeSession()`, so it always describes the session the cover shows, also after Save or Discard (then `.none`). If that fetch throws after an action already saved, the error is **logged and the report skipped**; the action doesn't fail (review finding 8). `workoutName` is optional (`nil` when the reference is gone) and a missing exercise has no entry in `exerciseNames`; consumers apply `SessionMessages.fallbackWorkoutName` / `fallbackExerciseName` (step 1). `ModelContainerFactory.isRunningTests(environment:)` makes the test part of the provider gate testable (step 1).
- **`SessionEffects`** is a `@MainActor` protocol: `sessionChanged(_:)`, `appBecameActive(_:)` (added in step 2b), `requestNotificationPermissionIfNeeded()` and `notificationAuthorization() async -> NotificationAuthorization` (`.notDetermined` / `.allowed` / `.denied`, the app's own enum). `NoSessionEffects` does nothing (and reports `.allowed`, so nothing permission-related shows). `LiveSessionEffects` fans out to the coordinators and talks to the notification center.
- **`SessionEffectsProvider.current`** (an `enum` namespace with a `static let current: any SessionEffects`) is `NoSessionEffects` when the process hosts unit tests (`ModelContainerFactory.isRunningTests`), runs in UI-testing mode (`UITestingLaunch.current != nil`) or renders Xcode previews (`XCODE_RUNNING_FOR_PREVIEWS == "1"`), and `LiveSessionEffects.shared` otherwise. So tests and previews never schedule notifications, show Live Activities or raise the permission prompt, and that gate exists in **one** place (review findings 7 and 10).
- **Reconcile, don't track events.** The notification and the Live Activity are each driven by an **idempotent reconciler** that makes the system match the stored state ("there should be a rest notification at 10:42:30 with this text" / "there should be none"). Nothing remembers which event happened. This covers skip rest, undo, pause, resume, end, discard, back to workout and recovery with no per-action code.
- **Serial coordinators.** Each reconciler is a `@MainActor final class` coordinator that keeps only the **latest** desired state and applies it in one running task at a time: a new state while a system call is in flight is applied after it, and intermediate states are skipped. The system APIs sit behind small value-only protocols (`NotificationScheduling`, `LiveActivityControlling`) with one live adapter each, so the coordinators are unit tested with fakes.
- **Reconcile at launch and on becoming active, too.** `RootTabView`'s launch check and its scene-phase `.active` handler call `effects.appBecameActive(library.effectsState())` (a reconcile that also removes delivered notifications; a launch counts, since it's always in the foreground), independent of the recovery alert. This repairs anything that drifted while the app was killed. A reconcile while an expired rest isn't cleared yet is fine: `restRemaining` already treats it as no rest.

### Rest-end notification
- **One notification at a time,** with the fixed identifier `rest-end`; adding it again replaces the pending one.
- **Desired state** (pure, `RestNotificationPlan.decide(_ state:, settings:, now:)`): **schedule** while the session is resting and not paused (`restRemaining(now:) != nil`, `!isPaused`, not finished); otherwise **cancel**. A schedule carries the fire date (`restEndsAt`), the title, the body and the sound choice.
- **Trigger:** `UNTimeIntervalNotificationTrigger(timeInterval: restEndsAt − now, repeats: false)`, at least 1 s (the API refuses 0). A rest that is already over when it's applied isn't scheduled.
- **Content:** title **"Rest Over"**; body the rest screen's up-next line, `SessionMessages.upNext` — "Bench Press · Set 2 · 8 × 62.5 kg" (Bodyweight reads "Bodyweight"). Exercise name from the effects state; `SessionMessages.fallbackExerciseName` when the reference is gone. Interruption level `.active` (the default).
- **Sound and vibration (the user's choice, review finding 4).** A notification without a sound is completely silent, with no vibration either. So:
  - **Sound on:** `UNNotificationSound(named: "RestEnd.caf")`. The iPhone also vibrates according to its own settings.
  - **Sound off, Haptics on:** a bundled **silent** sound, `RestEndSilent.caf` (about 0.5 s of silence, synthesized by the main session like `RestEnd.caf`). The iPhone vibrates without the chime. Whether this vibrates is checked on a real device; if it doesn't, fall back to fully silent and adjust the footer.
  - **Both off:** no sound (a silent banner).
- **Background rest end (review finding 1).** Phase 3's `autoAdvance` clears the rest at `restEndsAt` even when the app isn't active. With the seam, that would cancel the notification at the moment it fires, while the in-app alert is skipped, so there would be no alert at all. So:
  - `autoAdvance` (and so `finishRest`) **doesn't clear the rest while the app is in the background**. The rest stays stored, the notification fires, and `settleExpiredRest` clears it silently on `.active` (phase 3 behaviour).
  - While the app is **inactive** (Control Center or Notification Center pulled down; the app is still on screen), `autoAdvance` clears the rest **and plays the in-app alert** (`RestAlert` plays unless the app is in the background, instead of only when active). The `rest-end` notification isn't shown in the foreground (see the delegate), so there's still only one alert.
  - **A cancel in the first second after the fire date is skipped** (one-sided: a cancel before the fire date always runs, since it's a user action like Pause or Skip Rest; step 2a review), and **delivered** notifications are removed only by a reconcile that runs when the app becomes active or launches, so a banner that just arrived isn't pulled away.
- **In the foreground** (active or inactive) the app plays its own alert, so `RestNotificationDelegate` returns no presentation options for `rest-end` in `willPresent` (which iOS only calls while the app is in the foreground; no state check needed). Other notifications (none yet) get the default banner, list and sound.
- **Delegate isolation (review finding 6):** `nonisolated final class RestNotificationDelegate: NSObject, UNUserNotificationCenterDelegate`, only comparing the identifier (a constant). `UNUserNotificationCenter.delegate` is **weak**, so `LiveSessionEffects` keeps a strong `static let` reference. It's installed in `WorkoutBuddyApp.init` through `LiveSessionEffects` (so never in tests, UI-testing mode or previews).
- **Tapping the notification** only opens the app; the cover and `settleExpiredRest` show the next set.
- **Permission:** `WorkoutDetailView.start` calls `effects.requestNotificationPermissionIfNeeded()` after a **successful Start** — "the first time you start a workout" (F4). The live version asks for `[.alert, .sound]` only when the status is `.notDetermined`. The prompt appears over the session cover. If it's denied, the in-app alert and the Live Activity still work. The scheduler's `add` then fails with `UNError.notificationsNotAllowed` on every rest; that case is **not logged** (it's expected), other failures are.

### Settings (phase 1 hook)
- The **Rest-end alert** section keeps **Sound** and **Haptics** and gets a footer. Draft (to be shown to the user with before/after in step 3): "When the app is in the background, a notification alerts you: with the sound if Sound is on, or with a vibration if only Haptics is on."
- When permission is **denied**, the section shows "Notifications are off" with an **Open Settings** button (`UIApplication.openNotificationSettingsURLString`). The status comes from `effects.notificationAuthorization()` on appear and when the app becomes active, so in tests and UI-testing mode it's always `.allowed` and the row never shows. (The UI test `testSettingsAreIsolatedPerLaunch` opens Settings; it's unaffected.)

### Live Activity (part B)
- **Shared attributes.** `nonisolated struct WorkoutActivityAttributes: ActivityAttributes` with `sessionID: UUID` (static) and a `nonisolated struct ContentState: Codable, Hashable, Sendable` (both explicitly `nonisolated`, so the conformances aren't main-actor isolated; review finding 6). They live in a new synchronized folder `LiveActivityContract/` at the repo root that is a member of **both** the app and the widget extension (like `UITestingContract/`).
- **Pre-formatted content.** The content state carries **ready-made texts** plus the dates the system timers need, built in the app by a pure `LiveActivityContent.make(from: SessionEffectsState, now:)` with the existing `SessionMessages`, `SetSummary` and `Formatters`. The widget needs no SwiftData, no `Formatters` and no name lookup. Spoken forms are included where `SessionMessages` has them. Far under ActivityKit's 4 KB limit.
- **Phases** (`ContentState.phase`):
  - **Set:** workout name, exercise name, "Exercise 2 of 5 · Set 3 of 4", the set's reps × kg from `prefill` (`SetSummary.line`, Bodyweight for 0 kg), and the elapsed time: `Text(timerInterval:pauseTime:countsDown: false, showsHours: true)` over `ElapsedTimerInfo.interval`.
  - **Rest:** a system countdown over `RestTimerInfo.interval` (`countsDown: true`) and `ProgressView(timerInterval:countsDown:)`, the "Up next" line, and the elapsed time. The layout must read well at 0:00 too (the countdown stops there).
  - **Rest over (stale):** the activity's `staleDate` is `restEndsAt` during a rest. A suspended app can't update the activity when the rest ends, so when `context.isStale` the widget shows **"Rest over"** and the next set. The system re-renders **shortly after** the stale date, not exactly at 0 (reports say up to a minute or two; review finding 5); until then the countdown shows 0:00 with the up-next line. The rule "which phase to draw, given the state and `isStale`" is a pure function in the contract folder, covered by the app's unit tests.
  - **Paused:** "Paused", the elapsed time frozen with `pauseTime` (a count-up timer does freeze), and, if a rest was running, its remaining time as **static text** (`Formatters.rest` of the frozen remaining time), because `pauseTime` doesn't freeze a countdown (phase 3, step 6 review).
  - **Finished, waiting for Save:** `SessionMessages.summaryTitle` ("Workout Complete" / "Workout Ended") and the duration (`Formatters.duration`), static.
- **Activity states (review finding 2).** The adapter maps `activityState` to **live** (`.active`, `.stale`, and `.pending` on iOS 26+, named only inside `if #available(iOS 26, *)`) or **gone** (`.ended`, `.dismissed`, `@unknown default`). Only live activities count as existing; an update with a new stale date brings a `.stale` one back. Gone activities need no `end`.
- **Lifecycle** (the coordinator's desired state): one activity per session.
  - `.active` state and no live activity for that session → **request** one, if `ActivityAuthorizationInfo().areActivitiesEnabled` (otherwise nothing, silently), **unless this process already requested one for that session** (review finding 3, the user's default): an activity the user swiped away stays away for the rest of the app run instead of coming back at the next Done. The coordinator keeps the requested session IDs in memory; after a relaunch it requests once more. A request that **failed** is retried at the next reconcile. `Activity.request` only works in the foreground; Start, launch and `.active` are all foreground.
  - A live activity for the session exists → **update** it when the content state or stale date differ from its current content.
  - `.none`, or live activities of other session IDs → **end** them with dismissal `.immediate` (Save, Discard, recovery Discard, strays after a kill). The user is in the app at that moment, so nothing needs to stay on the Lock Screen.
- **Concurrency (review finding 6).** `Activity` isn't `Sendable`, and `UNUserNotificationCenter` has no Sendable annotation. The adapters never store them: each call looks up `UNUserNotificationCenter.current()` or `Activity<WorkoutActivityAttributes>.activities.first { $0.id == id }` locally, and the protocols pass only values (IDs, session IDs, content states, dates). `@preconcurrency import` is the fallback if the SDK still complains.
- **Tapping the Live Activity** opens the app (the default; the cover is always on top).
- **Dynamic Island and Lock Screen (review finding 17):** compact leading = phase symbol (`dumbbell.fill` set, `timer` rest, `pause.fill` paused, `checkmark` finished), compact trailing = the countdown during rest, else the elapsed time; minimal = the countdown during rest, else the symbol; expanded = the Lock Screen content condensed. Timer texts get monospaced digits and a fixed width (a `Text(timerInterval:)` otherwise takes the widest possible string), the minimal timer a frame cap and `minimumScaleFactor` so it fits the small circle. Lock Screen: system margins, medium or heavier text weight, system colours (the look waits for the UI tidying session).
- **Widget extension target (user in Xcode, then the main session; review finding 12).** The user creates it in Xcode from the step 5 checklist; the main session then sets and checks the build settings and trims the template code. Target: `WorkoutBuddyWidgets`, bundle ID `net.poukar.WorkoutBuddy.WorkoutBuddyWidgets` (Xcode's default prefix), iOS 18.0, Swift 6, default actor isolation `MainActor` and Approachable Concurrency like the other targets, the same team, embedded in the app. The app gets `INFOPLIST_KEY_NSSupportsLiveActivities = YES`. The extension contains only the Live Activity widget in a `WidgetBundle`.

## Folder layout
- `WorkoutBuddy/Features/Session/Effects/`: `SessionEffects` and friends, the notification plan, coordinator, adapter and delegate; in part B the Live Activity content, coordinator and adapter.
- `LiveActivityContract/`: `WorkoutActivityAttributes` and the pure presentation rule (app + widget).
- `WorkoutBuddyWidgets/`: the widget bundle and the Live Activity views (widget only).
- `WorkoutBuddyTests/Features/Session/Effects/` mirrors the app folder.

## Key design decisions
- **Actor isolation:** the pure types (`SessionEffectsState`, `RestNotificationPlan`, `LiveActivityContent`, the attributes and the presentation rule) are `nonisolated`, `Equatable` and `Sendable`, and take `now` / `locale` / settings as parameters. The coordinators, protocols and adapters are `@MainActor`; the delegate is `nonisolated`.
- **Logging:** failed system calls are logged with `ErrorLogging.log` and the category `"session"`, never shown: a missing banner mustn't interrupt the workout. `notificationsNotAllowed` isn't logged.
- **Reuse:** `SessionLibrary.snapshot(of:)`; `exerciseNames(of:)` moves from `ActiveSessionView` into `SessionLibrary`, used by both; `SessionMessages.upNext` / `position` / `summaryTitle` / `fallbackExerciseName` / `fallbackWorkoutName`; `SetSummary.line`; `Formatters.rest` / `duration`; `ElapsedTimerInfo` and `RestTimerInfo` for the timer dates; `AppSettings.current()` for Sound and Haptics.
- **Previews:** widget previews with `#Preview(as: .content, using: attributes) { … } contentStates: { … }` and the Dynamic Island families, for each phase, Bodyweight and a long exercise name. Compiled in every configuration. Previews of the app never reach the system (the provider's preview gate).

## Steps

### Part A — rest-end notification

**Step 1 — The side-effect seam**
- `Features/Session/Effects/SessionEffects.swift`: `SessionEffectsState`, `NotificationAuthorization`, the `SessionEffects` protocol, `NoSessionEffects`, `SessionEffectsProvider.current` (returns `NoSessionEffects` everywhere for now; step 2b adds `LiveSessionEffects`, keeping the test / UI-testing / preview gate as a pure tested function of the environment and launch arguments).
- `SessionLibrary`: `init(context:effects:)`; `effectsState()` (fetch failure logged, report skipped); `exerciseNames(of:)` moved here (`ActiveSessionView` uses it); the report after every successful save in `commit` and `start`.
- Tests (`SessionEffectsTests`, a recording fake, in-memory container): start reports the first set; Done with rest reports a resting snapshot; Skip Rest, Undo, Pause, Resume, End, Back to Workout and the review edits each report the new state; Save and Discard report `.none`; names come from the references (rename the exercise, the next report has the new name). **Report after save:** the fake records `context.hasChanges` at report time and expects `false` (forcing a failed save on an in-memory store isn't practical; review finding 11). The provider gate: tests, UI-testing and previews → no-op.

**Step 2a — Rest notification: the plan and the coordinator (pure and faked)**
- `RestNotificationPlan` (pure): `decide(_:settings:now:) -> .schedule(RestNotificationRequest) / .cancel`; `RestNotificationRequest` has `fireDate`, `title`, `body` and `sound` (`.chime` / `.silent` / `.none`). Title in `SessionMessages` (`restOverNotificationTitle`).
- `NotificationScheduling` protocol (values only, no `UserNotifications` import): `schedule(_ request:) async throws`, `cancel()`, `removeDelivered()`, `authorization()`, `requestAuthorization() async throws`, and the app-level `NotificationSchedulingError.notAllowed`.
- `RestNotificationCoordinator`: `reconcile(_:settings:appBecameActive:)`, latest state wins, serial application; delivered notifications removed only for a reconcile marked "app became active" (the mark survives a newer state replacing it); **the cancel guard lives here** (it remembers the fire date it scheduled; skips a cancel only from the fire date to 1 s after it; always cancels when it scheduled nothing, e.g. after a relaunch); failures logged except `.notAllowed`.
- Tests: the plan for a running set, resting, rest expired, paused while resting, finished, `.none`; the sound for each Sound/Haptics combination; Bodyweight and a missing exercise name; `en_CZ` numbers in the body. The coordinator with a fake: schedule then cancel ends cancelled; three quick states apply only the first and the last; a failure is logged and the next state still applies; `notificationsNotAllowed` isn't logged; removing delivered only on the active reconcile.

**Step 2b — Rest notification: the system adapter, the delegate and the wiring** (main session first adds `WorkoutBuddy/Resources/RestEndSilent.caf`)
- `UserNotificationScheduler` (adapter: identifier `rest-end`, the sound file names, trigger ≥ 1 s, skip if past, maps `UNError.notificationsNotAllowed` to `NotificationSchedulingError.notAllowed`, `UNUserNotificationCenter.current()` looked up per call). **No cancel guard here**: it's in the coordinator.
- `SessionEffects` gets `appBecameActive(_ state:)` (step 2a review): the "came back to the app" reconcile, which also removes delivered notifications. `NoSessionEffects` and the step 1 test fake implement it.
- `RestNotificationDelegate` (`nonisolated`, `[]` for `rest-end`); the identifier rule as a pure function, tested.
- `LiveSessionEffects.shared` (holds the coordinator and the delegate strongly; installs the delegate); `SessionEffectsProvider.current` returns it outside tests, UI-testing and previews; `WorkoutBuddyApp.init` touches it so the delegate is set before any notification arrives.
- `RootTabView`: `effects.appBecameActive(library.effectsState())` in the launch check **and** on `.active` (a launch is always in the foreground, so it counts as coming back; an old "Rest Over" from before a kill is removed then).
- `ActiveSessionView.autoAdvance`: don't clear the rest in the background; in the inactive state clear it and play `RestAlert`. The rule (app state → clear? play?) as a pure function in `RestAlertRules`, tested.
- Run the Release build too.

**Step 3 — Permission on the first Start, and Settings**
- `WorkoutDetailView.start`: after a successful start, `effects.requestNotificationPermissionIfNeeded()` (live: only when `.notDetermined`).
- `SettingsView`: the footer (wording agreed with the user in the step's discussion, before/after shown), and the "Notifications are off" row with **Open Settings** when `effects.notificationAuthorization()` is `.denied`, refreshed on appear and `.active`.
- Tests: the live effects ask only when not determined (through a fake scheduler); the Settings texts. The UI suite runs on CI with the phase PR.
- Run the Release build too (Settings previews).

**Step 4 — Part A manual check (user)**
- On iPhone 17 / iOS 27 and iPhone 16 Pro / iOS 18.2 simulators (the user's manual-check devices). See "Manual check of part A" under Verification. Real-device items wait for the end of the phase.

### Part B — Live Activity (fresh session)

**Step 5 — Widget extension target and the shared folder (user + main session)**
- **User, in Xcode:** File › New › Target › Widget Extension; product name `WorkoutBuddyWidgets`; **tick** "Include Live Activity"; **untick** "Include Control" and "Include Configuration App Intent"; embed in `WorkoutBuddy`; don't activate the new scheme (keep the `WorkoutBuddy` scheme).
- **Main session:** set `IPHONEOS_DEPLOYMENT_TARGET = 18.0` on the extension (the template uses the newest OS), Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and Approachable Concurrency like the app, the same team; check the generated pieces (the extension's `Info.plist` with `NSExtension` → `com.apple.widgetkit-extension`, kept out of the synchronized folder's resources by an exception set; the "Embed Foundation Extensions" phase; the target dependency; `SKIP_INSTALL = YES`; the extension run-path); add `INFOPLIST_KEY_NSSupportsLiveActivities = YES` to the app (Debug and Release); create `LiveActivityContract/` as a synchronized folder in both targets with a **stub** `WorkoutActivityAttributes` so the template's `ActivityConfiguration` can use it; delete the template's static widget and sample attributes.
- Build Debug and Release, the device build (`xcodebuild build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`), and `build-for-testing` as CI does; run the unit tests that touch the app's launch. CI needs no workflow change (the scheme builds the dependency).
- `CLAUDE.md`: the targets list and the shared folder.

**Step 6 — Attributes and the pure Live Activity content**
- `LiveActivityContract/WorkoutActivityAttributes.swift`: the real attributes, `ContentState` (phase, texts, spoken texts, the timer dates, the frozen rest text) and the presentation rule (`displayPhase(isStale:)`).
- `Features/Session/Effects/LiveActivityContent.swift`: `make(from:now:locale:) -> (state, staleDate)?` (`nil` for `.none`).
- Tests: every phase; paused during a set and during a rest (frozen texts); finished complete / ended; stale rest → "Rest over" with the next set; Bodyweight; a missing exercise or workout name; `en_US` and `en_CZ`; the encoded state stays small for a long exercise name.

**Step 7 — Live Activity coordinator and wiring**
- `LiveActivityControlling` protocol (values only: the live activities as (ID, session ID, content state, stale date); `request`; `update(id:state:staleDate:)`; `end(id:)`; `areActivitiesEnabled`) and `ActivityKitController` (adapter: the state mapping, local lookups).
- `LiveActivityCoordinator`: the lifecycle rules, latest state wins, the requested-in-this-process set, failures logged. `LiveSessionEffects` forwards to it as well; launch and `.active` already reconcile.
- The widget keeps the template's simple view for now, so the reviewer can see the activity appear.
- Tests with a fake controller: start → request; update only when the state or stale date changed; Save / Discard → end `.immediate`; a stray of another session ended at launch; ended and dismissed activities don't count as existing; a dismissed activity isn't requested again in the same process, but is after a "relaunch" (a new coordinator); a failed request is retried; activities disabled → nothing requested.

**Step 8 — The Live Activity views**
- `WorkoutBuddyWidgets/WorkoutLiveActivity.swift`: the Lock Screen view and the Dynamic Island (expanded, compact, minimal) for each display phase, as described in Decisions; spoken texts as accessibility labels.
- Previews for each phase, Bodyweight, a long name, and the Dynamic Island families.
- Run the Release build too.
- **Runtime check by the code reviewer** on iOS 27 and 18.2: start a workout in the app, switch to another app (`xcrun simctl launch booted com.apple.Preferences`) and screenshot the compact Dynamic Island during a set, a rest and a pause. The Lock Screen view needs Device › Lock in the Simulator menu, so it's a user check (step 9).

**Step 9 — Wrap-up**
- `FEATURES.md` F4: what the Live Activity shows after a rest ends while the app is suspended ("Rest over" with the next set, shortly after the countdown reaches 0) and the Sound/Haptics behaviour of the notification.
- The status section of this plan.
- Push and the PR (with the user); CI green (full unit + UI suites).
- The manual check of part B and the real-device check (see Verification).

## Hooks left for later phases
- **Phase 5 (History):** nothing from this phase. Deleting a saved session from History doesn't touch notifications or activities (only in-progress sessions have them).
- **Phase 7 (Export):** nothing new is stored; the Live Activity and the notification are derived from the session.
- **UI tidying session:** the Live Activity's look (colours, layout).
- **Later (out of scope now):** interactive Live Activity buttons (Done / Skip via App Intents); push updates so the activity switches to the next set by itself at rest end; Time Sensitive notifications if Focus modes turn out to hide the alert.

## Verification
- Each step: the build, the step's unit test suites on iPhone 17 / OS 27.0 and iPhone 16 / OS 18.2 (with `-parallel-testing-enabled NO` if the clone fails), the Release build where the step says so, and the `code-reviewer` review. The full unit suite and the UI suite run on GitHub CI with the phase PR.
- **Manual check of part A** (by the user at the laptop, iOS 27 and iOS 18.2 simulators):
  - First Start of a workout: the permission prompt appears once; later Starts don't ask.
  - Rest with the app in the background or the simulator locked: shortly at 0 the "Rest Over" banner with the up-next line and the chime (Sound on); no sound with Sound off.
  - Lock the simulator with about 3 s of rest left: the banner and chime still come (review finding 1).
  - Control Center pulled down at 0: the in-app chime plays, no banner; closing it shows the next set.
  - Skip Rest, Undo, Pause and End Workout during a rest: no banner later. Pause then Resume: the banner comes at the shifted end.
  - App in the foreground at rest end: only the in-app alert, no banner.
  - Kill the app during a rest: the banner still comes; relaunch → recovery alert as before.
  - Deny permission (delete the app from the simulator and run it again, or erase the simulator): the workout works; Settings shows "Notifications are off" and Open Settings opens the app's notification settings.
  - Notification Center doesn't keep an old "Rest Over" once the app is back on the next set.
- **Manual check of part B** (simulators, both OS versions): the Live Activity on the Lock Screen (Device › Lock) and in the Dynamic Island for a set, a rest, a paused set and rest, and the finished summary; the countdown and elapsed time run while the app is in the background; shortly after a rest ends while locked it shows "Rest over" and the next set; coming back to the app shows the next set and the activity follows; Save and Discard remove it; swiping the activity away keeps it away until the next launch; after a kill and relaunch there's exactly one activity (or none after Discard); turning Live Activities off in Settings › Workout Buddy stops new ones without errors.
- **Real device** (the simulator can't show these reliably): the notification's sound and vibration with the ring switch on and off; **Sound off + Haptics on vibrates without sound** (the silent sound file); the Dynamic Island's look; how promptly "Rest over" appears; VoiceOver on the Lock Screen activity; the Sound and Haptics toggles left over from phase 3.

## Review decisions

**Architect review of the plan (2026-11-12), verdict "Approve with changes", 17 findings, discussed with the user:**
1. [Major] A rest ending while the app was alive but not active gave no alert at all → **accepted**: no rest clearing in the background, the in-app alert also when inactive, no cancel within 1 s of the fire date, delivered banners removed only on `.active`; two manual-check cases.
2. [Major] Activities that ended or were dismissed are still listed; iOS 26 adds `.pending` → **accepted**: live/gone mapping in the adapter, tests.
3. Should a dismissed activity come back? → **user's default**: not within the same app run; retried only after a failed request; `.immediate` on Save and Discard.
4. A soundless notification doesn't vibrate → **user's decision**: Sound off + Haptics on uses a silent sound file so the phone vibrates (real-device check).
5. "Rest over" may appear a minute or two after 0 → **accepted**: "shortly after" in the wording and the checks; the rest layout reads well at 0:00.
6. Concurrency details (non-Sendable `Activity` and notification center, delegate isolation, weak delegate, `nonisolated` attributes) → **accepted**.
7. `SessionEffects.current` couldn't compile on a protocol; previews would reach the system → **accepted**: `SessionEffectsProvider`, preview gate.
8. A failed post-save fetch mustn't fail a saved action → **accepted**: logged, report skipped.
9. Step order in part B → **accepted**: stub attributes in step 5; the coordinator (step 7) before the views (step 8), where the runtime check happens.
10. Permission gating duplicated → **accepted**: through `SessionEffects`.
11. No existing save-failure tests to copy → **accepted**: `context.hasChanges == false` at report time.
12. An extension needs more than the plan listed → **user's decision**: the user creates the target in Xcode from the step 5 checklist; the main session checks the settings.
13. `simctl` has no notification-permission reset or lock → **accepted**: reinstall to reset; Lock Screen is a user check; the reviewer uses the Dynamic Island from another app.
14. Time Sensitive notifications → **user's decision: no**; interruption level `.active`; listed under Hooks for later.
15. Footer wording and a wrong claim about the UI tests → **accepted**: wording follows decision 4 and is agreed in step 3; the claim fixed.
16. Step 2 too big; local suite runs vs. the 8 GB Mac → **accepted**: steps 2a and 2b; **user's decision**: only the step's suites locally, full suites on CI.
17. Dynamic Island sizes and Lock Screen layout → **accepted**.

**Step 2a code review, verdict "Approve with fixes", 3 findings, discussed with the user** (plus the implementer's deviations, **accepted**: the cancel guard in the coordinator, so `cancel()` takes no `now`; `requestAuthorization()` is `async throws`; `decide` takes a `locale`; `NotificationSchedulingError.notAllowed` mapped by the 2b adapter):
1. The plan text didn't match what was built → **fixed** in steps 2a and 2b.
2. **User's decision:** the 1 s cancel guard is one-sided (from the fire date to 1 s after); a cancel before the fire date always runs, so Pause in the last second can't leave a stale "Rest Over".
3. The "came back to the app" mark had no way through `SessionEffects`, and a launch didn't remove an old delivered banner → **accepted**: `appBecameActive(_:)` in step 2b, called at launch and on `.active`.

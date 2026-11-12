# UI tests — a permanent XCUITest target, run in CI

Not a `FEATURES.md` phase: this adds a permanent UI test target so the phase 3 flows (and later phases) are checked at runtime by tests instead of throwaway harnesses. During phase 3 the code reviewers built scratch XCUITest targets again and again to check the app at runtime; this plan makes that permanent, adds the tests the reviewers ran by hand, and runs them in CI.

The work goes on the branch `phase-3-session` (phase 3 is complete there, latest commit 6e67305, not pushed). Nothing is pushed and no PR is opened without the user.

## Workflow
As in `CLAUDE.md`, with the findings discussed with the user before anything changes:
1. Steps marked **(main session)** are project setup (targets, schemes, folders, CI verification). The main session does them itself; no subagent touches the Xcode project.
2. Every other step: run `implementer` with this plan's path and the step number, handle its "Needs main session" list, run `code-reviewer` with the plan, the step and the implementer's report, discuss the findings with the user, apply the agreed fixes through `implementer`, and commit once the build and all tests are green: `UI tests, step N: <what it did>`. If the plan changed because of the step, the plan goes in the same commit.

## Scope
- **In scope:** a `WorkoutBuddyUITests` target in the `WorkoutBuddy` scheme; a UI-testing launch mode in the app (in-memory store, isolated settings, seeded scenarios); UI tests for the phase 3 flows and a smoke test of the phase 2 template editor; CI running them; `CLAUDE.md` commands.
- **Out of scope:** accessibility audits (`performAccessibilityAudit`) and VoiceOver checks (XCUITest's element tree also lists accessibility-hidden elements, so it can't prove what VoiceOver reaches; that stays a real-device check); screenshots or snapshot tests; Settings → Exercises tests (phase 1, well covered by unit tests); performance tests. Any of these can be added later on top of this target.

## Decisions
- **XCTest for UI tests.** UI tests need `XCUIApplication`, which is driven from `XCTestCase`; the unit tests stay on Swift Testing. The target uses the same Swift 6 / `MainActor` default isolation as the others, but a `MainActor` test class doesn't compile: its inferred initializers and `setUpWithError` clash with `XCTestCase`'s nonisolated ones (found in step 1). So the UI test classes are **`nonisolated`**, and the test methods are **`@MainActor`** (`XCUIApplication` and `XCUIElement` are main-actor API); support helpers outside the classes keep the default `MainActor` isolation. **`setUpWithError` only sets `continueAfterFailure = false`**; every test starts with `let app = launch(scenario: …)` (review finding 6).
- **One scheme, split by filters.** The UI test target joins the `WorkoutBuddy` scheme's test action, marked **not parallelizable** (UI tests on one simulator, in order). Commands select the target: unit tests with `-only-testing:WorkoutBuddyTests`, UI tests with `-only-testing:WorkoutBuddyUITests`. A plain `xcodebuild test` runs both. `CLAUDE.md`'s per-step unit command gets the filter, so implementer and reviewer runs stay as fast as today, and a separate UI command is added (step 1).
- **Shared contract.** The launch argument names, the scenario names, the accessibility identifiers and the expected spoken texts the tests rely on are needed by both the app and the UI tests, which can't import the app module. They live in one `nonisolated` file in a new synchronized folder `UITestingContract/` at the repo root, which is a member of **both** the app target and the UI test target (main session, step 1). A typo then fails to compile instead of failing a test at runtime.
- **The UI-testing launch mode** is switched on only by the launch argument `-uiTesting`, which only the UI tests pass. Without it nothing changes: a normal launch and the unit-test host (which never passes it) behave exactly as today. The arguments are parsed by a pure `nonisolated` function of `ProcessInfo.arguments` (unit tested). In UI-testing mode:
  - **Store:** in memory by default, so the tests never touch the user's data on the simulator (the UI tests install over the same app the user checks by hand). A fresh store gets the normal exercise seed and then the scenario's data.
  - **Settings:** every `@AppStorage` and `AppSettings.current()` read goes to one `AppSettings.store: UserDefaults`: `.standard` normally, and a separate suite (`net.poukar.WorkoutBuddy.uiTesting`) in UI-testing mode, cleared at launch, with **Sound and Haptics off** so test runs are silent. The app root sets `.defaultAppStorage(AppSettings.store)`; `AppSettings.current(in:)` defaults to `AppSettings.store` instead of `.standard`. (The `@AppStorage` users are exactly `SettingsView`, `WeightField` and `LargeWeightControl`; the `current()` callers are `WorkoutEditorView`, `ExerciseEditorView` and `RestAlert`.)
  - **Region:** the UI tests launch with `-AppleLanguages (en) -AppleLocale en_US` (standard argument-domain overrides, not written anywhere), so number texts are predictable ("62.5", "1,420 kilograms") on the Czech-region simulators here and on CI alike. Foundation reads launch arguments as `-key value` pairs, so the region pairs come **first** in the argument list and the app's own flags take explicit values (`-uiTesting YES`, `-uiTestingKeepData YES`); one test asserts the English number format to prove the override applied (review finding 7). Region-dependent formatting stays covered by the unit tests (`en_CZ`).
  - **Notifications (phase 4):** UI-testing mode never requests notification permission, so no system prompt can block a test (review finding 14).
  - It is compiled in every configuration (no `#if DEBUG`), like the preview data, because a Debug-only helper broke the Release build before. In a Release build it still only reacts to `-uiTesting`, which a user can't pass.
- **Seeded scenarios** (`-uiTestingScenario <name>`), built with the app's own `WorkoutLibrary` / `SessionLibrary` calls, never by poking models. Templates are built with `WorkoutDraft(name:exercises:)` and `DraftExercise` / `DraftSet` (the pattern in `SessionFixture`), and use built-in exercises looked up with `WorkoutPreviewData.exercise(named:in:)`, so names are stable. Unlike `SessionPreviewData`, scenarios call everything with `try` and stop the app with a clear message on failure, and they respect the library's rules: an action that doesn't apply is a silent no-op (Skip Set while a rest runs does nothing), so the session scenarios call `skipRest` (or pass a later `now:`) between actions. Unit tests check the resulting state of each scenario (review finding 13).
  - `empty` (the default): the exercise seed only.
  - `templates`: **"Short Rests"** — Bench Press 10 × 60 kg rest 10 s, Bench Press 8 × 62.5 kg rest 0, Overhead Press 8 × 40 kg rest 10 s; **"Long Rests"** — the same sets with 600 s rests (the maximum), so a test has all the time it needs on the rest screen. The short rest exercises auto-advance (10 s, so even a slow CI runner sees the rest screen first; review finding 5); the 0 rest exercises "no rest screen"; the last set exercises "straight to the summary". Completing all three sets as planned gives a volume of 1,420 kg.
  - `inProgress`: `templates` plus a running "Long Rests" session started a few minutes ago: the first set done (10 × 60), the second skipped, the current set Overhead Press. On launch it raises the recovery alert (Resume / End Workout), exactly as after a kill; tests that only need the running workout tap Resume first. Used for recovery and for looking back at earlier sets.
  - `nothingDone`: `templates` plus a running "Long Rests" session with only the first set skipped. On launch the alert offers Resume / Discard.
  - `onSummary`: `templates` plus a "Long Rests" session with all three sets done, finished and waiting for Save. On launch the summary opens without asking.
  The recovery alert is the app's real launch check; no scenario bypasses it.
- **A real kill-and-relaunch test** needs data that survives the process, so UI-testing mode has a second store option: `-uiTestingStore disk` uses a separate store file (`UITesting.store` in the app's temporary directory, never the real `default.store`), wiped at launch unless `-uiTestingKeepData YES` is passed; with it the settings suite is kept too and no scenario is seeded. The test launches with `disk`, starts a workout, does a set, calls `XCUIApplication.terminate()`, and launches again with `disk` + keep data. This checks "progress is saved after every action" end to end, which the seeded scenarios can't. The store-file deletion moves out of `ModelContainerFactory`'s `#if targetEnvironment(simulator)` block (only the "reset the real store on a load failure" policy stays simulator-only), so device builds still compile (review finding 8).
- **Tests check accessibility labels and values, not visible text** (review finding 1). XCUITest matches what VoiceOver gets, and many session texts have a spoken form that replaces the visible one. The expected strings are the spoken forms, for example:
  - the position line: "Exercise 1 of 2, set 1 of 2" (not "Exercise 1 of 2 · Set 1 of 2")
  - summary counts: "3 sets completed", "1 set skipped", "2 sets not performed"
  - volume: one element labelled "Volume" with the value "1,420 kilograms"
  - the kg control's value: "62.5 kilograms"; the reps control's value: "10"
  - a Workouts list row: the workout name as its label; "Last done" is inside its value, so it's matched with `CONTAINS`
  - "Up next": the label; the spoken line is the value
  - the recovery message uses curly quotes around the workout name (“Long Rests”)
  Where a value contains a date or other changing part, the test matches with `CONTAINS` / `BEGINSWITH` predicates. The exact strings the tests use are kept in the contract file.
- **Screens are identified by layer, not by the buttons they contain** (review finding 2). During a review, and under the paused overlay, the screen underneath stays alive and, although hidden from VoiceOver, still appears in XCUITest's element tree, so `buttons["Done"]` would exist while a review shows, labels would appear twice, and `firstMatch` could read the hidden control's value. Each layer root therefore gets a **container identifier**: `.accessibilityElement(children: .contain).accessibilityIdentifier(…)` on the set screen, rest screen, review, paused overlay and summary. A `.contain` container doesn't pass its identifier down to its children and doesn't change what VoiceOver reads. Every query is scoped to the top layer, and "on the set screen" means: the set container exists and neither the review nor the paused container does.
- **Other identifiers** only where a label is ambiguous or not reachable, on leaf elements (an identifier on a plain container is copied onto all its children in SwiftUI), never changing labels, traits or what VoiceOver reads:
  - the set screen's **Done** button ("Done" is also the keyboard's Done button, the review badge and the template editor's Edit/Done) — the keyboard's button is queried as `app.toolbars.buttons["Done"]`;
  - the paused overlay's **End Workout** and the summary's **Discard Workout** buttons, so the dialog helper can tell them from the confirmation's buttons (review finding 3);
  - the large reps and kg controls (one adjustable element each).
- **The − / + buttons and the typed value** (review finding 4). Each large control is one combined accessibility element; its − / + buttons are hidden from VoiceOver and its text field is a child of the combined element, so they may not be reachable by XCUITest, and XCUITest can't increment an adjustable element. Step 3b probes this first. If identifiers on the inner buttons and field reach XCUITest, use them; if not, keep the single VoiceOver element unchanged and tap `control.coordinate(withNormalizedOffset:)` at its left edge (−), right edge (+) or centre (the value, to type), at the default text size. The value is always read from the control's `value`.
- **Dialogs.** "End Workout" and "Discard Workout" appear both as a screen button and as the confirmation's button. The confirmation is an action sheet on iOS 18, but on iOS 26+ a popover that animates from its source button and may replace it in the tree. One helper taps the button with `label == X AND identifier != <the screen button's identifier>`, which works whether or not the source button is still there; tests never pick by index.
- **Waiting, not sleeping.** No `sleep`. Every wait is `waitForExistence(timeout:)`, `waitForNonExistence(timeout:)` or an `XCTNSPredicateExpectation`, with a 10 s default and 25 s for auto-advance (10 s rest plus launch load). Each test launches its own app with its own scenario, so tests don't depend on order.
- **Swipes** use coordinate drags (`XCUICoordinate.press(forDuration:thenDragTo:withVelocity: .fast, thenHoldForDuration:)`) on the scrolling content, away from the screen edges: in phase 3 these were the real synthesized touches the app's `UISwipeGestureRecognizer` responds to.
- **Known risk: idle waiting** (review finding 5). XCUITest waits for the app to be idle before each action. The rest screen's progress ring is a `TimelineView(.animation)`, which may keep the app "busy". Step 3b probes it on **"Long Rests"** (a short rest would end by itself and hide a stall): Done → rest screen → tap Skip Rest and time it; it must take under 10 s (step 3b found no stall: 1.7–1.9 s here; a real stall shows up as XCUITest's idle timeout of tens of seconds, and 3 s was too tight for slower CI runners). If actions on the rest screen stall, the fallback (decided with the user then) is a UI-testing-only switch that draws the ring with the Reduce Motion schedule (`.periodic` by 1 s), which is already a supported mode.
- **Fresh simulators.** The first keyboard on a new simulator may show the "Speed up your typing" introduction over the keys. CI turns it off before the UI tests (`simctl spawn <UDID> defaults write com.apple.keyboard.preferences DidShowContinuousPathIntroduction -bool true` on the booted simulator), and the launch helper dismisses it if it still appears (review finding 11).
- **No retries** of failed UI tests in CI (`-retry-tests-on-failure` hides flakiness). A flaky test is a bug to fix in the test or the app.
- **CI time.** About 28 UI tests, each with a fresh launch. The architect review estimated 6–10 minutes on CI (review finding 12), but in step 2 each UI test took about 30–100 s on iOS 27 on this Mac (mostly the app launch and XCUITest's idle waiting), which would make the suite **up to about 20 minutes**. The real CI figure is measured in step 8 from the `.xcresult` per-test durations. The job's timeout goes from 30 to 45 minutes; if the UI step is too slow there, step 8 moves the UI tests into their own job with its own timeout (decided with the user then).
- **Known tooling problem.** After a failing UI test, `xcodebuild test` hangs in `simctl diagnose` (found in step 2, every time, not only occasionally). `pkill -f "simctl diagnose"` lets the run finish.

## Folder layout
- `UITestingContract/UITestingContract.swift` — shared by the app and the UI test target.
- `WorkoutBuddy/App/UITesting/` — the launch mode parsing, the store and settings set-up, the scenarios.
- `WorkoutBuddyUITests/` — `Support/` (launch helper, waits, screen checks, the dialog helper, swipes, value controls), then one file per area: `TemplateEditorUITests`, `SessionFlowUITests`, `SessionEndUITests`, `ReviewSetsUITests`, `RecoveryUITests`.
- `WorkoutBuddyTests/App/` — unit tests of the launch mode parsing and the scenarios.

## Steps

**Step 1 — Target, scheme and commands (main session)**
- Create the `WorkoutBuddyUITests` UI testing bundle target (product type `com.apple.product-type.bundle.ui-testing`), done in Xcode or by editing `project.pbxproj` carefully (it's hand-written with simple IDs; the installed `xcodeproj` gem 1.22 may not understand objectVersion 77 synchronized folders). Settings, listed so they aren't copied wrongly from the unit test target (review finding 10):
  - `TEST_TARGET_NAME = WorkoutBuddy`, and **no** `TEST_HOST` / `BUNDLE_LOADER` (those are for hosted unit tests);
  - a target dependency on `WorkoutBuddy` (`PBXTargetDependency` with its `PBXContainerItemProxy`);
  - `GENERATE_INFOPLIST_FILE = YES`, `PRODUCT_BUNDLE_IDENTIFIER = net.poukar.WorkoutBuddyUITests`, `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `TARGETED_DEVICE_FAMILY = 1`, `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, signing as the unit test target;
  - the synchronized folder `WorkoutBuddyUITests/` in its `fileSystemSynchronizedGroups`.
- Create the synchronized folder `UITestingContract/`, listed in **both** the app's and the UI test target's `fileSystemSynchronizedGroups`, with `UITestingContract.swift` holding only the `-uiTesting` argument for now.
- Add the target to the shared scheme's test action, `parallelizable = "NO"`.
- One placeholder test, `LaunchUITests.testAppLaunches`, launches the app with `-uiTesting YES` and waits for the Workouts tab, only to prove the target runs. No Xcode template launch-screenshot tests (they run once per configuration and are slow). Step 2 deletes the placeholder.
- `CLAUDE.md`: the unit test command gets `-only-testing:WorkoutBuddyTests`; add "Run the UI tests" (`-only-testing:WorkoutBuddyUITests`, plus `-parallel-testing-enabled NO` on iOS 18.2), the flakiness check (`-test-iterations 3 -run-tests-until-failure`), and one sentence on when to run them (steps that touch views or the UI tests; the code reviewer runs them on both OS versions); mention the new target and folder under "Project setup".
- Check: unit tests and the placeholder pass on iPhone 17 / iOS 27.0 and iPhone 16 / iOS 18.2; `xcodebuild build-for-testing` builds both bundles; the Release build still succeeds.

**Step 2 — UI-testing launch mode, launch helper and the template editor smoke test**
- `WorkoutBuddy/App/UITesting/UITestingLaunch.swift` (`nonisolated`, pure): `parse(_ arguments: [String]) -> UITestingLaunch?` returning `nil` without `-uiTesting`, else the options: scenario (default `empty`; an unknown name is a programming error and stops the app with a clear message), store (`memory` default / `disk`), keep data. Flags take explicit values (`YES`), see "Region".
- `ModelContainerFactory`: a way to build the UI-testing disk store at its own URL (`UITesting.store` in the temporary directory), deleting its files first unless keep data. The file deletion moves out of the simulator-only `#if`; the real store's load-failure policy doesn't change.
- `AppSettings.store`: `.standard`, or the cleared UI-testing suite with Sound and Haptics off. `AppSettings.current(in:)` defaults to it. `WorkoutBuddyApp` sets `.defaultAppStorage(AppSettings.store)` on the root view, so `SettingsView`, `WeightField` and `LargeWeightControl` follow without changes.
- `WorkoutBuddyApp.init`: decides the container from the launch mode (UI testing first, then the existing unit-test check, then the real store), then seeds the exercises as today. (Scenarios come in step 3a; until then every scenario name other than `empty` is rejected.)
- Unit tests: parsing (no flag → `nil`; defaults; each option; flags in any order; values missing or not `YES`); the disk-store URL is never the real store's; `AppSettings.current(in:)` still reads `.standard` when not UI testing (the existing `AppSettingsTests` stay green).
- `WorkoutBuddyUITests/Support/`: `launch(scenario:store:keepData:)` (region pairs first, then `-uiTesting YES` and the options; dismisses the keyboard introduction if it appears) and the wait helpers.
- UI tests (`TemplateEditorUITests`, the phase 2 smoke test): with `empty`, create "Smoke Test" — name, Add Exercise, search "Bench", pick Bench Press, change reps with the stepper, Save — and see it in the Workouts list; open it and see Start Workout enabled. A second test checks isolation: change the default reps in Settings, relaunch, and see the default again (the suite is cleared). Delete `LaunchUITests`.
- Checks: unit and UI tests on both OS versions, the Release build, and a device build (`xcodebuild build -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`).

**Step 3a — Seeded scenarios (app code only)**
- `WorkoutBuddy/App/UITesting/UITestingScenario.swift`: the scenarios from the Decisions (`templates`, `inProgress`, `nothingDone`, `onSummary`), seeded only into a fresh store, built as described there (`try`, a clear stop on failure, `skipRest` between actions, reused lookups and drafts).
- Unit tests, with an in-memory container: each scenario's templates, sets and rests, and each session's state (current set, done / skipped sets, finished or not, `LaunchRecovery.decide` giving the expected answer).
- Checks: unit tests on both OS versions; the Release build.

**Step 3b — Layer identifiers, support code, probes and the first session flow**
- Accessibility identifiers (contract file): the five layer containers, the set screen's Done, the paused overlay's End Workout, the summary's Discard Workout, the large reps and kg controls. Nothing else unless a test can't find an element; any extra one is listed in the report. The expected spoken strings go into the contract file too.
- `WorkoutBuddyUITests/Support/`: screen checks scoped to the top layer (`assertSetScreen(exercise:position:)`, `assertRestScreen()`, `assertSummary(title:)`, `assertReview(status:)`), the confirmation-dialog helper, the coordinate swipe helper, and the value-control helper (− / + / type / read value, by inner identifiers or by coordinates, whichever the probe shows works).
- **Probes first**, each reported with what was found, on iOS 27 and 18.2:
  1. Idle waiting on "Long Rests": Done → rest screen → Skip Rest takes under 10 s (was 3 s; see "Known risk: idle waiting").
  2. An `app.debugDescription` dump while a review shows and while paused: the layer containers are there and the scoped queries pick the top layer.
  3. Whether the − / + buttons and the text field can be reached (see Decisions); the helper uses the way that works.
  4. The dialog helper: Pause → End Workout → the confirmation → Cancel, on both OS versions.
  5. One coordinate swipe right on the set screen opens a review.
  These stay as tests where they make sense (the dialog and swipe probes become parts of steps 5 and 6's tests; the idle probe stays as `SessionFlowUITests.testRestScreenRespondsQuickly`).
- `SessionFlowUITests.testDoneRestAutoAdvanceToSummaryAndSave`: `templates` → "Short Rests" → Start Workout → set screen "Bench Press", "Exercise 1 of 2, set 1 of 2" → Done → rest screen → after 10 s the second Bench Press set opens by itself → Done (0 rest) → Overhead Press opens straight away → Done → summary "Workout Complete", "3 sets completed", volume "1,420 kilograms" (which also proves the English region applied) → Save → the cover closes and the "Short Rests" row's value contains "Last done".

**Step 4 — Set actions, rest actions and pause**
- `SessionFlowUITests` (all on "Long Rests" unless noted):
  - − / + on reps and kg change the values; Done saves them: the summary volume reflects the changed values (e.g. reps 11 and kg 62.5 on the first set).
  - Typing a kg value through the keyboard and its Done bar (`app.toolbars.buttons["Done"]`, the phase 1 `DecimalTextField`): "57.5" is kept after Done.
  - Skip Set on the first set → the second set opens with no rest screen.
  - Done → rest screen with "Up next" naming Bench Press → Skip Rest → the second set.
  - Done → Undo → the first set again with the values entered before Done.
  - Pause on the set screen → the paused layer with Resume and End Workout → Resume → the set screen. The same on the rest screen, and the rest screen is still there after Resume.

**Step 5 — Ending: summary, Save, Back to Workout, Discard**
- `SessionEndUITests`:
  - End early with a done set: Done, Skip Rest, Pause → End Workout → confirmation "End Workout?" → End Workout → summary "Workout Ended" with "1 set completed" and "2 sets not performed" → Save → cover closes, "Last done" shows.
  - Back to Workout after Done on the last set ("Long Rests": Done, Skip Rest, Done, Skip Rest, Done): summary → Back to Workout → the Overhead Press set screen again; Done → summary again.
  - Back to Workout after an early end: summary → Back to Workout → the second set's screen.
  - Nothing done: Start → Pause → End Workout → "Discard Workout?" → Discard Workout → the cover closes and the row's value doesn't contain "Last done".
  - Every set skipped: the summary is "Workout Ended" with the can't-save note and Discard Workout instead of Save → Discard Workout → confirm → the cover closes.

**Step 6 — Looking back at earlier sets**
- `ReviewSetsUITests`, on `inProgress` (tap Resume first) unless noted:
  - Change the current set's reps, then swipe right → the review of the skipped second set (status "Skipped") → swipe right → the done first set (status "Done") → swipe left twice → the current set, with its unsaved reps change still there.
  - The Previous Set button and the bottom bar's Previous / Next / Back to Current Set do the same.
  - Edit the done set's kg with + → Back to Current Set → finish the workout → the summary volume includes the corrected kg.
  - Mark as Done on the skipped set → its status reads "Done"; Mark as Skipped on the done set → "Skipped".
  - From the summary (`onSummary`): Review Sets → the last set's review with no Pause button → Mark as Skipped on all three → Back to Summary → Discard Workout replaces Save (the workout can't be saved any more).
  - (No "swipes ignored while paused" test: the paused overlay already takes every touch, so such a test couldn't fail for the reason it names; review finding 12.)

**Step 7 — Recovery after a kill**
- `RecoveryUITests`:
  - `inProgress`: the alert "Resume Workout?" with the message naming “Long Rests” → Resume → the Overhead Press set screen; no session layer exists before the alert is answered.
  - `inProgress` → End Workout → the summary "Workout Ended" → Save → the list shows "Last done".
  - `nothingDone` → the alert offers Discard, not End Workout → Discard → no cover, no "Last done".
  - `onSummary` → the summary opens without an alert.
  - Real kill (disk store): `templates` → "Long Rests" → Start → Done → rest screen → `terminate()` → relaunch with keep data → the alert → Resume → the rest screen still counting down; the same with End Workout → the summary with "1 set completed".

**Step 7b — Hardening against lost taps and keystrokes** (added after the step 7 review, 2026-10-26, by the main session)
- `tapSettled()` (in `Support/Waiting.swift`) before every first tap after a presentation: `startWorkout`, alert and confirmation buttons, the paused layer's buttons, the summary's buttons, and taps on a newly shown layer. "Settled" = the element exists, its frame is non-empty, overlaps the app window and is the same on two consecutive checks. It deliberately doesn't use `isHittable`: on GitHub CI (iOS 27) a fully visible, still Done button was never reported hittable ("Done never settled", run 40325692361), and locally scroll content and the review opened from the summary weren't either. (Since the first CI run, 2026-11-12, a settle timeout no longer fails the tap; see "First CI run with UI tests" at the end.)
- Typing: `ValueControl.type(_:deleting:)` types one character at a time and waits for the field to show it, so a lost keystroke fails at that character (no retyping, no retries).
- Verification: the user chose GitHub CI for the full suite (the Mac's load was 75–124 for hours, so local runs gave no usable result); locally only `build-for-testing`.

**Step 8 — CI and documentation**
- `.github/workflows/ci.yml`:
  - The Build step gets `id: build`; `build-for-testing` builds both test bundles as now.
  - The unit test step gets `-only-testing:WorkoutBuddyTests` and `-resultBundlePath UnitTests.xcresult`.
  - Before the UI tests: boot the created simulator and turn off the keyboard introduction (see "Fresh simulators").
  - A new **UI tests** step on the same simulator: `test-without-building -only-testing:WorkoutBuddyUITests -parallel-testing-enabled NO -resultBundlePath UITests.xcresult`; it runs even when the unit tests failed (`if: ${{ !cancelled() && steps.build.outcome == 'success' }}`), so both results show.
  - The upload step uploads both bundles on failure. `timeout-minutes: 45`.
- `CLAUDE.md` CI paragraph: the UI tests run in CI; the `.xcresult` bundles are uploaded on failure; CI still doesn't run iOS 18, so UI tests on iOS 18.2 stay a local check.
- **(main session)** Verify CI: needs a push, which is the user's call (the branch also carries phase 3). If the user agrees, push, watch the run and record the UI step's duration here.

## Hooks left for later phases
- **Phase 4:** UI-testing mode never requests notification permission (decided above), so the permission prompt can't block tests. Live Activity and notification content can't be checked by XCUITest in the app; keep them in unit tests and the manual check.
- **Phases 5–7:** add scenarios for saved history (several sessions on different days) and UI tests for the calendar, session detail, charts and export as those phases land. New flows get UI tests in the same step that builds them.
- **UI tidying session:** the label-based queries will need updating if button texts or spoken forms change; the contract file is the place to keep the shared ones.
- **UI tidying session — functional issue found by step 3b:** on iPhone 17 at the default text size, the centre of the set screen's reps + button sits about 8 pt inside the bottom action bar, and a tap there pressed Done (seen in XCUITest, not checked with a finger). The UI tests scroll the control up first. Listed in `phase-3-session.md`'s UI tidying hook too.
- **UI tidying session — found by step 6:** on iPhone 17 / iOS 27 the summary's Review Sets row starts below the visible area (it's visible on iOS 18.2), so the way into the review from the summary needs a scroll; at the newest set the review shows two buttons with the same label ("Back to Current Set" / "Back to Summary"), which VoiceOver reads twice and Voice Control can't tell apart; the large reps and kg controls start low on the screen (about y = 450–650 on iPhone 17), so they often need a scroll before − / +. In the review of a done set, the footer's Mark as Skipped starts below the screen on iPhone 17 at the default text size and sits under the bottom bar unless the review is scrolled almost to the end.

## Verification
- Each step: build; unit tests and UI tests green on iPhone 17 / iOS 27.0 and iPhone 16 / iOS 18.2 (with `-parallel-testing-enabled NO` there); Release build for steps that touch app code; `code-reviewer` reviews the step. Count tests and read per-test durations from the `.xcresult` (`xcrun xcresulttool get test-results summary` / `tests`), not the console log.
- Before a step with new UI tests is committed, run its test class with `-test-iterations 3 -run-tests-until-failure` on iOS 27, to catch flakiness early.
- At the end: the full UI suite twice on each OS version, and (if the user allows the push) one green CI run with its UI step duration recorded.
- `xcodebuild test` sometimes hangs in `simctl diagnose`; kill it and retry once.

## Review decisions
**Architect review (2026-10-25), verdict "Approve with changes", 14 findings, discussed with the user; all accepted:**
1. Tests would search for visible text, but XCUITest matches the spoken labels and values → tests check the spoken forms, listed in the Decisions and kept in the contract file.
2. Hidden screens under a review or the paused overlay stay in the element tree → container identifiers per layer; every query scoped to the top layer.
3. "Done", "End Workout" and "Discard Workout" are ambiguous; iOS 26 popovers may replace their source button → identifiers on those buttons; the dialog helper excludes the screen button's identifier; the keyboard's Done via `app.toolbars`.
4. The − / + buttons and the text field may not be reachable → probed first in step 3b; coordinate taps on the control as the fallback.
5. A 5 s rest would hide an idle-wait stall and is tight on CI → the probe runs on "Long Rests"; "Short Rests" rests are 10 s.
6. `setUp` can't launch the app under Swift 6 isolation → each test launches through the helper.
7. Value-less flags may swallow the locale pairs → region pairs first, flags take `YES`, one assertion proves the English format.
8. The store-file deletion is simulator-only → moved out of the `#if`; a device build check in step 2.
9. Step order and size → launch helper in step 2; step 3 split into 3a (scenarios) and 3b (identifiers, helpers, probes, first flow).
10. UI test target settings → listed explicitly in step 1.
11. CI: missing `id: build`; the keyboard introduction on a fresh simulator → both handled in step 8 and the launch helper.
12. CI time estimate optimistic; an untestable paused-swipe test; a redundant placeholder → 6–10 min estimate, test dropped, placeholder deleted in step 2, `-test-iterations 3` for the flakiness check.
13. Scenarios could silently seed the wrong state → `try`, a clear stop on failure, `skipRest` between actions, reused lookups and draft initialiser, state checked by unit tests.
14. Phase 4 notification prompt → UI-testing mode never requests notification permission.

**Step 2 code review (2026-10-25), verdict "Approve with fixes", 5 findings, discussed with the user** (plus the implementer's deviations, accepted: `AppSettings.store` is `nonisolated(unsafe)` because `UserDefaults` isn't `Sendable` in this SDK; the disk store is a separate `makeUITestingDiskStore(keepData:)`; OS differences handled in the test helpers — the reps stepper is tapped by coordinate, the search is ended before using the sheet's bar on iOS 26+, the iOS 18 search field is pulled into view, the back button is the bar's first button):
1. In UI-testing mode a failed suite would silently fall back to the user's settings → **accepted**: `.standard` only when not UI testing; a failed suite stops the app.
2. Sound/Haptics off and keep data were untested → **accepted**: the set-up is a testable function with unit tests.
3. `Scenario.init?(argument:)` only wrapped `init?(rawValue:)` → **accepted**: removed.
4. The disk-store test duplicated the delete helper → **accepted**: the helper is internal and reused; a comment says the test uses the UI tests' file on purpose.
5. UI tests took 30–100 s each on iOS 27 here, so ~28 tests could take ~20 minutes → **accepted**: the CI time estimate is updated; step 8 measures it and may split the UI tests into their own job.

**Step 3a code review (2026-10-25), verdict "Approve", 2 minor findings, discussed with the user; both accepted:**
1. The `onSummary` volume test summed reps × kg itself instead of using `SessionStats`, which the summary shows → **accepted**: checked through `SessionStats` (volume, done / skipped / not-performed counts).
2. The seeded timestamps were only loosely checked, and one test repeated two others → **accepted**: exact `startedAt` / `lastActionAt` / `endedAt` checks (later recovery and summary tests depend on them); the redundant test removed.

**Step 3b code review (2026-10-25), verdict "Approve with fixes", 5 findings, discussed with the user** (plus the implementer's deviations, accepted: the inner − / + buttons are reachable and found by their system labels "Remove" / "Add" (inner identifiers were unreliable); the value helper scrolls the control clear of the bottom bar before tapping; on iOS 26+ the confirmation has no Cancel button, so the helper taps the popover's dismiss region; after Save the cover closes onto the template detail, so the flow test goes back before checking "Last done"):
1. [Major] The review layer's container identifier moved its `.isModal` trait (and `.accessibilityHidden`) from the children onto the container → **accepted**: the identifier is the outermost modifier, so VoiceOver gets exactly what it got before.
2. The 3 s idle-probe limit was too tight for CI → **accepted**: 10 s.
3. The value helper could tap while the control was still under the bottom bar → **accepted**: it asserts the control is clear first.
4. The dialog-cancel helper didn't check the dialog closed, and waited 2 s on iOS 26+ → **accepted**: it asserts the dialog is gone and doesn't wait for a Cancel that doesn't exist. Proved by a new test, `SessionFlowUITests.testCancelConfirmationKeepsWorkoutPaused`, kept so the iOS 26+ popover path stays covered.
5. The reps + button overlaps the bottom bar on iPhone 17 → **user's decision**: noted for the UI tidying session (Hooks above, and `phase-3-session.md`).

**Step 4 code review (2026-10-25), verdict "Approve with fixes", 4 minor findings, discussed with the user; all accepted** (plus the implementer's merges, accepted: the step 4 cases are three tests — adjusted and typed values proved by the summary volume, 1,467.5 kg; Skip Set with set-screen Pause/Resume; the rest screen's Up next, Pause/Resume, Undo and Skip Rest — to save launches of 30–40 s each):
1. Undo only proved the reps came back → the kg is changed too and checked after Undo.
2. Repeated summary-volume lookup and pause/resume code → shared helpers in `Support/Screens.swift`; the identifier aliases removed.
3. The Up next check was a prefix match → the exact spoken value, kept in the contract file.
4. The keyboard-introduction check waited and collected debug information on every run → checked without a failing wait, after a (succeeding) wait for the keyboard: without that wait one iOS 18.2 run typed "57" instead of "57.5" (a lost keystroke while the keyboard settled); watch for it in later runs. The adjusted-values test takes about 75–95 s on iOS 27 here; step 8 uses this for the CI timing.

**Step 5 code review (2026-10-26, night), verdict "Approve with fixes", 7 minor findings. The user was asleep and had asked the main session to carry on with steps 5–8, so the main session settled them; all accepted** (plus the implementer's merge, accepted: "Back to Workout after an early end" is part of the early-end test, which ends, goes back, ends again and saves):
1. Back to Workout after the last set didn't prove the set came back with its entered values → the kg is changed before the last Done and checked after Back to Workout; the final volume (1,440 kg) proves nothing was counted twice.
2. "Nothing saved" was checked as a missing substring → the row's value is checked to contain "Not done yet".
3. "The cover closed" was checked differently in each test → one `assertNoSessionLayer()` helper, used after every Save and Discard.
4. Copied Pause → End Workout and "back to the list, read the row" sequences → shared helpers.
5. The nothing-done discard excluded an identifier that isn't on screen → it excludes the real source button (`pausedEndWorkout`).
6. The last-set loop didn't check where each Skip Rest landed → `assertSetScreen` before each Done.
7. The all-skipped discard didn't check the confirmation title → it waits for "Discard Workout?" first.

**Step 6 code review (2026-10-26, night), verdict "Approve with fixes", 5 findings, settled by the main session (the user was asleep and had asked it to carry on)** (plus the implementer's deviations, accepted: `ValueControl.reveal()` rewritten to drag only the remaining distance, because the fixed drag overshot when the control sat lower; skipped sets don't make the title "Workout Ended" (only not-performed sets or a can't-save workout do), so the Mark-as-Skipped test expects "Workout Complete"; the summary is scrolled to reach Review Sets and dragged back to see the title; merges: swipes and buttons in one launch, the kg correction and Mark as Done proved by one summary):
1. [Major] On iOS 27 some review taps only succeeded through XCUITest's internal retry (a tap during the slide-in; Mark as Skipped "not hittable" in the review opened from the summary) → **accepted**: taps wait until the button is hittable, the slide-in is awaited; the summary case was diagnosed on iOS 27: in a review opened from the summary XCUITest reports every button not hittable for 10 s+ although nothing covers it, real (coordinate) taps work, and the covered summary is already hidden from accessibility (`ActiveSessionView`, `.accessibilityHidden(paused || reviewing)`), so it's an XCUITest quirk, not an app bug; the review tests fall back to a coordinate tap there, with a comment. No app change.
2. On iOS 27 the summary's Review Sets row starts below the screen → **accepted**: the test keeps its scroll and asserts the row is reachable; logged for the UI tidying session (Hooks).
3. At the newest set the review has two buttons labelled "Back to Current Set" ("Back to Summary") → **no change**; logged for the UI tidying session (VoiceOver reads it twice; Voice Control needs a number).
4. The index taps on those two buttons are robust but the comments overstated it → **accepted**: comments reworded.
5. "No Pause" in the review from the summary was only checked one way → **accepted**: the live review asserts Pause is there.

**Step 7 code review (2026-10-26, night), verdict "Approve with fixes", 5 findings, settled by the main session; all accepted:**
1. [Major] One iOS 18.2 run of the Resume kill test failed: on the first launch a Done tap right after Start reached the app but did nothing → Done is tapped only once hittable, and the failure was chased with 5-iteration runs on iOS 18.2. It didn't reproduce, but the same kind of lost tap hit the recovery alert's Resume ~1.7 s after the alert appeared: a tap during a presentation animation on the loaded Mac, not an app bug (it also happened with the in-memory store). A new `waitUntilSettled()` (exists, hittable, same frame twice) now guards the taps right after a presentation in the recovery tests; 5 iterations on 18.2 then passed. The remaining rare flakes (the lost ".5" keystroke on 18.2, about 2 in 7 runs; one lost confirmation tap on iOS 27) are handled in a hardening step before CI (step 7b).
2. [Major] The countdown check would pass if Resume restarted the rest → it checks the remaining time against the time since Done and waits for the countdown to change.
3. "No session layer before the alert" had no positive control → it also checks the list behind the alert is in the tree.
4. Re-seeding on relaunch wasn't detected and Save after a kill wasn't checked → the End Workout kill test saves and checks there's exactly one "Long Rests" row showing "Last done".
5. A copied row check → `assertRow(_:valueContains:)` split out of `assertRowAfterSession`; the alert's close is awaited.

**Step 7b code review (2026-11-12), verdict "Approve with fixes", 4 major and 5 minor findings, discussed with the user; 1–7 and 9 accepted, 8 in part:**
1. [Major] The settle was inside the timed window of `testRestScreenRespondsQuickly` → the clock starts after the settle, right before the tap.
2. [Major] The summary's Review Sets row was still found with `isHittable`, and a row partly under the bottom bar could pass the settle → scrolled until its bottom is above Save, asserted, then `tapSettled()`.
3. [Major] The review helper still waited 2 s for `isHittable` (always false on iOS 27, a hidden delay) and didn't settle after scrolling → renamed `tapReviewElement`: settles after the scroll, then always taps by coordinate; callers check the result.
4. [Major] `TemplateEditorUITests` wasn't hardened → `tapSettled()` for the first taps after a sheet, push, pop or dismiss; per-character typing moved into `XCUIElement.typeSlowly(_:)`, used by `ValueControl.type` and for the name and search fields.
5. `dismissSearch` relied on `isHittable` and could silently do nothing → waits for the button to settle and fails if neither button was tapped.
6. The settle read the first window's frame → uses the app's frame (screen bounds).
7. The settle's doc comment → says the expectation polls about once a second, which is what covers fades, and each settle costs about 1 s.
8. Redundant settles → only the confirmation's Cancel tap after an already settled confirm becomes a plain tap; the settles before Done on a screen already showing stay (about 1 s each, cheap insurance on CI).
9. The value predicate was built by string interpolation → `NSPredicate(format: "value == %@", …)`.

**Step 8 code review (2026-11-12), verdict "Approve with fixes", 2 minor findings and 1 question, discussed with the user; all settled as recommended:**
1. The Boot simulator step ran before the unit tests (which run on clones) and was skipped when the Release build failed, while the UI tests still ran → moved directly before the UI tests, with the UI step's condition (`!cancelled() && steps.build.outcome == 'success'`).
2. Nothing confirms the `DidShowContinuousPathIntroduction` setting suppresses the keyboard introduction on iOS 27 → kept as the first line of defence; the launch helper still dismisses the introduction. Checked after the first CI run.
3. A Release-only failure skipped the unit tests but ran the UI tests → the unit test step gets the same condition, so both results always show.

**First CI run with UI tests (run 43176303956, 2026-11-12, iOS 27.2):** unit tests green; UI tests 21 of 22 passed. The UI step took about 19.5 min (job about 24 min, well inside the 45 min timeout); the template editor's per-character search typing and the keyboard-introduction step caused no failures. The failure: `RecoveryUITests/testEndWorkoutFromAlertShowsSummaryAndSave` — "Save never settled", although both debug snapshots show Save on screen with the same frame; on the runner one settle poll read the frame (about 1 s), the next one stalled or returned no frame, and a snapshot request then took about 10 s, so two matching frame reads didn't fit in the 10 s settle. Decided with the user: `tapSettled()` no longer fails on a settle timeout; it taps when the element still exists on screen and fails only if it's missing (the settle only guards against tapping during an animation, none lasts 10 s, and every caller checks the tap's effect).

**Review of the tapSettled fix (2026-11-12), verdict "Approve with fixes", 1 major and 4 minor findings, discussed with the user; all accepted:**
1. [Major] The screen frame was read inside the settle predicate, costing about 1–1.5 s per poll on CI → read once before the wait and passed to the fallback.
2. A single-read fallback could hit the same stall → the fallback is a presence wait (up to 3 s) that ends at the first read finding the element on screen.
3. Inaccurate doc comment ("one snapshot read") → corrected.
4. An ambiguous query also reads as "missing or off screen" → the messages say "missing, off screen or ambiguous".
5. The strict `waitUntilSettled` was still callable and the step 7b text read as a hard requirement → `waitUntilSettled` is private; step 7b points to this decision.

**CI verified (run 43183858778, 2026-11-12, commit a5ff93c, iOS 27.2):** green. Unit tests about 2 min; UI tests 22 of 22 passed in 19 min 40 s; the job about 24 min (timeout 45). Whether the keyboard-introduction setting itself takes effect on iOS 27 isn't confirmed; the launch helper's dismissal stays the safeguard. The UI test work is done; phase 4 starts in its own session.

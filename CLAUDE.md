# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project
WorkoutBuddy is an iPhone-only SwiftUI app: minimum iOS 18, SwiftData, local-only (no sync), English UI, weights in kg. `FEATURES.md` is the product spec. It defines features F1–F9, the data model (§4), what's out of scope (§5), defaults chosen for open points (§6) and the implementation phases (§7). Work is planned and built phase by phase from it.

## Build and test
Scheme `WorkoutBuddy`, project `WorkoutBuddy.xcodeproj`. There is no linter configured.

```sh
# Build
xcodebuild build -project WorkoutBuddy.xcodeproj -scheme WorkoutBuddy -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -quiet

# Run all unit tests
xcodebuild test -project WorkoutBuddy.xcodeproj -scheme WorkoutBuddy -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -quiet

# Run one suite or one test
xcodebuild test -project WorkoutBuddy.xcodeproj -scheme WorkoutBuddy -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -quiet -only-testing:WorkoutBuddyTests/<SuiteName>/<testName()>
```

To check behaviour on the minimum OS, use `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'`.

**CI:** `.github/workflows/ci.yml` builds the app and runs all unit tests on every pull request and every push to `main`. It runs on GitHub's `xcode-27` runner, using iPhone 17 on the latest iOS simulator. CI doesn't test on iOS 18, so the minimum-OS check above is still done locally. If a test fails, the `.xcresult` bundle is uploaded as a run artifact.

## Project setup
- Targets: `WorkoutBuddy` (app, `net.poukar.WorkoutBuddy`) and `WorkoutBuddyTests` (unit tests, hosted in the app). A widget extension for the Live Activity comes in phase 4.
- `WorkoutBuddy/` and `WorkoutBuddyTests/` are **synchronized folders**: any file added under them joins the target automatically. Don't edit `project.pbxproj` to add files.
- Both targets use Swift 6 language mode with **default actor isolation set to `MainActor`** and Approachable Concurrency. Types and functions are `@MainActor` unless marked `nonisolated`; mark pure logic `nonisolated` when it must run off the main actor.
- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`). SwiftData tests use an in-memory `ModelContainer`.
- Portrait only. Any API newer than iOS 18 needs `if #available` with an iOS 18 fallback.

## Rules that span the whole app
These come from `FEATURES.md` and affect most features, so keep them in mind even when a change looks local:
- **Soft delete:** exercises are archived and workouts are soft-deleted, never removed, so history and charts keep working. Pickers and lists hide archived or deleted records, but **lookups by ID must not filter them out**.
- **Names are never copied** into sessions. They're always looked up through references.
- **Sessions copy the planned numbers** (reps, kg, rest), because templates can change later.
- **Name uniqueness** is case-insensitive and applies only among active records.
- **Timers** are calculated from stored timestamps, not by counting ticks. Session progress is saved after every action, so a killed app can resume.
- SwiftData relationships are unordered, so ordered children (exercises in a workout, sets in an exercise) need an explicit order field.

## Workflow: plan → review → implement → review
Features are built with three project subagents in `.claude/agents/`. Follow this flow:

1. **Plan.** The main session writes the implementation plan for a phase (see `FEATURES.md` §7) to `docs/plans/phase-<N>-<short-name>.md`, for example `docs/plans/phase-1-foundation.md`. The plan is split into numbered steps small enough for one subagent run each.
2. **Plan review.** Send the plan file path to the `architect-reviewer` agent. It checks the plan against `FEATURES.md`, the existing code (soundness and reuse) and current Apple Human Interface Guidelines. It returns numbered findings. **Present the findings to the user and discuss them. Update the plan only after you've agreed on changes; never fix it silently.** Commit the plan once it's agreed.
3. **Implement, one step at a time.** For each plan step, run the `implementer` agent (Sonnet) once, passing the plan file path and the step number. It writes the code and unit tests, then runs the build and tests. It doesn't change Xcode project settings, the plan, or git. Anything it lists under **"Needs main session"** (targets, capabilities, entitlements, Info.plist keys, packages, problems with the plan) is handled here in the main session, with the user where it needs a decision.
4. **Code review.** After each step, run the `code-reviewer` agent with the plan, the step and the implementer's report. It checks the actual changes (using `git diff`) against the plan, the spec and the project rules, and reruns the build and tests. **Present its findings to the user and discuss them before fixing anything.** Apply the agreed fixes before starting the next step.
5. **Commit the step.** Once the review is settled and the build and tests pass, the main session commits the step, with a message like `Phase 1, step 2: <what the step did>`. Every step gets its own commit, so the next code review's diff contains only that step. Subagents never commit.

If the plan changes while it's being implemented (for example after a "Needs main session" report or a review finding), update the plan file and commit it together with the step that caused the change.

Project setup work (creating targets, capabilities, signing, packages) is always done in the main session, never by a subagent.

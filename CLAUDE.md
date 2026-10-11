# WorkoutBuddy

iPhone-only SwiftUI app: minimum iOS 18, SwiftData, local-only, English UI, kg. The product spec is `FEATURES.md`.

## Build and test
Scheme `WorkoutBuddy`, project `WorkoutBuddy.xcodeproj`.

```sh
# Build
xcodebuild build -project WorkoutBuddy.xcodeproj -scheme WorkoutBuddy -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -quiet

# Run all unit tests
xcodebuild test -project WorkoutBuddy.xcodeproj -scheme WorkoutBuddy -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' -quiet

# Run one suite or test
xcodebuild test ... -only-testing:WorkoutBuddyTests/<SuiteName>[/<testName()>]
```

To check behaviour on the minimum OS, use `-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.2'`.

## Project setup
- Targets: `WorkoutBuddy` (app, `net.poukar.WorkoutBuddy`) and `WorkoutBuddyTests` (unit tests, hosted in the app).
- The `WorkoutBuddy/` and `WorkoutBuddyTests/` folders are **synchronized folders**: any file added under them is part of the target automatically. Don't edit `project.pbxproj` to add files.
- Swift 6 language mode, with **default actor isolation set to `MainActor`** and Approachable Concurrency, in both targets. Types and functions are `@MainActor` unless marked `nonisolated`; mark pure logic `nonisolated` when it needs to run off the main actor.
- Unit tests use Swift Testing (`import Testing`, `@Test`, `#expect`). SwiftData tests use an in-memory `ModelContainer`.
- Portrait only.

## Workflow
Each implementation plan is reviewed by the `architect-reviewer` agent, then implemented one step at a time by the `implementer` agent, and each step is checked by the `code-reviewer` agent. Findings from both reviewers are discussed with the user before the plan or the code is changed. Targets, capabilities, entitlements, Info.plist keys and packages are configured in the main session, not by subagents.

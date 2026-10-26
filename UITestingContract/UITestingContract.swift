/// Names shared by the app and the UI tests. This folder is a member of both targets, because the UI tests
/// can't import the app module; a typo then fails to compile instead of failing a test at runtime.
///
/// Foundation reads launch arguments as `-key value` pairs, so every option here takes an explicit value
/// (`-uiTesting YES`): a flag without one could swallow the next pair, such as the region overrides.
nonisolated enum UITestingContract {
    nonisolated enum Argument {
        /// Switches the app into UI-testing mode. Only the value `YES` counts.
        static let uiTesting = "-uiTesting"
        /// The seeded scenario, one of `Scenario`.
        static let scenario = "-uiTestingScenario"
        /// Where the data lives, one of `Store`.
        static let store = "-uiTestingStore"
        /// `YES` keeps the disk store and the settings suite from the previous launch.
        static let keepData = "-uiTestingKeepData"
        /// The value that switches a flag on.
        static let yes = "YES"
    }

    nonisolated enum Scenario {
        /// The exercise seed only. The default.
        static let empty = "empty"
        /// The two templates "Short Rests" and "Long Rests".
        static let templates = "templates"
        /// The templates and a running "Long Rests" session: first set done, second skipped.
        static let inProgress = "inProgress"
        /// The templates and a running "Long Rests" session with only the first set skipped.
        static let nothingDone = "nothingDone"
        /// The templates and a finished "Long Rests" session with all sets done, waiting for Save.
        static let onSummary = "onSummary"
    }

    /// The seeded templates (every scenario except `empty`).
    nonisolated enum Workout {
        /// Rests of 10 s, 0 s and 10 s: the rest screen ends by itself.
        static let shortRests = "Short Rests"
        /// Rests of 600 s: all the time a test needs on the rest screen.
        static let longRests = "Long Rests"
    }

    nonisolated enum Store {
        /// A fresh in-memory store. The default.
        static let memory = "memory"
        /// A separate store file that survives the process, for kill-and-relaunch tests.
        static let disk = "disk"
    }

    /// Accessibility identifiers. The layer ones are container identifiers (`.accessibilityElement(children:
    /// .contain)`), so a test can tell which layer is on top: during a review and under the paused overlay the
    /// screen underneath stays in XCUITest's element tree. The others sit on leaf elements whose label is
    /// ambiguous or whose parts aren't reachable.
    nonisolated enum Identifier {
        static let setScreen = "session.setScreen"
        static let restScreen = "session.restScreen"
        static let review = "session.review"
        static let paused = "session.paused"
        static let summary = "session.summary"
        /// The set screen's Done ("Done" is also the keyboard's, the review badge's and the editor's).
        static let setDone = "session.setScreen.done"
        /// The paused overlay's End Workout (the confirmation has a button with the same label).
        static let pausedEndWorkout = "session.paused.endWorkout"
        /// The summary's Discard Workout (the confirmation has a button with the same label).
        static let summaryDiscardWorkout = "session.summary.discardWorkout"
        /// The large reps and kg controls, one adjustable element each (on the set screen and the review).
        static let repsControl = "session.reps"
        static let kgControl = "session.kg"
    }

    /// The spoken forms XCUITest sees as labels and values (it matches what VoiceOver gets, not the visible text).
    nonisolated enum Spoken {
        static func position(exercise: Int, of exercises: Int, set: Int, of sets: Int) -> String {
            "Exercise \(exercise) of \(exercises), set \(set) of \(sets)"
        }
        static let volumeLabel = "Volume"
        /// The summary volume of the `templates` workouts when every set is done as planned.
        static let plannedVolume = "1,420 kilograms"
        /// The summary count line, "3 sets completed" or "1 set completed".
        static func setsCompleted(_ count: Int) -> String { "\(count) \(count == 1 ? "set" : "sets") completed" }
        /// The summary count line for sets never done or skipped, "2 sets not performed".
        static func setsNotPerformed(_ count: Int) -> String { "\(count) \(count == 1 ? "set" : "sets") not performed" }
        static let upNextLabel = "Up next"
        /// The "Up next" value on the rest screen after the first "Long Rests" set: the plan of Bench Press set 2.
        static let longRestsUpNextSet2 = "Bench Press, set 2, 8 reps at 62.5 kilograms"
        static let repsLabel = "Reps"
        static let weightLabel = "Weight"
        static let workoutComplete = "Workout Complete"
        static let workoutEnded = "Workout Ended"
        static let backToWorkout = "Back to Workout"
        /// The summary note when no set was done (the workout can't be saved).
        static let cannotSaveNote = "No sets were completed, so this workout can't be saved."
        /// The confirmation titles for ending a workout with done sets, and for discarding one with none.
        static let endConfirmationTitle = "End Workout?"
        static let discardConfirmationTitle = "Discard Workout?"
        /// The Workouts list row's value contains this once the workout has been done.
        static let lastDone = "Last done"
        /// The Workouts list row's value for a workout that was never done.
        static let notDoneYet = "Not done yet"
        /// The summary volume of the `templates` workouts when the last set's kg is raised by one step (40 to 42.5).
        static let plannedVolumeWithLastSetRaised = "1,440 kilograms"
    }

    /// The `UserDefaults` suite the app reads its settings from in UI-testing mode.
    static let settingsSuiteName = "net.poukar.WorkoutBuddy.uiTesting"
}

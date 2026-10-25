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

    /// The `UserDefaults` suite the app reads its settings from in UI-testing mode.
    static let settingsSuiteName = "net.poukar.WorkoutBuddy.uiTesting"
}

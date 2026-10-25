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

/// Names shared by the app and the UI tests. This folder is a member of both targets, because the UI tests
/// can't import the app module; a typo then fails to compile instead of failing a test at runtime.
nonisolated enum UITestingContract {
    nonisolated enum Argument {
        /// Switches the app into UI-testing mode. Takes a value (`-uiTesting YES`): Foundation reads launch
        /// arguments as `-key value` pairs, and a flag without one could swallow the next pair.
        static let uiTesting = "-uiTesting"
    }
}

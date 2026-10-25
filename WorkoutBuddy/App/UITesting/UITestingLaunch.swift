import Foundation

/// The options of the UI-testing launch mode, read from the launch arguments. The mode is switched on only by
/// `-uiTesting YES`, which only the UI tests pass; without it nothing in the app changes.
/// Compiled in every configuration (no `#if DEBUG`), like the preview data: a Debug-only helper broke the
/// Release build before.
nonisolated struct UITestingLaunch: Equatable, Sendable {
    enum Scenario: String, Sendable {
        case empty
    }

    enum Store: String, Sendable {
        case memory
        case disk
    }

    var scenario: Scenario = .empty
    var store: Store = .memory
    /// Keeps the disk store and the settings suite from the previous launch, and seeds no scenario.
    var keepData = false

    /// The mode of this process, or `nil` for a normal launch (and in the unit-test host).
    static let current: UITestingLaunch? = parse(ProcessInfo.processInfo.arguments)

    /// `nil` without `-uiTesting YES`. An unknown scenario or store name is a programming error in a test and
    /// stops the app with a clear message.
    static func parse(_ arguments: [String]) -> UITestingLaunch? {
        guard value(of: UITestingContract.Argument.uiTesting, in: arguments) == UITestingContract.Argument.yes else {
            return nil
        }
        var launch = UITestingLaunch()
        if let name = value(of: UITestingContract.Argument.scenario, in: arguments) {
            guard let scenario = Scenario(rawValue: name) else {
                fatalError("Unknown UI-testing scenario '\(name)'")
            }
            launch.scenario = scenario
        }
        if let name = value(of: UITestingContract.Argument.store, in: arguments) {
            guard let store = Store(rawValue: name) else {
                fatalError("Unknown UI-testing store '\(name)', expected memory or disk")
            }
            launch.store = store
        }
        launch.keepData = value(of: UITestingContract.Argument.keepData, in: arguments) == UITestingContract.Argument.yes
        return launch
    }

    /// The argument right after `key`, if there is one.
    private static func value(of key: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: key), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

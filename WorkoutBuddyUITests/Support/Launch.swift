import XCTest

/// Launches the app in UI-testing mode and returns it. The region pairs come first: Foundation reads launch
/// arguments as `-key value` pairs, and they make number texts predictable ("62.5", "1,420 kilograms") on
/// the Czech-region simulators here and on CI alike. Every flag takes an explicit value.
@MainActor
func launch(
    scenario: String = UITestingContract.Scenario.empty,
    store: String = UITestingContract.Store.memory,
    keepData: Bool = false
) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    arguments += [UITestingContract.Argument.uiTesting, UITestingContract.Argument.yes]
    arguments += [UITestingContract.Argument.scenario, scenario]
    arguments += [UITestingContract.Argument.store, store]
    if keepData { arguments += [UITestingContract.Argument.keepData, UITestingContract.Argument.yes] }
    app.launchArguments = arguments
    app.launch()
    return app
}

extension XCUIApplication {
    /// The "Speed up your typing" introduction on a fresh simulator can cover the keyboard. Best effort: tap
    /// its Continue button if it shows up within a moment, do nothing otherwise.
    func dismissKeyboardIntroductionIfPresent() {
        let continueButton = keyboards.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 1) { continueButton.tap() }
    }
}

extension XCUIApplication {
    /// Ends a focused search, which hides the navigation bar on iOS 26+ (its button is "close" there, "Cancel" before).
    func dismissSearch() {
        for name in ["close", "Cancel"] {
            let button = buttons[name]
            if button.exists, button.isHittable {
                button.tap()
                return
            }
        }
    }
}

extension XCUIElement {
    /// Taps the + half of a `RepsStepper` row. The row is one combined accessibility element (adjustable, with
    /// no reachable buttons), so the tap is a coordinate tap on the system stepper inside it.
    func incrementRepsStepper() {
        steppers.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
    }
}

extension XCUIApplication {
    /// Taps the back button of the pushed screen with this navigation title. The back button is the bar's first
    /// button on every OS version (its identifier and label differ: "BackButton" on iOS 26+, the previous title before).
    func goBack(from title: String) {
        navigationBars[title].buttons.element(boundBy: 0).tap()
    }
}

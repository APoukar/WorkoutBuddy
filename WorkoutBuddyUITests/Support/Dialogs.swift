import XCTest

extension XCUIApplication {
    /// Taps the confirmation's button with this label. The same label is also on the screen button that opened
    /// the question (End Workout, Discard Workout), so the screen button's identifier is excluded. That works
    /// whether the source button is still in the tree (iOS 18 action sheet) or replaced (iOS 26 popover).
    func tapConfirmationButton(_ label: String, excluding screenButtonIdentifier: String) {
        let button = buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", label, screenButtonIdentifier)
        ).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: defaultTimeout), "no confirmation button \(label)")
        button.tapSettled()
    }

    /// Dismisses the open confirmation and waits until its button (`label`, not the screen button
    /// `screenButtonIdentifier`) is gone. The iOS 18 action sheet has a Cancel button; the iOS 26+ popover has
    /// none (tapping outside it cancels), so the system's dismiss region is tapped in the right margin beside
    /// the popover (the left edge is the system's back-swipe zone, and the popover covers most of the rest).
    func cancelConfirmation(label: String, excluding screenButtonIdentifier: String) {
        let confirm = buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", label, screenButtonIdentifier)
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: defaultTimeout), "no confirmation open")
        XCTAssertTrue(confirm.waitUntilSettledOrPresent(), "the confirmation is missing, off screen or ambiguous")
        let cancel = buttons["Cancel"]
        let dismiss = otherElements["PopoverDismissRegion"]
        if cancel.exists {
            cancel.tap()
        } else if dismiss.exists {
            dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        } else {
            XCTFail("no Cancel and no popover dismiss region")
        }
        XCTAssertTrue(confirm.waitForNonExistence(), "the confirmation didn't close")
    }
}

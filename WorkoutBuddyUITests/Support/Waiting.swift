import XCTest

/// The default wait for something to appear.
let defaultTimeout: TimeInterval = 10

extension XCUIElement {
    /// Waits until the element no longer exists. Never sleeps.
    @discardableResult
    func waitForNonExistence(timeout: TimeInterval = defaultTimeout) -> Bool {
        waitUntil("exists == false", timeout: timeout)
    }

    /// Waits until the element's `isEnabled` equals `enabled`.
    @discardableResult
    func waitUntilEnabled(_ enabled: Bool, timeout: TimeInterval = defaultTimeout) -> Bool {
        waitUntil("isEnabled == \(enabled ? "true" : "false")", timeout: timeout)
    }

    /// Waits until the predicate format holds for the element.
    @discardableResult
    func waitUntil(_ format: String, timeout: TimeInterval = defaultTimeout) -> Bool {
        waitUntil(NSPredicate(format: format), timeout: timeout)
    }

    /// Waits until the predicate holds for the element.
    @discardableResult
    func waitUntil(_ predicate: NSPredicate, timeout: TimeInterval = defaultTimeout) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Types `text` one character at a time and, after each, waits for the element's value to equal everything
    /// typed so far, so a keystroke lost while the keyboard settles fails here, at the character. For a field
    /// that was empty before.
    func typeSlowly(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        var typed = ""
        for character in text {
            typeText(String(character))
            typed.append(character)
            XCTAssertTrue(
                waitUntil(NSPredicate(format: "value == %@", typed)),
                "after typing '\(typed)' the field shows \(String(describing: value))", file: file, line: line)
        }
    }
}

extension XCUIElement {
    /// Waits until the element exists, has a non-empty frame that overlaps the screen, and has the same frame
    /// as at the previous check, so a tap doesn't land while an alert, cover or slide-in is still animating.
    /// The expectation polls about once a second, so "unchanged between two checks" means the same frame
    /// about 1 s apart; that gap covers fades and alert scale-ins, and each settle costs about 1 s. Not
    /// `isHittable` (false for tappable scroll content, and never true on CI for a visible button). A partly
    /// visible frame is accepted: scroll content below the fold is scrolled into view by `tap()`.
    @discardableResult
    func waitUntilSettled(timeout: TimeInterval = defaultTimeout) -> Bool {
        let window = XCUIApplication().frame
        var lastFrame: CGRect?
        let predicate = NSPredicate { evaluated, _ in
            MainActor.assumeIsolated {
                guard let element = evaluated as? XCUIElement,
                      let frame = try? element.snapshot().frame,
                      !frame.isEmpty, frame.intersects(window) else {
                    lastFrame = nil
                    return false
                }
                defer { lastFrame = frame }
                return lastFrame == frame
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension XCUIElement {
    /// Waits until the element has settled (see `waitUntilSettled`), fails the test if it never does, and taps it.
    /// Use for the first tap after a screen, alert or confirmation appeared.
    func tapSettled(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            waitUntilSettled(),
            "\(self) never settled (exists, non-empty frame in the app window, unchanged between two checks) before the tap",
            file: file, line: line)
        tap()
    }
}

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
    /// The element's frame if it exists with a non-empty frame that overlaps `screen`, else nil (one snapshot
    /// read; a missing or ambiguous query makes `snapshot()` throw). A partly visible frame counts: scroll
    /// content below the fold is scrolled into view by `tap()`.
    private func frameOnScreen(_ screen: CGRect) -> CGRect? {
        guard let frame = try? snapshot().frame, !frame.isEmpty, frame.intersects(screen) else { return nil }
        return frame
    }

    /// Waits until the element exists, has a non-empty frame that overlaps the screen, and has the same frame
    /// as at the previous check, so a tap doesn't land while an alert, cover or slide-in is still animating.
    /// The screen frame is read once, before the wait (on CI that read costs 1-1.5 s, too slow to repeat per
    /// poll). The expectation polls about once a second, so "unchanged between two checks" means the same
    /// frame about 1 s apart; that gap covers fades and alert scale-ins, and each settle costs about 1 s. Not
    /// `isHittable` (false for tappable scroll content, and never true on CI for a visible button).
    /// Returns false on timeout. On CI a snapshot can take several seconds, so two matching reads may not fit
    /// in the timeout even though the element is stable; callers use `waitUntilSettledOrPresent` or
    /// `tapSettled`, which tolerate that.
    private func waitUntilSettled(screen: CGRect, timeout: TimeInterval) -> Bool {
        var lastFrame: CGRect?
        let predicate = NSPredicate { evaluated, _ in
            MainActor.assumeIsolated {
                guard let frame = (evaluated as? XCUIElement)?.frameOnScreen(screen) else {
                    lastFrame = nil
                    return false
                }
                defer { lastFrame = frame }
                return lastFrame == frame
            }
        }
        return waitUntil(predicate, timeout: timeout)
    }

    /// Waits for the element to settle (see `waitUntilSettled`); if that times out, waits up to 3 s (or
    /// `timeout` if shorter, so a short caller timeout stays short) for a single read to find the element
    /// present on screen, using the same screen frame as the settle wait. Returns whether the element is
    /// present on screen afterwards (settled or not).
    func waitUntilSettledOrPresent(timeout: TimeInterval = defaultTimeout) -> Bool {
        let screen = XCUIApplication().frame
        if waitUntilSettled(screen: screen, timeout: timeout) { return true }
        let present = NSPredicate { evaluated, _ in
            MainActor.assumeIsolated { (evaluated as? XCUIElement)?.frameOnScreen(screen) != nil }
        }
        return waitUntil(present, timeout: min(3, timeout))
    }
}

extension XCUIElement {
    /// Waits for the element to settle (see `waitUntilSettledOrPresent`) and taps it. If the settle times out
    /// the tap still happens as long as the element is present on screen; it fails (without tapping) only
    /// when the element is missing, off screen or ambiguous (an ambiguous query makes `snapshot()` throw).
    /// The settle only guards against tapping during an animation and none lasts 10 s; on CI snapshots can be
    /// so slow that two matching reads don't fit in the timeout; callers check the effect of every tap. Use
    /// for the first tap after a screen, alert or confirmation appeared.
    func tapSettled(file: StaticString = #filePath, line: UInt = #line) {
        guard waitUntilSettledOrPresent() else {
            XCTFail("\(self) is missing, off screen or ambiguous (no non-empty frame in the app window) before the tap",
                    file: file, line: line)
            return
        }
        tap()
    }
}

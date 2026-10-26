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
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

extension XCUIElement {
    /// Waits until the element exists, is hittable and keeps the same frame between two consecutive checks, so
    /// a tap doesn't land while an alert or a full-screen cover is still animating in (on iOS 18.2 such taps
    /// reached the app and did nothing). Polls through an expectation; never sleeps.
    @discardableResult
    func waitUntilSettled(timeout: TimeInterval = defaultTimeout) -> Bool {
        var lastFrame: CGRect?
        let predicate = NSPredicate { evaluated, _ in
            MainActor.assumeIsolated {
                guard let element = evaluated as? XCUIElement, element.exists, element.isHittable else {
                    lastFrame = nil
                    return false
                }
                defer { lastFrame = element.frame }
                return lastFrame == element.frame
            }
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}

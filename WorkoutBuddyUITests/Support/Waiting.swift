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

import XCTest

extension XCUIApplication {
    /// A real touch drag, away from the screen edges (where the system gestures are) and on the scrolling
    /// content. `.fast` is what the app's `UISwipeGestureRecognizer`s respond to. A swipe right opens the
    /// review of the previous set; a swipe left goes forward.
    func swipeHorizontally(right: Bool) {
        let start = coordinate(withNormalizedOffset: CGVector(dx: right ? 0.25 : 0.75, dy: 0.35))
        let end = coordinate(withNormalizedOffset: CGVector(dx: right ? 0.85 : 0.15, dy: 0.35))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }
}

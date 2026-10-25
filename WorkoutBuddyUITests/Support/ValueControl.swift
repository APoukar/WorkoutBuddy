import XCTest

/// One of the large reps / kg controls: one adjustable element whose − / + buttons and text field are
/// children XCUITest can reach (the probe in step 3b found them, although VoiceOver can't). The buttons are
/// found by the system labels of the minus and plus symbols, "Remove" and "Add" (the symbol-name identifiers
/// come and go). The value is always read from the control's `value`. The set screen scrolls and its bottom bar covers the lower
/// part of the content, so the control is scrolled to the top first, or the tap would land on Done.
@MainActor
struct ValueControl {
    let control: XCUIElement
    let scrollView: XCUIElement

    init(identifier: String, in layer: XCUIElement) {
        control = layer.descendants(matching: .any)[identifier]
        scrollView = layer.scrollViews.firstMatch
    }

    var value: String { control.value as? String ?? "" }
    var field: XCUIElement { control.textFields.firstMatch }

    func increment() { tapButton("Add") }
    func decrement() { tapButton("Remove") }

    /// Taps the value and types into it. The caller ends the editing (the keyboard's Done bar).
    func focusField() {
        reveal()
        field.tap()
    }

    private func tapButton(_ label: String) {
        reveal()
        control.buttons[label].tap()
    }

    /// Scrolls until the whole control is clear of the bottom bar (its top is near the top of the scroll
    /// view, or it is fully inside the upper 60 %), scrolling back if it went above the top. The drag starts
    /// in the left margin, where there's no control to catch it.
    private func reveal() {
        XCTAssertTrue(control.waitForExistence(timeout: defaultTimeout))
        for _ in 0..<6 {
            if isClearOfBar { return }
            let frame = scrollView.frame
            let offset = control.frame.minY - frame.minY
            let down = offset < 0
            let from = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: down ? 0.2 : 0.55))
            let to = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: down ? 0.55 : 0.2))
            from.press(forDuration: 0.05, thenDragTo: to, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTAssertTrue(isClearOfBar, "the control is still under the bottom bar after scrolling: \(control.frame)")
    }

    /// The control's top is near the top of the scroll view, or the whole control is inside its upper 60 %.
    private var isClearOfBar: Bool {
        let frame = scrollView.frame
        let offset = control.frame.minY - frame.minY
        return offset >= -1 && (offset <= 90 || control.frame.maxY <= frame.minY + frame.height * 0.6)
    }
}

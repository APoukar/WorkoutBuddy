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

    /// Clears the focused field with `deleteCount` delete keys, then types `text` one character at a time,
    /// waiting after each for the field's value to show everything typed so far. A keystroke lost while the
    /// keyboard settles then fails here, at the character, instead of surfacing as a wrong value later.
    func type(_ text: String, deleting deleteCount: Int, file: StaticString = #filePath, line: UInt = #line) {
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deleteCount))
        field.typeSlowly(text, file: file, line: line)
    }

    private func tapButton(_ label: String) {
        reveal()
        control.buttons[label].tap()
    }

    /// Scrolls until the whole control is clear of the bottom bar (its top is near the top of the scroll
    /// view, or it is fully inside the upper 60 %). Each drag covers the distance still needed (a drag moves
    /// the content by about 90 % of its length), so the control doesn't overshoot past the top and bounce
    /// back and forth. The drag starts in the left margin, where there's no control to catch it.
    private func reveal() {
        XCTAssertTrue(control.waitForExistence(timeout: defaultTimeout))
        for _ in 0..<6 {
            if isClearOfBar { return }
            let frame = scrollView.frame
            // Positive: the content has to move up (the finger drags up) until the control is 8 pt from the top.
            let needed = (control.frame.minY - frame.minY - 8) / 0.9 / frame.height
            // The drag stays above the bottom bar (the lowest 35 % of the scroll view), which doesn't scroll.
            let limit = 0.5
            let distance = max(-limit, min(limit, needed))
            let start = distance > 0 ? 0.1 + distance : 0.1
            let from = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: start))
            let to = scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: start - distance))
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

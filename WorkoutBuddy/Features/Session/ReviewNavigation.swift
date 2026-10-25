import SwiftUI
import UIKit

/// Where a swipe or a VoiceOver action leads while looking back at earlier sets: swipe right goes to the
/// previous (older) set, swipe left to the next one (or back). `nil` means there's nowhere to go.
struct ReviewNavigation {
    struct Action {
        /// The VoiceOver action name.
        let title: String
        let perform: () -> Void
    }

    /// Off while the workout is paused (the overlay covers the screen) or a text field is being edited.
    var isEnabled = true
    /// Swipe right.
    var previous: Action?
    /// Swipe left.
    var next: Action?
}

/// A discrete left or right swipe, recognised by UIKit's `UISwipeGestureRecognizer`. Unlike a SwiftUI
/// `DragGesture` it recognises at the same time as the scroll view, so vertical scrolling, the - / +
/// buttons and the text fields keep working.
private struct SwipeGesture: UIGestureRecognizerRepresentable {
    let direction: UISwipeGestureRecognizer.Direction
    let isEnabled: Bool
    let action: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UISwipeGestureRecognizer {
        let recognizer = UISwipeGestureRecognizer()
        recognizer.direction = direction
        recognizer.isEnabled = isEnabled
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if recognizer.isEnabled != isEnabled { recognizer.isEnabled = isEnabled }
    }

    func handleUIGestureRecognizerAction(_ recognizer: UISwipeGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

extension View {
    /// Swipe right and left for `navigation`, plus the same as VoiceOver actions on the view. Attach it
    /// to the scrolling content, not to the bottom bar (the home-indicator edge). `isEditing` switches
    /// the swipes off while a text field is focused.
    func reviewSwipes(_ navigation: ReviewNavigation, isEditing: Bool = false) -> some View {
        let enabled = navigation.isEnabled && !isEditing
        return self
            .gesture(SwipeGesture(
                direction: .right, isEnabled: enabled && navigation.previous != nil,
                action: { navigation.previous?.perform() }))
            .gesture(SwipeGesture(
                direction: .left, isEnabled: enabled && navigation.next != nil,
                action: { navigation.next?.perform() }))
    }

    /// The navigation as named VoiceOver actions. Attach it to an accessibility element.
    func reviewAccessibilityActions(_ navigation: ReviewNavigation) -> some View {
        accessibilityActions {
            if let previous = navigation.previous { Button(previous.title, action: previous.perform) }
            if let next = navigation.next { Button(next.title, action: next.perform) }
        }
    }
}

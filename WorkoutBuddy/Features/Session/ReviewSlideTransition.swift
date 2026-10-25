import SwiftUI

/// Which side of the screen the review layer's new content comes from. Physical sides, matching the
/// swipe: swiping right (to an older set) brings content in from the left.
enum ReviewSlideSide {
    case left, right

    /// The sign of the horizontal offset for content waiting outside this side.
    var sign: CGFloat { self == .left ? -1 : 1 }
}

/// Remembers which way the review layer moves next. A reference type on purpose: the transition reads it
/// when it runs, so the layer that is being removed slides out the right way even though it was last
/// drawn before the direction was known.
final class ReviewSlideDirection {
    var side: ReviewSlideSide = .left
}

/// The review layer slides in from `direction.side` and out towards the opposite side. Used instead of
/// `.move(edge:)` because the removal of a view takes the transition from before the change.
struct ReviewSlideTransition: Transition {
    let direction: ReviewSlideDirection

    func body(content: Content, phase: TransitionPhase) -> some View {
        let sign: CGFloat = switch phase {
        case .identity: 0
        case .willAppear: direction.side.sign
        case .didDisappear: -direction.side.sign
        }
        content.visualEffect { view, proxy in
            view.offset(x: proxy.size.width * sign)
        }
    }
}

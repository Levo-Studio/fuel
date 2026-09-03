import SwiftUI

// MARK: - Back swipe

/// The leading-edge drag that closes a screen, and the geometry that decides
/// when a drag is one.
///
/// **Undrawn, like the curves in `FuelMotion`.** Every screen in Fuel is a
/// `fullScreenCover`, which has no interactive dismissal of its own, and the
/// export draws none: each screen carries its own `‹ Back` or `✕ Cancel`, and
/// that stays the control. This is a second way to reach the same exit for
/// people who reach for the edge before they reach for the corner — **it adds
/// no affordance of any kind.** There is no edge indicator, no peel, and the
/// screen does not track the finger, because all three would be drawing, and
/// drawing is the owner's.
///
/// A gesture that can destroy work is not a convenience, so `isEnabled` is not
/// a nicety: a screen holding unsaved edits either routes the gesture through
/// the same confirmation its drawn control uses, or does not offer it. See
/// `MealDetailView` for the live case.
nonisolated enum FuelBackSwipe {

    // MARK: - Geometry

    /// How far in from the leading edge a drag has to begin.
    ///
    /// Narrow on purpose: a drag that starts in the middle of the screen is
    /// somebody swiping content, not somebody leaving, and this is the number
    /// that keeps the two apart.
    static let edgeWidth: CGFloat = 20

    /// How far it has to travel before it counts.
    ///
    /// Comfortably past the 44pt a touch target is allowed to be, so a thumb
    /// resting near the edge and drifting cannot close a screen.
    static let travel: CGFloat = 60

    // MARK: - Recognition

    /// Whether a finished drag was a back swipe.
    ///
    /// Pure and separate from the gesture so the three ways it can be wrong —
    /// starting too far in, not travelling far enough, and travelling mostly
    /// downwards while a list scrolls — are held by tests rather than by a
    /// simulator someone has to drag on.
    static func isBackSwipe(startX: CGFloat, translation: CGSize) -> Bool {
        guard startX <= edgeWidth, translation.width >= travel else { return false }
        // Predominantly horizontal. A drag down the leading edge of a scrolling
        // list drifts sideways, and without this it would eventually close the
        // screen underneath the person reading it.
        return abs(translation.height) < translation.width
    }
}

// MARK: - Applying the gesture

private struct FuelBackSwipeModifier: ViewModifier {

    let isEnabled: Bool
    let perform: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            // Simultaneous rather than `gesture`: the screens this sits on
            // scroll and carry buttons, and an exclusive drag recogniser over
            // the whole surface would take touches away from both.
            DragGesture(minimumDistance: FuelBackSwipe.travel, coordinateSpace: .local)
                .onEnded { drag in
                    guard
                        isEnabled,
                        FuelBackSwipe.isBackSwipe(
                            startX: drag.startLocation.x,
                            translation: drag.translation
                        )
                    else {
                        return
                    }
                    perform()
                }
        )
    }
}

extension View {

    /// Closes this screen on a drag in from the leading edge.
    ///
    /// `isEnabled` is for a screen that is holding something a dismissal would
    /// throw away. Passing `true` there is a claim that nothing is lost by
    /// leaving.
    func fuelBackSwipe(isEnabled: Bool = true, perform: @escaping () -> Void) -> some View {
        modifier(FuelBackSwipeModifier(isEnabled: isEnabled, perform: perform))
    }
}

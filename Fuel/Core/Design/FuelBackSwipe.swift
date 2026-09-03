import SwiftUI

// MARK: - Back swipe

/// The left-edge drag that closes a screen, and the geometry that decides when
/// a drag is one.
///
/// **Left, not leading.** `startX` is a distance from x = 0, which is the
/// leading edge only where the layout runs left to right. Fuel's interface is
/// English and nothing else — the string catalog holds one language and the
/// repository forbids a second — so the two cannot come apart here, and saying
/// "leading" would claim a right-to-left correctness this does not have.
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

    /// How far in from the left edge of the screen a drag has to begin.
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
        // Predominantly horizontal. A drag down the left edge of a scrolling
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
            // `.global` and not `.local`: `edgeWidth` is a distance from the
            // edge of the screen, and in local space it would mean a distance
            // from the edge of whatever this happens to be attached to. Both
            // call sites are full-screen roots today, where the two agree — so
            // the difference is invisible until someone applies this to an
            // inset view, and then it arms a back swipe in the middle of the
            // screen. Global keeps the constant meaning what it says.
            DragGesture(minimumDistance: FuelBackSwipe.travel, coordinateSpace: .global)
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

    /// Closes this screen on a drag in from the left edge of the screen.
    ///
    /// **Apply it to something that fills the screen.** The drag is measured in
    /// global coordinates, so the edge is the device's and not this view's: on
    /// a half-width or inset view the gesture would still be armed by a touch
    /// at the left of the screen, which may be nowhere near the view itself.
    ///
    /// `isEnabled` is for a screen that is holding something a dismissal would
    /// throw away. Passing `true` there is a claim that nothing is lost by
    /// leaving.
    func fuelBackSwipe(isEnabled: Bool = true, perform: @escaping () -> Void) -> some View {
        modifier(FuelBackSwipeModifier(isEnabled: isEnabled, perform: perform))
    }
}

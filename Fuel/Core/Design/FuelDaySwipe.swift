import SwiftUI

// MARK: - Day swipe

/// The sideways drag that moves Today to the day beside it, and the geometry
/// that decides when a drag is one.
///
/// **Undrawn**, like `FuelBackSwipe` next to it and for the same reason: the
/// export is a set of still frames and says nothing about what a finger does to
/// them. Screens 05 and 06 draw no navigation of any kind. Browsing is the
/// owner's instruction, and this is one of the three ways in — the header's
/// arrows are the drawn affordance, and this adds none of its own.
///
/// **It does not reserve the left edge**, which is the one thing worth saying
/// about it next to the back swipe. Everywhere else in Fuel a drag in from the
/// left means *leave this screen*: Settings takes one, and the meal screen has
/// the system's own pop. Today is the root — there is nothing to go back to and
/// no screen underneath — so the edge carries no second meaning here, and
/// excluding it would only kill the gesture in the strip where reaching for the
/// previous day is most natural.
///
/// What it does have to keep clear of is the vertical scroll underneath it,
/// which is what `direction(of:)` is for.
nonisolated enum FuelDaySwipe {

    // MARK: - Direction

    /// Which way a recognised drag moved the day.
    ///
    /// Named by the day rather than by the finger. A drag to the right moves
    /// *back*, the way a page turns, and calling the case `right` would make
    /// every call site translate it again.
    enum Direction: Equatable, Sendable {

        case earlier
        case later
    }

    // MARK: - Geometry

    /// How far a drag has to travel sideways before it changes the day.
    ///
    /// Deliberately `FuelBackSwipe`'s own distance rather than a second number
    /// beside it: "a horizontal drag that meant something" is one question, and
    /// two answers to it would mean a swipe had to be longer on one screen than
    /// on another for no reason a user could see.
    static let travel = FuelBackSwipe.travel

    // MARK: - Recognition

    /// Which day a finished drag asked for, or `nil` when it was not asking for
    /// one.
    ///
    /// Pure and separate from the gesture so the two ways it can be wrong —
    /// not travelling far enough, and travelling mostly up or down while the
    /// day list scrolls — are held by tests rather than by a simulator someone
    /// has to drag on.
    static func direction(of translation: CGSize) -> Direction? {
        guard abs(translation.width) >= travel else { return nil }
        // Predominantly horizontal, the guard `FuelBackSwipe` uses and the one
        // that keeps this off the scroll underneath: Today's list scrolls
        // vertically, a scrolling thumb drifts sideways, and without this a
        // long scroll would eventually change the day under the person reading
        // it. Strict, so a perfect diagonal is a scroll rather than a day.
        guard abs(translation.height) < abs(translation.width) else { return nil }
        return translation.width > 0 ? .earlier : .later
    }
}

// MARK: - Applying the gesture

private struct FuelDaySwipeModifier: ViewModifier {

    let perform: (FuelDaySwipe.Direction) -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            // Simultaneous rather than `gesture`, for the reason the back swipe
            // is: this sits on a scrolling surface carrying buttons on every
            // row, and an exclusive drag recogniser over the whole screen would
            // take touches away from both. The `minimumDistance` is what keeps
            // it away from the taps — a finger that lands on a meal row and
            // lifts never reaches this at all.
            //
            // `.local` and not `.global`, unlike the back swipe: nothing here
            // is measured from the edge of the screen, only how far the finger
            // went, and that is the same distance in either space.
            DragGesture(minimumDistance: FuelDaySwipe.travel)
                .onEnded { drag in
                    guard let direction = FuelDaySwipe.direction(of: drag.translation) else { return }
                    perform(direction)
                }
        )
    }
}

extension View {

    /// Moves to the day beside this one on a sideways drag.
    ///
    /// The day at the far end of the move is the caller's business: this says
    /// only which way the finger asked to go, and a caller already at a bound
    /// does nothing with it.
    func fuelDaySwipe(perform: @escaping (FuelDaySwipe.Direction) -> Void) -> some View {
        modifier(FuelDaySwipeModifier(perform: perform))
    }
}

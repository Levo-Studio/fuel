import SwiftUI

// MARK: - List fade

/// The band that takes a scrolling list out under whatever floats over its
/// bottom edge, so the last rows do not collide with a control standing on
/// them.
///
/// **Prototype-only, and written down for one screen.**
/// `design/Fuel Design Notes.md` describes it under "The list fade under the
/// add button" — a 120pt band across the bottom of Today,
/// `linear-gradient(to top, bg 46%, transparent)`, drawn behind the floating
/// add button. A static render has no scrolled list to fade, so grepping
/// `Screens2c.dc.html` for it comes back empty. See `FuelMetrics.ListFade` for
/// the two values.
///
/// The result screens carry the same band under their footer, and there the
/// design says nothing at all — see `mealResultFooter`. What they are in is the
/// situation this fade was written for, so they get this one at its own height
/// and its own stop rather than a gradient invented beside it.
///
/// It lives in the design layer rather than beside a call site for the reason
/// `FuelCheckGlyph` does: a gradient copied into a second feature is a gradient
/// that can be corrected in one place and left wrong in the other.
///
/// Behind whatever it is covering for and in front of the list, and
/// deliberately not hit-testable: it covers the last rows, and a row under it
/// still has to be reachable.
struct FuelListFade: View {

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: palette.background, location: .zero),
                Gradient.Stop(color: palette.background, location: FuelMetrics.ListFade.opaqueStop),
                Gradient.Stop(color: palette.background.opacity(.zero), location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: FuelMetrics.ListFade.height)
        .allowsHitTesting(false)
    }
}

// MARK: - Top fade

/// The band at the other end of the same list: it takes the day out from under
/// the status row, so a total scrolled up to the top edge is not drawn through
/// the clock.
///
/// **Undrawn, like the band below it, and reported the same way.** The export
/// has no scrolled state at either end. What the owner saw was the big total
/// travelling up under the status row and reading straight through the time,
/// at full contrast, with neither legible.
///
/// **The same gradient inverted, and deliberately not the same two values.**
/// Both of `FuelListFade`'s numbers were measured against a band standing on
/// the bottom edge with nothing at rest underneath it, and neither survives the
/// move to a top edge that a header is already sitting against:
///
/// - **Not 120 tall.** Today's header stands `Space.s26` below the safe area
///   and does not move when the list scrolls. A 120pt band would still be at
///   roughly half opacity where the eyebrow begins, so the date, the title and
///   all three header controls would sit behind a wash while nothing had been
///   scrolled at all.
/// - **Not stopped at 46%.** The strip this exists to keep clear is the one the
///   system draws its clock, its indicators and its island into, and that strip
///   is the top safe area — a figure the app is told rather than one it may
///   choose. So the band is opaque across exactly that and fades out over the
///   header's own drop below it. Both of its edges are facts of the layout, and
///   the whole reserved strip is covered on every device rather than whichever
///   fraction of it a proportion carried over from the other end would happen
///   to reach.
///
/// In front of the list and behind nothing, and not hit-testable for the reason
/// its sibling is not: it covers rows that are still rows a finger can reach.
struct FuelListTopFade: View {

    /// The strip the system reserves at the top of the screen.
    ///
    /// Passed in rather than read here: a view that has been told to ignore the
    /// safe area is the one place that can no longer ask what it was.
    let statusBar: CGFloat

    @Environment(\.fuelPalette) private var palette

    /// Down to the first line of the header, which is where the band has to be
    /// gone: the reserved strip, plus the drop the header stands at.
    private var height: CGFloat { statusBar + FuelMetrics.Space.s26 }

    /// Where it stops being opaque, as a fraction of that height — the bottom
    /// edge of the reserved strip.
    private var opaqueStop: CGFloat { height > .zero ? statusBar / height : .zero }

    var body: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: palette.background, location: .zero),
                Gradient.Stop(color: palette.background, location: opaqueStop),
                Gradient.Stop(color: palette.background.opacity(.zero), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .allowsHitTesting(false)
    }
}

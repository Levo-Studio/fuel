import SwiftUI

// MARK: - List fade

/// The band that takes a scrolling list out under whatever floats over its
/// bottom edge, so the last rows do not collide with a control standing on
/// them.
///
/// **Prototype-only.** `design/Fuel Design Notes.md` describes it under "The
/// list fade under the add button" — a 120pt band across the bottom of Today,
/// `linear-gradient(to top, bg 46%, transparent)`, drawn behind the floating
/// add button. A static render has no scrolled list to fade, so grepping
/// `Screens2c.dc.html` for it comes back empty. See `FuelMetrics.ListFade` for
/// the two values.
///
/// It lives in the design layer rather than beside its call site for the reason
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

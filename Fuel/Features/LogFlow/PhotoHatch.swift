import SwiftUI

// MARK: - Hatch

/// The diagonal hatch the export draws wherever a picture goes but none is
/// there yet: the viewfinder before the session hands over a frame, the frozen
/// frame under the analysis scrim, and the result screen's thumbnail.
///
/// Drawn rather than tiled from an asset, because it is a design value — a
/// `135°` axis and a `10pt` band, from `FuelMetrics.Hatch` — and an image would
/// hide those numbers in a file nobody diffs. `Canvas` is the cheapest way to
/// repeat a gradient SwiftUI has no repeating gradient for.
struct PhotoHatch: View {

    /// What sits behind the stripes. `Color.clear` on the result screen, whose
    /// export writes the second stop as `transparent` over the page.
    let base: Color

    let stripe: Color

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))

            // The stripes are drawn along a rotated axis, so they have to cover
            // the frame's diagonal in both directions to reach every corner.
            let reach = (size.width * size.width + size.height * size.height).squareRoot()
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: .degrees(FuelMetrics.Hatch.angleDegrees))

            let band = FuelMetrics.Hatch.band
            var offset = -reach
            while offset < reach {
                // Stacked along y, so the unrotated gradient axis points along
                // y and the rotation above is the CSS angle itself rather than
                // the CSS angle plus a quarter turn. CSS measures a gradient
                // from "to top" and turns clockwise, so a construction that
                // stacked bands along x would start at 90° and land the whole
                // hatch a quarter turn out — bands running "\" where the export
                // draws "/". They are the same three numbers either way, which
                // is exactly why the mistake is invisible in a diff.
                context.fill(
                    Path(CGRect(x: -reach, y: offset, width: reach * 2, height: band)),
                    with: .color(stripe)
                )
                // One band painted, one band left, which is what
                // `0 10px, 10px 20px` says.
                offset += band * 2
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Hatch") {
    PhotoHatch(
        base: FuelPalette.Camera.placeholderBase,
        stripe: FuelPalette.Camera.placeholderStripe
    )
    .frame(width: FuelMetrics.Control.thumbnailHeight, height: FuelMetrics.Control.thumbnailHeight)
}

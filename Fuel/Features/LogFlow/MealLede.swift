import SwiftUI

// MARK: - Photo lede

/// The captured-photo thumbnail above the meal-label pill: screen 14's slot,
/// and — since the photo now travels with the entry it was scanned into —
/// `MealDetailView`'s, on a meal that was logged from a photo.
///
/// Shared rather than redrawn: `PhotoResultView` and `MealDetailView` are
/// filling the exact same slot `MealResultView.lede` gives them, and a second
/// copy of this box is a second place its padding, its radius and its
/// hairline could drift from the first.
struct MealPhotoLede: View {

    /// `nil` in a preview, where the export's own `CAPTURED PHOTO` stand-in is
    /// what is drawn. Never `nil` from `MealDetailView` — it chooses this lede
    /// only once a photo has decoded.
    let photo: UIImage?

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                PhotoHatch(base: .clear, stripe: palette.soft)

                Text(CameraCopy.resultPhotoCaption)
                    .fuelStyle(FuelTypography.overlayCaption)
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: FuelMetrics.Control.thumbnailHeight)
        .clipShape(.rect(cornerRadius: FuelMetrics.Radius.thumbnail))
        .overlay {
            RoundedRectangle(cornerRadius: FuelMetrics.Radius.thumbnail)
                .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
        }
        .accessibilityElement()
        .accessibilityLabel(Text(CameraCopy.resultPhotoLabel))
    }
}

// MARK: - Quote lede

/// The typed sentence, quoted back above the meal-label pill: screen 15's
/// slot, and — for the same reason `MealPhotoLede` is shared — a meal
/// `MealDetailView` opens that was logged from one.
///
/// The sentence behind an accent rule: `border-left:2px solid var(--accent)`
/// with `padding:2px 0 2px 14px`. A rule and a gap in a row rather than a
/// border on a box, because CSS draws the border outside the padding — the
/// sentence sits 14 from the rule and the rule sits at the margin, which is
/// what this arrangement gives and what a `.overlay` inside the padding would
/// not.
struct MealQuoteLede: View {

    /// The user's own words, verbatim. `Text(verbatim:)` at the call site,
    /// so nothing typed is read as markup on the way back to them.
    let text: String

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: FuelMetrics.Space.s14) {
            palette.accentColor
                .frame(width: FuelMetrics.Line.quoteRule)

            Text(verbatim: text)
                .fuelStyle(FuelTypography.body)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, FuelMetrics.Space.s2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(TextLogCopy.resultQuoteLabel))
        .accessibilityValue(Text(verbatim: text))
    }
}

// MARK: - Title lede

/// What the lede slot shows when there is nothing fresher to put there.
///
/// **Not in the export** — the export's result screens always have a capture
/// behind them, so this case has no drawn frame to match. Two situations land
/// here, permanently: a meal repeated from the Recent list, which never had a
/// capture of its own, and a meal logged before Fuel kept the photo or the
/// sentence behind an estimate at all. Both are the same absence, so both get
/// the same answer — the meal's own name, in the slot's own position, so
/// `MealDetailView` never opens on a gap where the photo or the quote would
/// be.
struct MealTitleLede: View {

    let title: String

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Text(verbatim: title)
            .fuelStyle(FuelTypography.entryTitle)
            .foregroundStyle(palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: title))
    }
}

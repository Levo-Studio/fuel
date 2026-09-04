import SwiftUI

// MARK: - Accuracy

/// How sure the model is of a meal's estimate, standing on the row of facts
/// above the kilocalorie figure: `80% ACC`.
///
/// **Not in the export, and recomposed from it rather than invented beside
/// it.** There is no frame with this element in it, no type style drawn for it
/// and no spacing measured for it — the owner asked for it after a build. Every
/// value it uses is one the export already draws, and the reasoning is the same
/// one `MealResultView.adviceLine` sets out for the advisor sentence — which is
/// also why this lives here rather than in the design layer; see "Where this
/// lives" below.
///
/// **Two drawn treatments were candidates and they disagree about one thing.**
/// Screen 14 sets a small mono run in `muted` twice over:
///
/// - line 316, `CAPTURED PHOTO` over the thumbnail —
///   `400 10.5px 'DM Mono'`, `letter-spacing:.1em`, drawn already uppercase.
/// - line 336, `sicher · ca. 150 g` under a recognised item's name —
///   `400 10.5px 'DM Mono'`, no tracking, mixed case.
///
/// They agree on family, weight, size and colour, and this element takes all
/// four from them without a choice being made. **The one difference is the
/// tracking, and the tracking follows the casing.** All twenty-seven
/// `text-transform:uppercase` declarations in the export carry a
/// `letter-spacing` and not one is untracked; the untracked mono runs are bare
/// figures with no uppercase word in them, and line 336 is lowercase prose on
/// the same side of that rule. So the casing decides, and `ACC` is the owner's
/// copy: line 316's treatment is the internally consistent one, and taking line
/// 336's tracking while keeping uppercase would be half of a treatment in a
/// combination the export never draws.
///
/// Line 336 is the stronger citation on its own terms — it is what the export
/// draws for a *confidence* specifically — and if the owner would rather have
/// that look, **the change is to the copy and not to the type**: spell the word
/// out, or write `Acc`, and the tracking follows it down to zero. That is a
/// one-line ruling on `result.accuracy`, not a rebuild of this view.
///
/// **Mono because it is a figure.** `Fuel Design Notes.md` gives DM Mono 400 as
/// "every number, every timestamp, every uppercase letter-spaced eyebrow", and
/// this is the first and the third at once.
///
/// **Smaller than the figures around it.** The export never gives a companion
/// figure one global size — `/ 2400 kcal` is 13pt beside the 74pt day total,
/// `kcal` is 12pt beside the 58pt result figure, `08:14 · Photo` is 11pt under
/// a 14.5pt row title — so 10.5pt is the quiet register beside the 11.5pt sans
/// of the two pills it stands between.
///
/// **It does not scale with Dynamic Type**, and that is `FuelTypography`'s own
/// rule rather than a convenience: a tracked uppercase eyebrow is pinned
/// because growing it wraps a line rather than making it more readable. Here it
/// also keeps the element from crowding those pills.
///
/// **Accent-safe by construction.** `muted` is derived from the theme's ink and
/// never from the accent, so all five accents draw this identically.
///
/// ## Where this lives
///
/// **In the feature, not in `Core/Design/`, and it was in the design layer
/// until the score moved.** `FuelGlyphs` states the repo's test for design-layer
/// residency in its own words: a mark belongs there once *two* things carry it,
/// because "a mark copied into a second feature is a mark that can be corrected
/// in one place and left wrong in the other". While the score also stood on a
/// day-list row that test was met. The owner has since put it on the meal
/// detail screen alone, so exactly one feature draws it — `MealResultView`,
/// which is screens 14, 15 and the detail screen — and the test is not met any
/// more.
///
/// Applying that rule honestly is worth more than the convenience of leaving it
/// where it was. It also puts `Core/Design/` back to reading no string catalog
/// at all: the copy is `MealResultCopy`'s now, beside the rest of the words
/// these screens say. `adviceLine` is the precedent in both directions — an
/// element the export does not draw, recomposed from values it does, living in
/// the feature that draws it with its reasoning in a comment there.
///
/// If a second feature ever draws a score, `FuelGlyphs`' rule says move this
/// back rather than copy it.
struct MealAccuracyLabel: View {

    /// A whole percent, `0...100`. The caller has already decided there is one
    /// — an absent figure draws nothing at all rather than a placeholder, so
    /// this type never has to represent "unknown". `MealResultView.labelRow` is
    /// the one place that draws it.
    let percent: Int

    /// The drawn style, named so a test can hold *this element* to it rather
    /// than restating what `overlayCaption` happens to contain. A style test
    /// that reads the token directly passes whatever this view is set in, which
    /// is a test that cannot fail for the reason it exists — and one did, until
    /// `AccuracyLabelDrawingTests` began measuring the ink instead.
    static let style = FuelTypography.overlayCaption

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Text(MealResultCopy.accuracy(percent))
            .fuelStyle(Self.style)
            .foregroundStyle(palette.muted)
            .accessibilityLabel(Text(MealResultCopy.accuracySpoken(percent)))
    }
}

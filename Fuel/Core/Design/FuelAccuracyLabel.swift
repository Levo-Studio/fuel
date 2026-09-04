import SwiftUI

// MARK: - Accuracy

/// How sure the model is of a meal's estimate, drawn beside that meal's
/// kilocalorie figure: `80% ACC`.
///
/// **Not in the export, and recomposed from it rather than invented beside
/// it.** There is no frame with this element in it, no type style drawn for it
/// and no spacing measured for it — the owner asked for it after a build. Every
/// value it uses is one the export already draws, and the reasoning is the same
/// one `MealResultView.adviceLine` sets out for the advisor sentence.
///
/// - **Type and colour are screen 14's own.** `overlayCaption` is
///   `400 10.5px 'DM Mono'` with `.1em` of tracking, drawn already uppercase,
///   and `Screens2c.dc.html` line 316 sets it in `var(--muted)` for the
///   `CAPTURED PHOTO` label over the result thumbnail — the same screen this
///   element joins, a few points above the calorie row it sits on. A small
///   tracked uppercase mono run in `muted` is a thing that screen already
///   contains.
/// - **Mono, because it is a figure.** `Fuel Design Notes.md` gives DM Mono
///   400 as "every number, every timestamp, every uppercase letter-spaced
///   eyebrow", and this is the first and the third at once. `ACC` carries
///   tracking because every uppercase run in seventeen screens does; an
///   untracked one appears nowhere.
/// - **Smaller than the figure it qualifies, at every site.** The export never
///   gives a companion figure one global size — `/ 2400 kcal` is 13pt beside
///   the 74pt day total, `kcal` is 12pt beside the 58pt result figure,
///   `08:14 · Photo` is 11pt under a 14.5pt row title — so 10.5pt reads as the
///   quiet register on the 15pt day-list row and on the 58pt result row alike.
///
/// **It does not scale with Dynamic Type**, and that is `FuelTypography`'s own
/// rule rather than a convenience: a tracked uppercase eyebrow is pinned
/// because growing it wraps a line rather than making it more readable. It also
/// keeps the element a fixed width on the day-list row, so the meal name's
/// share of that row does not shrink as the user's text size grows.
///
/// **Accent-safe by construction.** `muted` is derived from the theme's ink and
/// never from the accent, so all five accents draw this identically.
struct FuelAccuracyLabel: View {

    /// A whole percent, `0...100`. The caller has already decided there is one
    /// — an absent figure draws nothing at all rather than a placeholder, so
    /// this type never has to represent "unknown".
    let percent: Int

    /// The drawn style, named so a test can hold *this element* to it rather
    /// than restating what `overlayCaption` happens to contain. A style test
    /// that reads the token directly passes whatever this view is set in, which
    /// is a test that cannot fail for the reason it exists.
    static let style = FuelTypography.overlayCaption

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Text(FuelAccuracyCopy.figure(percent))
            .fuelStyle(Self.style)
            .foregroundStyle(palette.muted)
            .accessibilityLabel(Text(FuelAccuracyCopy.spoken(percent)))
    }
}

// MARK: - Copy

/// The two keys this element needs.
///
/// **The one place in the design layer that reads the string catalog**, and it
/// is here because the element belongs to no single feature: the day list draws
/// it and both result screens draw it. A copy accessor in each of those
/// features would be two keys with one value, which is the drift a shared
/// element exists to prevent.
///
/// Casing is the value's rather than the style's, exactly as `CAPTURED PHOTO`
/// and `CANCEL` are stored: `overlayCaption` does not transform, because the
/// export draws those runs already uppercase.
nonisolated enum FuelAccuracyCopy {

    static func figure(_ percent: Int) -> String {
        String(format: String(localized: "accuracy.figure"), percent)
    }

    /// What VoiceOver says instead. `80% ACC` spoken letter by letter is not a
    /// word, and an abbreviation that exists to save room on a row has no room
    /// to save in speech.
    static func spoken(_ percent: Int) -> String {
        String(format: String(localized: "accuracy.figure.spoken"), percent)
    }
}

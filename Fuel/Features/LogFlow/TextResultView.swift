import SwiftUI

// MARK: - Text result

/// Screen 15: `MealResultView` with the typed sentence above the meal-label
/// pill, the `Text entry` flow label, and `Broken down` over the breakdown.
///
/// That is the whole difference between screens 15 and 14, so it is the whole
/// of this file.
struct TextResultView: View {

    let draft: MealResultDraft

    /// What the user typed, quoted back to them.
    let typedText: String

    let onBack: () -> Void
    let onCycleLabel: () -> Void
    let onToggleFavourite: () -> Void
    let onAdjustCalories: (Int) -> Void
    let onNew: () -> Void
    let onAdd: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        MealResultView(
            draft: draft,
            flowLabel: TextLogCopy.resultFlow,
            itemsHeading: TextLogCopy.resultItemsHeading,
            onBack: onBack,
            onCycleLabel: onCycleLabel,
            onToggleFavourite: onToggleFavourite,
            onAdjustCalories: onAdjustCalories,
            onNew: onNew,
            onAdd: onAdd,
            lede: { quote }
        )
    }

    // MARK: - Quote

    /// The sentence behind an accent rule: `border-left:2px solid var(--accent)`
    /// with `padding:2px 0 2px 14px`.
    ///
    /// A rule and a gap in a row rather than a border on a box, because CSS
    /// draws the border outside the padding — the sentence sits 14 from the
    /// rule and the rule sits at the margin, which is what this arrangement
    /// gives and what a `.overlay` inside the padding would not.
    ///
    /// `Text(verbatim:)` because the words are the user's own: nothing they
    /// type is read as markup on the way back to them.
    private var quote: some View {
        HStack(alignment: .top, spacing: FuelMetrics.Space.s14) {
            palette.accentColor
                .frame(width: FuelMetrics.Line.quoteRule)

            Text(verbatim: typedText)
                .fuelStyle(FuelTypography.body)
                .foregroundStyle(palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, FuelMetrics.Space.s2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(TextLogCopy.resultQuoteLabel))
        .accessibilityValue(Text(verbatim: typedText))
    }
}

// MARK: - Preview

#Preview("Result after text entry") {
    TextResultView(
        draft: TextPreviewData.draft,
        typedText: TextPreviewData.typedText,
        onBack: {},
        onCycleLabel: {},
        onToggleFavourite: {},
        onAdjustCalories: { _ in },
        onNew: {},
        onAdd: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
}

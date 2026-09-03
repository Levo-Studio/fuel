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
    let onRemoveItem: (RecognisedItem.ID) -> Void
    let onEditItem: (RecognisedItem.ID, String) -> Void
    let onAddItem: (String) -> Void
    let onReanalyse: () -> Void
    let onDiscard: (() -> Void)?
    let commit: MealResultAction

    var body: some View {
        MealResultView(
            draft: draft,
            flowLabel: TextLogCopy.resultFlow,
            itemsHeading: TextLogCopy.resultItemsHeading,
            onBack: onBack,
            onCycleLabel: onCycleLabel,
            onToggleFavourite: onToggleFavourite,
            onRemoveItem: onRemoveItem,
            onEditItem: onEditItem,
            onAddItem: onAddItem,
            onReanalyse: onReanalyse,
            onDiscard: onDiscard,
            discardConfirmation: MealResultCopy.discardConfirmation,
            commit: commit,
            lede: { MealQuoteLede(text: typedText) }
        )
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
        onRemoveItem: { _ in },
        onEditItem: { _, _ in },
        onAddItem: { _ in },
        onReanalyse: {},
        onDiscard: {},
        commit: MealResultAction(title: MealResultCopy.add, perform: {})
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
}

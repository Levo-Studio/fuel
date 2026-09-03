import SwiftUI

// MARK: - Photo result

/// Screen 14: `MealResultView` with the captured photo above the meal-label
/// pill, the `Photo entry` flow label, and `Recognised` over the breakdown.
///
/// That is the whole difference between screens 14 and 15, so it is the whole
/// of this file.
struct PhotoResultView: View {

    let draft: MealResultDraft

    /// The captured frame. `nil` in a preview, where the export's own
    /// `CAPTURED PHOTO` stand-in is what is drawn.
    let photo: UIImage?

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
            flowLabel: CameraCopy.resultFlow,
            itemsHeading: CameraCopy.resultItemsHeading,
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
            lede: { MealPhotoLede(photo: photo) }
        )
    }
}

// MARK: - Preview

#Preview("Result after photo scan") {
    PhotoResultView(
        draft: CameraPreviewData.draft,
        photo: nil,
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
    .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

/// The screen with nothing to throw away, which is the shape a caller opening
/// it on a meal that is already in the store will want: no leading control at
/// all, and the filled button carrying that caller's own verb.
///
/// It exists so that branch is drawn somewhere. Neither log mode passes `nil` —
/// both always have a scan or an estimate to discard — so without this the
/// footer's one conditional would never be rendered by anything.
#Preview("Result with nothing to discard") {
    PhotoResultView(
        draft: CameraPreviewData.draft,
        photo: nil,
        onBack: {},
        onCycleLabel: {},
        onToggleFavourite: {},
        onRemoveItem: { _ in },
        onEditItem: { _, _ in },
        onAddItem: { _ in },
        onReanalyse: {},
        onDiscard: nil,
        commit: MealResultAction(title: MealResultCopy.add, perform: {})
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .blue))
}

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
    let onAdjustCalories: (Int) -> Void
    let onNew: () -> Void
    let onAdd: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        MealResultView(
            draft: draft,
            flowLabel: CameraCopy.resultFlow,
            itemsHeading: CameraCopy.resultItemsHeading,
            onBack: onBack,
            onCycleLabel: onCycleLabel,
            onToggleFavourite: onToggleFavourite,
            onAdjustCalories: onAdjustCalories,
            onNew: onNew,
            onAdd: onAdd,
            lede: { thumbnail }
        )
    }

    // MARK: - Photo

    private var thumbnail: some View {
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

// MARK: - Preview

#Preview("Result after photo scan") {
    PhotoResultView(
        draft: CameraPreviewData.draft,
        photo: nil,
        onBack: {},
        onCycleLabel: {},
        onToggleFavourite: {},
        onAdjustCalories: { _ in },
        onNew: {},
        onAdd: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

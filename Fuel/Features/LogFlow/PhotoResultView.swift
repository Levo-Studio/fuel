import SwiftUI

// MARK: - Photo result

/// Screen 14: what the model came back with, before any of it is written down.
///
/// It follows the theme rather than the camera surface — the export draws it on
/// `bg`, not on `cam`, because the scan is over and there is no viewfinder left
/// to keep legible.
///
/// The estimate's **title is not drawn here.** The export puts the photo where
/// screen 15 puts the typed sentence, and gives the result no heading of its
/// own. The title still travels in the draft and still becomes the entry's
/// name in the day list; this screen simply does not show it.
///
/// Presentation only: it is handed a draft and hands back taps, so it renders
/// in a preview without a store, a client or a camera.
struct PhotoResultView: View {

    let draft: PhotoResultDraft

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
        ZStack(alignment: .bottom) {
            palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: .zero) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: .zero) {
                        thumbnail
                        labelRow
                        caloriesRow
                        macroRow
                        itemList
                    }
                    .padding(.top, FuelMetrics.Space.s26)
                    .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
                    // The footer floats over the list, so the last row has to
                    // be able to clear it.
                    .padding(.bottom, FuelMetrics.Space.s96)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            Button(action: onBack) {
                Text(CameraCopy.resultBack)
                    .fuelStyle(FuelTypography.eyebrow)
                    .foregroundStyle(palette.muted)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(CameraCopy.resultBackLabel))

            Spacer(minLength: FuelMetrics.Space.s14)

            Text(CameraCopy.resultFlow)
                .fuelStyle(FuelTypography.flowLabel)
                .foregroundStyle(palette.muted)
        }
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
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

    // MARK: - Label and favourite

    private var labelRow: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            mealLabelPill
            Spacer(minLength: FuelMetrics.Space.s14)
            favouritePill
        }
        .padding(.top, FuelMetrics.Space.s24)
    }

    /// The pill cycles Breakfast → Lunch → Snack → Dinner and wraps, which is
    /// `MealLabel.next` and the day list's own order. It is a cycle rather than
    /// a menu because the export draws a chevron on a pill, not a picker.
    private var mealLabelPill: some View {
        Button(action: onCycleLabel) {
            HStack(alignment: .center, spacing: FuelMetrics.Space.s7) {
                Text(CameraCopy.mealLabel(draft.label))
                    .fuelStyle(FuelTypography.tabLabel)
                    .foregroundStyle(palette.ink)

                ChevronGlyph()
                    .stroke(
                        palette.ink,
                        style: StrokeStyle(lineWidth: FuelMetrics.Line.Glyph.chevron, lineCap: .round, lineJoin: .round)
                    )
                    .frame(
                        width: FuelMetrics.Line.Glyph.chevronWidth,
                        height: FuelMetrics.Line.Glyph.chevronHeight
                    )
            }
            .padding(.vertical, FuelMetrics.Space.s8)
            .padding(.horizontal, FuelMetrics.Space.s14)
            .overlay {
                RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                    .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
            }
            .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(CameraCopy.mealLabel(draft.label)))
        .accessibilityHint(Text(CameraCopy.mealLabelHint))
        .fuelAnimation(FuelMotion.standard, value: draft.label)
    }

    private var favouritePill: some View {
        Button(action: onToggleFavourite) {
            Text(CameraCopy.favourite(isOn: draft.isFavourite))
                .fuelStyle(FuelTypography.tabLabel)
                .foregroundStyle(draft.isFavourite ? palette.onAccent : palette.muted)
                .padding(.vertical, FuelMetrics.Space.s8)
                .padding(.horizontal, FuelMetrics.Space.s13)
                .background {
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .fill(draft.isFavourite ? palette.accentColor : .clear)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .strokeBorder(
                            draft.isFavourite ? palette.accentColor : palette.hair,
                            lineWidth: FuelMetrics.Line.hairline
                        )
                }
                .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(CameraCopy.favouriteLabel))
        .accessibilityAddTraits(draft.isFavourite ? [.isButton, .isSelected] : .isButton)
        .fuelAnimation(FuelMotion.standard, value: draft.isFavourite)
    }

    // MARK: - Calories

    private var caloriesRow: some View {
        HStack(alignment: .bottom, spacing: FuelMetrics.Space.s14) {
            HStack(alignment: .lastTextBaseline, spacing: FuelMetrics.Space.s8) {
                Text(LogFlowFormat.figure(draft.kilocalories))
                    .fuelStyle(FuelTypography.resultCalories)
                    .foregroundStyle(palette.ink)
                    .contentTransition(.numericText())

                Text(CameraCopy.resultUnit)
                    .fuelStyle(FuelTypography.unit)
                    .foregroundStyle(palette.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(CameraCopy.kilocaloriesValue(draft.kilocalories)))

            Spacer(minLength: FuelMetrics.Space.s14)

            HStack(alignment: .center, spacing: FuelMetrics.Space.s8) {
                stepper(
                    glyph: CameraCopy.stepperDecrease,
                    label: CameraCopy.stepperDecreaseLabel,
                    delta: -CameraLogModel.calorieStep
                )
                stepper(
                    glyph: CameraCopy.stepperIncrease,
                    label: CameraCopy.stepperIncreaseLabel,
                    delta: CameraLogModel.calorieStep
                )
            }
        }
        .padding(.top, FuelMetrics.Space.s22)
        .fuelAnimation(FuelMotion.value, value: draft.kilocalories)
    }

    private func stepper(glyph: String, label: String, delta: Int) -> some View {
        Button {
            onAdjustCalories(delta)
        } label: {
            Text(glyph)
                .fuelStyle(FuelTypography.stepperGlyph)
                .foregroundStyle(palette.ink)
                .frame(width: FuelMetrics.Control.circleButton, height: FuelMetrics.Control.circleButton)
                .overlay {
                    Circle()
                        .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                }
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }

    // MARK: - Macros

    private var macroRow: some View {
        HStack(alignment: .top, spacing: FuelMetrics.Space.s24) {
            macro(CameraCopy.macroProtein, draft.macros.protein)
            macro(CameraCopy.macroCarbs, draft.macros.carbs)
            macro(CameraCopy.macroFat, draft.macros.fat)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s20)
        .padding(.bottom, FuelMetrics.Space.s20)
        .overlay(alignment: .bottom) {
            palette.hair
                .frame(height: FuelMetrics.Line.hairline)
        }
    }

    private func macro(_ name: String, _ grams: Int) -> some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(name)
                .fuelStyle(FuelTypography.macroLabelSmall)
                .foregroundStyle(palette.muted)

            Text(CameraCopy.grams(grams))
                .fuelStyle(FuelTypography.macroValue)
                .foregroundStyle(palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Breakdown

    private var itemList: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(CameraCopy.itemsHeading)
                .fuelStyle(FuelTypography.sectionLabel)
                .foregroundStyle(palette.muted)

            ForEach(draft.items) { item in
                itemRow(item)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, FuelMetrics.Space.s18)
    }

    private func itemRow(_ item: RecognisedItem) -> some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s14) {
            VStack(alignment: .leading, spacing: .zero) {
                // Model-written text, already capped at 120 characters at the
                // parse boundary. Plain `Text`, so there is no markup path into
                // the interface for a name that arrived from a provider.
                Text(verbatim: item.name)
                    .fuelStyle(FuelTypography.itemTitle)
                    .foregroundStyle(palette.ink)

                if let note = CameraCopy.itemNote(item.note) {
                    Text(note)
                        .fuelStyle(FuelTypography.confidence)
                        .foregroundStyle(palette.muted)
                        .padding(.top, FuelMetrics.Space.s2)
                }
            }

            Spacer(minLength: FuelMetrics.Space.s14)

            Text(LogFlowFormat.figure(item.kilocalories))
                .fuelStyle(FuelTypography.listValueSmall)
                .foregroundStyle(palette.ink)
        }
        .padding(.vertical, FuelMetrics.Space.s13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            palette.hairSoft
                .frame(height: FuelMetrics.Line.hairline)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
            Button(action: onNew) {
                Text(CameraCopy.resultNew)
                    .fuelStyle(FuelTypography.chipLabel)
                    .foregroundStyle(palette.ink)
                    .padding(.vertical, FuelMetrics.Space.s17)
                    .padding(.horizontal, FuelMetrics.Space.s20)
                    .overlay {
                        RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                            .strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                    }
                    .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
            }
            .buttonStyle(.plain)

            Button(action: onAdd) {
                Text(CameraCopy.resultAdd)
                    .fuelStyle(FuelTypography.buttonLabel)
                    .foregroundStyle(palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, FuelMetrics.Space.s17)
                    .background(palette.accentColor, in: .rect(cornerRadius: FuelMetrics.Radius.pill))
                    .contentShape(.rect(cornerRadius: FuelMetrics.Radius.pill))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.bottom, FuelMetrics.Space.s34)
    }
}

// MARK: - Chevron

/// The chevron beside the meal-label pill, as the export draws it:
/// `M1 1l3.5 3.5L8 1` in a 9×6 box — a 45° V held one unit off the left, the
/// right and the top.
///
/// A path rather than a symbol: it is the one glyph the export authors outside
/// the 20-unit box, and `chevron.down` is neither this angle nor this weight.
private struct ChevronGlyph: Shape {

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = rect.width / FuelMetrics.Line.Glyph.chevronWidth
        let inset = FuelMetrics.Line.Glyph.chevronInset * scale
        let top = rect.minY + inset
        // The V descends by exactly the distance it travels sideways.
        let drop = rect.midX - (rect.minX + inset)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + inset, y: top))
        path.addLine(to: CGPoint(x: rect.midX, y: top + drop))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: top))
        return path
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

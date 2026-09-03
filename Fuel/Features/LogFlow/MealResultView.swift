import SwiftUI

// MARK: - Meal result

/// Screens 14 and 15: what the model came back with, before any of it is
/// written down.
///
/// **One screen, drawn twice.** The export's two result frames differ in
/// three things and in nothing else: what sits above the meal-label pill — the
/// captured photo on 14, the typed sentence on 15 — the flow label top right,
/// and the heading over the breakdown. Everything from the pill down is the
/// same drawing, down to each padding. So the difference is a slot and two
/// strings, and the screen is written once.
///
/// It follows the theme rather than the camera surface — the export draws both
/// on `bg`, not on `cam`, because the estimate is done and there is no
/// viewfinder left to keep legible.
///
/// The estimate's **title is not drawn here.** Neither frame gives the result
/// a heading of its own. The title still travels in the draft and still
/// becomes the entry's name in the day list; these screens simply do not show
/// it.
///
/// Presentation only: it is handed a draft and hands back taps, so it renders
/// in a preview without a store, a client or a camera.
struct MealResultView<Lede: View>: View {

    let draft: MealResultDraft

    /// `Photo entry` or `Text entry`, top right.
    let flowLabel: String

    /// `Recognised` or `Broken down`, over the breakdown.
    let itemsHeading: String

    let onBack: () -> Void
    let onCycleLabel: () -> Void
    let onToggleFavourite: () -> Void
    let onAdjustCalories: (Int) -> Void
    let onNew: () -> Void
    let onAdd: () -> Void

    /// What the mode puts where the other mode puts its own: the thumbnail on
    /// screen 14, the quoted sentence on screen 15. It is the first thing in
    /// the scrolling column and carries its own top inset from the header.
    @ViewBuilder let lede: () -> Lede

    @Environment(\.fuelPalette) private var palette

    init(
        draft: MealResultDraft,
        flowLabel: String,
        itemsHeading: String,
        onBack: @escaping () -> Void,
        onCycleLabel: @escaping () -> Void,
        onToggleFavourite: @escaping () -> Void,
        onAdjustCalories: @escaping (Int) -> Void,
        onNew: @escaping () -> Void,
        onAdd: @escaping () -> Void,
        @ViewBuilder lede: @escaping () -> Lede
    ) {
        self.draft = draft
        self.flowLabel = flowLabel
        self.itemsHeading = itemsHeading
        self.onBack = onBack
        self.onCycleLabel = onCycleLabel
        self.onToggleFavourite = onToggleFavourite
        self.onAdjustCalories = onAdjustCalories
        self.onNew = onNew
        self.onAdd = onAdd
        self.lede = lede
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            palette.background
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: .zero) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: .zero) {
                        lede()
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
                Text(MealResultCopy.back)
                    .fuelStyle(FuelTypography.eyebrow)
                    .foregroundStyle(palette.muted)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(MealResultCopy.backLabel))

            Spacer(minLength: FuelMetrics.Space.s14)

            Text(flowLabel)
                .fuelStyle(FuelTypography.flowLabel)
                .foregroundStyle(palette.muted)
        }
        .padding(.top, FuelMetrics.Space.s22)
        .padding(.horizontal, FuelMetrics.Screen.logFlowHorizontalPadding)
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
                Text(MealResultCopy.mealLabel(draft.label))
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
        .accessibilityValue(Text(MealResultCopy.mealLabel(draft.label)))
        .accessibilityHint(Text(MealResultCopy.mealLabelHint))
        .fuelAnimation(FuelMotion.standard, value: draft.label)
    }

    private var favouritePill: some View {
        Button(action: onToggleFavourite) {
            Text(MealResultCopy.favourite(isOn: draft.isFavourite))
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
        .accessibilityLabel(Text(MealResultCopy.favouriteLabel))
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

                Text(MealResultCopy.unit)
                    .fuelStyle(FuelTypography.unit)
                    .foregroundStyle(palette.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(MealResultCopy.kilocaloriesValue(draft.kilocalories)))

            Spacer(minLength: FuelMetrics.Space.s14)

            HStack(alignment: .center, spacing: FuelMetrics.Space.s8) {
                stepper(
                    glyph: MealResultCopy.stepperDecrease,
                    label: MealResultCopy.stepperDecreaseLabel,
                    delta: -MealResultDraft.calorieStep
                )
                stepper(
                    glyph: MealResultCopy.stepperIncrease,
                    label: MealResultCopy.stepperIncreaseLabel,
                    delta: MealResultDraft.calorieStep
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
            macro(MealResultCopy.macroProtein, draft.macros.protein)
            macro(MealResultCopy.macroCarbs, draft.macros.carbs)
            macro(MealResultCopy.macroFat, draft.macros.fat)
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

            Text(MealResultCopy.grams(grams))
                .fuelStyle(FuelTypography.macroValue)
                .foregroundStyle(palette.ink)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Breakdown

    private var itemList: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(itemsHeading)
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

                if let note = MealResultCopy.itemNote(item.note) {
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
                Text(MealResultCopy.new)
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
                Text(MealResultCopy.add)
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

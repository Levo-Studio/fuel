import SwiftUI

// MARK: - Today

/// Screens 05 and 06: the day so far, against a goal or on its own.
///
/// One view for both, because the header, the day list and the add button are
/// drawn identically on the two screens. The block between the title and the
/// list is where they part, and that difference lives in `TodaySummaryView`
/// rather than in a flag here.
struct TodayView: View {

    let presentation: TodayPresentation

    let onOpenSettings: () -> Void
    let onAddEntry: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            palette.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    TodayHeader(date: presentation.date, onOpenSettings: onOpenSettings)
                        .padding(.top, FuelMetrics.Space.s26)

                    TodaySummaryView(
                        kilocalories: presentation.totals.kilocalories,
                        suffix: presentation.totalSuffix,
                        summary: presentation.summary
                    )
                    .padding(.top, FuelMetrics.Space.s34)

                    TodayDayList(groups: presentation.groups)
                        .padding(.top, listTopPadding)
                }
                .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
                // The last row would otherwise sit under the add button, which
                // floats rather than taking part in the layout.
                .padding(.bottom, FuelMetrics.Control.addButton + FuelMetrics.Control.addButtonBottomInset)
            }
            .scrollBounceBehavior(.basedOnSize)

            TodayAddButton(action: onAddEntry)
                .padding(.trailing, FuelMetrics.Control.addButtonTrailingInset)
                .padding(.bottom, FuelMetrics.Control.addButtonBottomInset)
        }
    }

    /// The gap above the day list, and one of the two places the screens differ
    /// by a value rather than by a shape: goal mode drops 32 to the first
    /// heading, count-only 34.
    private var listTopPadding: CGFloat {
        presentation.showsRing ? FuelMetrics.Space.s32 : FuelMetrics.Space.s34
    }
}

// MARK: - Header

/// The date, the title, and the settings control opposite them.
private struct TodayHeader: View {

    let date: Date
    let onOpenSettings: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: .zero) {
                Text(TodayFormat.eyebrowDate(date))
                    .fuelStyle(FuelTypography.meta)
                    .foregroundStyle(palette.muted)

                Text(TodayCopy.title)
                    .fuelStyle(FuelTypography.screenTitle)
                    .foregroundStyle(palette.ink)
            }

            Spacer(minLength: .zero)

            Button(action: onOpenSettings) {
                Text(TodayCopy.settingsGlyph)
                    .fuelStyle(FuelTypography.iconGlyph)
                    .foregroundStyle(palette.muted)
                    .frame(
                        width: FuelMetrics.Control.circleButton,
                        height: FuelMetrics.Control.circleButton
                    )
                    .overlay {
                        Circle().strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(TodayCopy.settingsLabel))
        }
    }
}

// MARK: - Add button

/// The accent-filled button floating over the day list — the one place either
/// mode offers to log something.
private struct TodayAddButton: View {

    let action: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .resizable()
                .scaledToFit()
                // The export draws the glyph as a 20×20 path. Its 1.6 stroke is
                // not in the design layer, so the symbol's own weight stands in
                // rather than a number invented here.
                .frame(width: FuelMetrics.Space.s20, height: FuelMetrics.Space.s20)
                .foregroundStyle(palette.onAccent)
                .frame(
                    width: FuelMetrics.Control.addButton,
                    height: FuelMetrics.Control.addButton
                )
                .background(palette.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(TodayCopy.addLabel))
    }
}

// MARK: - Previews

#Preview("Goal mode") {
    TodayView(
        presentation: TodayPresentation(
            entries: TodayPreviewData.day,
            mode: .goal(.default),
            date: TodayPreviewData.date
        ),
        onOpenSettings: {},
        onAddEntry: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

#Preview("Count only") {
    TodayView(
        presentation: TodayPresentation(
            entries: TodayPreviewData.day,
            mode: .countOnly,
            date: TodayPreviewData.date
        ),
        onOpenSettings: {},
        onAddEntry: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
}

/// The day the export draws, so a preview shows the screen the design shows.
private enum TodayPreviewData {

    static let date = Date(timeIntervalSince1970: 1_756_771_200)

    static let day: [NutritionEntry] = [
        NutritionEntry(
            title: "Oats with skyr",
            kilocalories: 420,
            macros: MacroTotals(protein: 30, carbs: 55, fat: 9),
            loggedAt: date.addingTimeInterval(29_640),
            source: .photo,
            label: .breakfast
        ),
        NutritionEntry(
            title: "Chicken bowl, rice",
            kilocalories: 680,
            macros: MacroTotals(protein: 52, carbs: 78, fat: 21),
            loggedAt: date.addingTimeInterval(45_600),
            source: .text,
            label: .lunch
        ),
        NutritionEntry(
            title: "Espresso, banana",
            kilocalories: 110,
            macros: MacroTotals(protein: 2, carbs: 24, fat: 1),
            loggedAt: date.addingTimeInterval(54_300),
            source: .recent,
            label: .snack
        ),
        NutritionEntry(
            title: "Salmon with polenta",
            kilocalories: 430,
            macros: MacroTotals(protein: 34, carbs: 15, fat: 17),
            loggedAt: date.addingTimeInterval(69_600),
            source: .photo,
            label: .dinner
        ),
    ]
}

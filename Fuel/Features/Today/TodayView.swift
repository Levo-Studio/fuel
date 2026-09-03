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

    /// What stands in the day list's place while the day has no entries. The
    /// export draws nothing there, and a first run showed the header over five
    /// hundred points of empty, which reads as a fault rather than as a
    /// beginning.
    let gettingStarted: TodayGettingStarted

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

                    dayOrEmptyState
                        .padding(.top, listTopPadding)
                }
                .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
                // The last row has to clear the whole fade band, not just the
                // button: a row scrolled to rest inside the band would be
                // legible at the top of it and gone at the bottom.
                .padding(.bottom, FuelMetrics.ListFade.height)
            }
            .scrollBounceBehavior(.basedOnSize)

            TodayListFade()

            TodayAddButton(action: onAddEntry)
                .padding(.trailing, FuelMetrics.Control.addButtonTrailingInset)
                .padding(.bottom, FuelMetrics.Control.addButtonBottomInset)
        }
    }

    /// The day, or what stands in for it.
    ///
    /// Three states rather than two. A day with entries is the drawn one; an
    /// empty day gets the checklist, and an empty day with nothing left to
    /// suggest gets a single line, because a list of four permanent ticks is
    /// not a beginning.
    @ViewBuilder private var dayOrEmptyState: some View {
        if presentation.hasEntries {
            TodayDayList(groups: presentation.groups)
        } else if gettingStarted.isComplete {
            TodayEmptyDayNote()
        } else {
            TodayGettingStartedView(
                checklist: gettingStarted,
                onOpenSettings: onOpenSettings,
                onAddEntry: onAddEntry
            )
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
                // A symbol stands in for a character the bundled face cannot
                // draw. The export sets this control's glyph as the text `\u{2699}`
                // and the browser satisfied it from a fallback font; Plus
                // Jakarta Sans has no gear, so the drawn markup renders as
                // tofu on the device. `FuelMetrics.Line.Glyph`'s stroke weights
                // do not apply to a symbol either — SF draws its own. The drawn
                // 14pt size, the 34pt circle, its hairline and its colour are
                // unchanged.
                Image(systemName: "gearshape")
                    .fuelStyle(FuelTypography.iconGlyph)
                    .foregroundStyle(palette.muted)
                    .frame(
                        width: FuelMetrics.Control.circleButton,
                        height: FuelMetrics.Control.circleButton
                    )
                    .overlay {
                        Circle().strokeBorder(palette.hair, lineWidth: FuelMetrics.Line.hairline)
                    }
                    // The drawn circle is 34 and a finger is 44. The larger
                    // frame grows the region that answers around it, and the
                    // negative padding gives the layout its 34 back — so the
                    // circle keeps the size and the position the export puts
                    // it in, and the header row is laid out as though nothing
                    // here were bigger than what is drawn.
                    .frame(
                        width: FuelMetrics.Control.minimumHitTarget,
                        height: FuelMetrics.Control.minimumHitTarget
                    )
                    .contentShape(Rectangle())
                    .padding(
                        -FuelMetrics.Control.hitTargetOverhang(
                            around: FuelMetrics.Control.circleButton
                        )
                    )
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
            TodayPlusGlyph()
                .stroke(
                    palette.onAccent,
                    style: StrokeStyle(lineWidth: FuelMetrics.Line.Glyph.plus, lineCap: .round)
                )
                .frame(
                    width: FuelMetrics.Line.Glyph.viewBox,
                    height: FuelMetrics.Line.Glyph.viewBox
                )
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

/// The plus on the add button, as the export draws it: `M10 3v14M3 10h14` in a
/// 20-unit box — two arms crossing at the centre, each held 3 off the edge.
///
/// Drawn as a path rather than taken from a symbol font: `plus` is butt-capped
/// and its arms are a different length against the box, so it is the drawing
/// next to it that would look wrong, not this.
private struct TodayPlusGlyph: Shape {

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = rect.width / FuelMetrics.Line.Glyph.viewBox
        let inset = FuelMetrics.Space.s3 * scale

        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        return path
    }
}

// MARK: - List fade

/// The band that takes the day list out under the add button.
///
/// Behind the button and in front of the list, and deliberately not
/// hit-testable: it covers the last rows, and a row under it still has to be
/// reachable.
private struct TodayListFade: View {

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: palette.background, location: .zero),
                Gradient.Stop(color: palette.background, location: FuelMetrics.ListFade.opaqueStop),
                Gradient.Stop(color: palette.background.opacity(.zero), location: 1),
            ],
            startPoint: .bottom,
            endPoint: .top
        )
        .frame(height: FuelMetrics.ListFade.height)
        .allowsHitTesting(false)
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
        gettingStarted: TodayPreviewData.finishedChecklist,
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
        gettingStarted: TodayPreviewData.finishedChecklist,
        onOpenSettings: {},
        onAddEntry: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .green))
}

#Preview("First run") {
    TodayView(
        presentation: TodayPresentation(
            entries: [],
            mode: .countOnly,
            date: TodayPreviewData.date
        ),
        gettingStarted: TodayPreviewData.firstRunChecklist,
        onOpenSettings: {},
        onAddEntry: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

#Preview("Empty day, nothing left to suggest") {
    TodayView(
        presentation: TodayPresentation(
            entries: [],
            mode: .goal(.default),
            date: TodayPreviewData.date
        ),
        gettingStarted: TodayPreviewData.finishedChecklist,
        onOpenSettings: {},
        onAddEntry: {}
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .mono))
}

/// The day the export draws, so a preview shows the screen the design shows.
private enum TodayPreviewData {

    /// A first run: a key was asked for before Today was ever reached, so that
    /// row is the one thing already done.
    static let firstRunChecklist = TodayGettingStarted(
        hasProviderKey: true,
        isGoalMode: false,
        hasCustomisedAppearance: false,
        hasLoggedMeal: false
    )

    /// Everything answered, which is what a day with entries in it has by
    /// definition — the last row asks for the first meal.
    static let finishedChecklist = TodayGettingStarted(
        hasProviderKey: true,
        isGoalMode: true,
        hasCustomisedAppearance: true,
        hasLoggedMeal: true
    )

    /// Local midnight, because the rows print `TimeZone.current`. Anchoring to
    /// UTC would slide every drawn time by the machine's offset and the
    /// preview would stop being the day the export draws.
    static let date: Date = {
        let reference = Date(timeIntervalSince1970: 1_756_771_200)
        return Calendar.current.startOfDay(for: reference)
    }()

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

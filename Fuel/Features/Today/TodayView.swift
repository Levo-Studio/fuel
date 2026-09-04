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

    /// Which day is being shown and which days it can move to.
    ///
    /// **Owner's instruction, and a deviation from the export**: screens 05 and
    /// 06 draw one day and no navigation of any kind. What the drawn header
    /// gains is stated where it is drawn, in `TodayHeader`.
    let navigation: TodayDayNavigation

    /// Whether the day now showing is earlier than the one it replaced. It
    /// decides which way the change travels — see `FuelMotion.DayTravel`, which
    /// is where the reason all three controls have to share one answer is
    /// written down.
    let isTravellingBackward: Bool

    /// What stands in the day list's place while the day has no entries. The
    /// export draws nothing there, and a first run showed the header over five
    /// hundred points of empty, which reads as a fault rather than as a
    /// beginning.
    let gettingStarted: TodayGettingStarted

    let onOpenSettings: () -> Void
    let onAddEntry: () -> Void

    /// A meal in the list was tapped, by the identity its hand-off value
    /// carries.
    let onOpenMeal: (UUID) -> Void

    let onShowPreviousDay: () -> Void
    let onShowNextDay: () -> Void

    /// A day chosen in the picker the date opens.
    let onShowDay: (Date) -> Void

    /// Whether that picker is up. Interface state, so it is held here rather
    /// than on the shell model, the way `RootShell` holds its confirmation: a
    /// sheet is a thing the interface is showing, not a thing the day is doing.
    @State private var isPickingDay = false

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            palette.background
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .zero) {
                    TodayHeader(
                        date: presentation.date,
                        navigation: navigation,
                        isTravellingBackward: isTravellingBackward,
                        onOpenSettings: onOpenSettings,
                        onShowPreviousDay: onShowPreviousDay,
                        onShowNextDay: onShowNextDay,
                        onPickDay: { isPickingDay = true }
                    )
                    .padding(.top, FuelMetrics.Space.s26)

                    day
                }
                .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
                // The last row has to clear the whole fade band, not just the
                // button: a row scrolled to rest inside the band would be
                // legible at the top of it and gone at the bottom.
                .padding(.bottom, FuelMetrics.ListFade.height)
            }
            .fuelScrolling()

            FuelListFade()

            TodayAddButton(action: onAddEntry)
                .padding(.trailing, FuelMetrics.Control.addButtonTrailingInset)
                .padding(.bottom, FuelMetrics.Control.addButtonBottomInset)
        }
        // The second of the three ways into the browse. It sits on the whole
        // screen rather than on the list, so a day with two entries on it can
        // be swiped off in the empty space below them.
        .fuelDaySwipe { direction in
            switch direction {
            case .earlier: onShowPreviousDay()
            case .later: onShowNextDay()
            }
        }
        .sheet(isPresented: $isPickingDay) {
            TodayDayPicker(
                navigation: navigation,
                onSelect: { day in
                    onShowDay(day)
                    isPickingDay = false
                },
                onDone: { isPickingDay = false }
            )
        }
    }

    /// Everything under the header, which is what a day change replaces.
    ///
    /// **In a `ZStack` rather than in the enclosing `VStack`**, and that is not
    /// a style choice: a transition keeps both days alive while it runs, and in
    /// a vertical stack the arriving day would be laid out *under* the leaving
    /// one and the screen would double in height for the length of the travel.
    /// Overlaid, the two occupy one slot and slide across it.
    private var day: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: .zero) {
                TodaySummaryView(
                    kilocalories: presentation.totals.kilocalories,
                    suffix: presentation.totalSuffix,
                    summary: presentation.summary
                )
                .padding(.top, FuelMetrics.Space.s34)

                dayOrEmptyState
                    .padding(.top, listTopPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(presentation.date)
            .fuelDayTransition(isBackward: isTravellingBackward)
        }
        .fuelAnimation(FuelMotion.dayChange, value: presentation.date)
    }

    /// The day, the checklist that stands in for it at the beginning, or the
    /// line a past day with nothing on it carries.
    ///
    /// The checklist is offered on an empty day *and only until the first meal
    /// is logged* — after that it is gone for good, and a later empty day is
    /// drawn as it always was: the header, the summary, and nothing under it.
    ///
    /// **The checklist is never offered on a past day**, however empty that day
    /// is and however new the user. It says "here are three things to set up",
    /// which is about the app rather than about a day, and a Tuesday in March
    /// is not where that belongs. What a past day with nothing on it gets is
    /// its own line, and the two are not the same statement: today with nothing
    /// on it *yet* is a day still running, which is why the export's own
    /// nothing is still the right answer there.
    @ViewBuilder private var dayOrEmptyState: some View {
        if presentation.hasEntries {
            TodayDayList(groups: presentation.groups, onSelect: onOpenMeal)
        } else if navigation.isToday {
            if gettingStarted.isOffered {
                TodayGettingStartedView(
                    checklist: gettingStarted,
                    onOpenSettings: onOpenSettings,
                    onAddEntry: onAddEntry
                )
            }
        } else {
            TodayEmptyPastDay()
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

/// The date, the title, the two day arrows, and the settings control.
///
/// **The export draws none of the navigation**, and what stands here is the
/// owner's instruction. What the export *does* draw is unmoved, which was the
/// condition: the eyebrow and the title sit on the leading edge in the type and
/// at the position screens 05 and 06 give them, and the gear keeps the trailing
/// edge, its drawn 34pt circle, its hairline and its colour. The arrows go in
/// the space between them, which the export leaves empty.
///
/// They are drawn as the same 34pt hairline circle rather than as a new mark.
/// That circle is already this app's header control — the gear here, the back
/// control on the meal screen, the gallery control on screen 07 — so three of
/// them in a row is the drawn vocabulary repeated rather than a fourth thing
/// invented. It also settles the touch targets exactly: a 34pt circle at a
/// `Space.s10` gap puts the centres 44 apart, so the three 44pt regions abut
/// and none of them overlaps its neighbour.
///
/// The title block takes all the width the controls leave, so the two days a
/// change keeps alive can cross it without the arrows or the gear moving for
/// the wider of them.
private struct TodayHeader: View {

    let date: Date
    let navigation: TodayDayNavigation
    let isTravellingBackward: Bool
    let onOpenSettings: () -> Void
    let onShowPreviousDay: () -> Void
    let onShowNextDay: () -> Void
    let onPickDay: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: FuelMetrics.Space.s10) {
            title
                .frame(maxWidth: .infinity, alignment: .leading)
                // The leaving day travels sideways out of this slot, and
                // without this it would run under the arrows on its way.
                .clipped()

            TodayDayArrow(
                direction: .previous,
                isEnabled: navigation.canGoBackward,
                action: onShowPreviousDay
            )

            TodayDayArrow(
                direction: .next,
                isEnabled: navigation.canGoForward,
                action: onShowNextDay
            )

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
            .buttonStyle(FuelPressButtonStyle())
            .accessibilityLabel(Text(TodayCopy.settingsLabel))
        }
    }

    /// The drawn eyebrow and the drawn title, now the third way into the
    /// browse: tapping them opens the day picker.
    ///
    /// **Nothing about the drawing changed.** The export puts no control here
    /// and none is added — no chevron, no underline, no fill. What is under the
    /// finger is the block itself, which is what the instruction asks for; the
    /// press feedback every control in this app has is the only sign it answers
    /// at all, and it costs no drawn geometry.
    ///
    /// The two days a change keeps alive are overlaid rather than stacked, for
    /// the reason the body below them is: side by side they would widen the
    /// header and push the arrows out of the place the export leaves them.
    private var title: some View {
        ZStack(alignment: .leading) {
            Button(action: onPickDay) {
                VStack(alignment: .leading, spacing: .zero) {
                    Text(TodayFormat.eyebrowDate(date))
                        .fuelStyle(FuelTypography.meta)
                        .foregroundStyle(palette.muted)

                    // One line, because the alternative is worse in the one way
                    // this feature was told not to be. The drawn word is
                    // `Heute`, and the longest thing that now stands in its
                    // place is a weekday at the largest accessibility size; if
                    // that wrapped, the header would grow and push the totals
                    // and the whole day list down. A title that truncates is a
                    // title the eyebrow above it has already spelled out.
                    Text(TodayCopy.dayTitle(navigation.title))
                        .fuelStyle(FuelTypography.screenTitle)
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                }
                // A floor, not the thing doing the work: 11.5pt over 25pt is
                // already past a fingertip, and this only asserts it. It cannot
                // move the drawn block, because a frame that is never reached
                // changes no layout.
                .frame(minHeight: FuelMetrics.Control.minimumHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(FuelPressButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(Text(TodayCopy.dayPickerHint))
            .id(date)
            .fuelDayTransition(isBackward: isTravellingBackward)
        }
        .fuelAnimation(FuelMotion.dayChange, value: date)
    }
}

// MARK: - Day arrows

/// One of the two arrows in the header, drawn as the gear's own circle.
///
/// **Disabled rather than absent at a bound**, and the forward arrow reaches
/// one every time the user comes back to today. Leaving it out would move the
/// back arrow into its place and then move it out again on the next swipe, and
/// the whole condition on this feature is that the header does not shift; a
/// control that vanishes is also a control the user cannot ask why about. Drawn
/// disabled, it says the edge is there and that this is where it is.
///
/// Both disabled tones are palette values a lighter step down from the enabled
/// ones — `hair2` under `muted` for the glyph, `hairSoft` under `hair` for the
/// ring — rather than an opacity applied to the enabled pair.
private struct TodayDayArrow: View {

    enum Direction {
        case previous
        case next
    }

    let direction: Direction
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Button(action: action) {
            // A symbol stands in, the way the gear beside it does and for the
            // same reason: the bundled faces draw no arrow, and the one chevron
            // the export does draw is a path authored in a 9×6 box for the meal
            // pill on screen 14 — a different mark at a different angle, not
            // this one rotated. `FuelMetrics.Line.Glyph`'s stroke weights do not
            // apply to a symbol; SF draws its own. The 14pt glyph size, the 34pt
            // circle, its hairline and its colour are the gear's, unchanged.
            Image(systemName: direction == .previous ? "chevron.left" : "chevron.right")
                .fuelStyle(FuelTypography.iconGlyph)
                .foregroundStyle(isEnabled ? palette.muted : palette.hair2)
                .frame(
                    width: FuelMetrics.Control.circleButton,
                    height: FuelMetrics.Control.circleButton
                )
                .overlay {
                    Circle().strokeBorder(
                        isEnabled ? palette.hair : palette.hairSoft,
                        lineWidth: FuelMetrics.Line.hairline
                    )
                }
                // The gear's own trick: the region that answers grows to 44 and
                // the negative padding gives the layout its 34 back, so the
                // circle keeps its drawn size and the row is laid out as though
                // nothing here were bigger than what is drawn.
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
        .buttonStyle(FuelPressButtonStyle())
        .disabled(!isEnabled)
        // A control reacting rather than a day arriving: the arrow goes dead
        // the moment the walk reaches its end, and a step of colour with no
        // curve under it reads as a redraw.
        .fuelAnimation(FuelMotion.standard, value: isEnabled)
        .accessibilityLabel(
            Text(direction == .previous ? TodayCopy.previousDayLabel : TodayCopy.nextDayLabel)
        )
    }
}

// MARK: - A past day with nothing on it

/// One line, where the day list would be.
///
/// **Not the get-started checklist**, which is the other thing that stands in
/// this place and answers a different question. The checklist is about the app
/// being new; this is about a day being empty, and a Tuesday in March with
/// nothing on it is not a user who has not started — it is a day nobody logged.
///
/// The line is `monoNote`, muted: the type screen 17 draws its privacy footer
/// in, which is this app's existing shape for a quiet statement of fact. No new
/// style, no new colour, and nothing framed — a heading and a rule over one
/// sentence would make more furniture than the fact deserves.
private struct TodayEmptyPastDay: View {

    @Environment(\.fuelPalette) private var palette

    var body: some View {
        Text(TodayCopy.emptyPastDay)
            .fuelStyle(FuelTypography.monoNote)
            .foregroundStyle(palette.muted)
    }
}

// MARK: - Day picker

/// The third way into the browse: a calendar, for jumping further back than a
/// swipe at a time is worth.
///
/// **The export draws no such screen**, and this does not invent one. The grid
/// is the system's `DatePicker`, standing in the way the SF symbols elsewhere
/// on this screen do and for the same reason — a calendar month is a control
/// the design does not draw, and a hand-built grid would be a page of invented
/// geometry where a stand-in is one line. It is tinted to the accent and set on
/// the app's own background, and the sheet's heading and its `Done` are
/// Settings' own, at Settings' own type and colour.
///
/// The range is `TodayDayNavigation`'s, so the picker cannot offer a day the
/// arrows and the swipe refuse: tomorrow is not selectable, and neither is
/// anything before the first meal ever logged.
private struct TodayDayPicker: View {

    let navigation: TodayDayNavigation
    let onSelect: (Date) -> Void
    let onDone: () -> Void

    /// The picker writes here, and the change is what jumps the day — selecting
    /// a date *is* the action, so there is no second control to confirm it.
    @State private var day: Date

    @Environment(\.fuelPalette) private var palette

    init(navigation: TodayDayNavigation, onSelect: @escaping (Date) -> Void, onDone: @escaping () -> Void) {
        self.navigation = navigation
        self.onSelect = onSelect
        self.onDone = onDone
        _day = State(initialValue: navigation.day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            // Settings' header, verbatim: the screen title on the leading edge
            // and `Done` opposite it in `flowLabel`, muted.
            HStack(alignment: .center) {
                Text(TodayCopy.dayPickerTitle)
                    .fuelStyle(FuelTypography.screenTitle)
                    .foregroundStyle(palette.ink)

                Spacer(minLength: FuelMetrics.Space.s12)

                Button(action: onDone) {
                    Text(TodayCopy.dayPickerDone)
                        .fuelStyle(FuelTypography.flowLabel)
                        .foregroundStyle(palette.muted)
                        .frame(minHeight: FuelMetrics.Control.minimumHitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FuelPressButtonStyle())
            }

            DatePicker(
                TodayCopy.dayPickerTitle,
                selection: $day,
                in: navigation.browsableDays,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(palette.accentColor)
            .padding(.top, FuelMetrics.Space.s20)

            Spacer(minLength: .zero)
        }
        .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        .padding(.top, FuelMetrics.Space.s26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
        .presentationBackground(palette.background)
        .onChange(of: day) { _, chosen in
            onSelect(chosen)
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
        .buttonStyle(FuelPressButtonStyle())
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

// MARK: - Previews

#Preview("Goal mode") {
    TodayView(
        presentation: TodayPresentation(
            entries: TodayPreviewData.day,
            mode: .goal(.default),
            date: TodayPreviewData.date
        ),
        navigation: TodayPreviewData.navigation(showing: TodayPreviewData.date),
        isTravellingBackward: false,
        gettingStarted: TodayPreviewData.retiredChecklist,
        onOpenSettings: {},
        onAddEntry: {},
        onOpenMeal: { _ in },
        onShowPreviousDay: {},
        onShowNextDay: {},
        onShowDay: { _ in }
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
        navigation: TodayPreviewData.navigation(showing: TodayPreviewData.date),
        isTravellingBackward: false,
        gettingStarted: TodayPreviewData.retiredChecklist,
        onOpenSettings: {},
        onAddEntry: {},
        onOpenMeal: { _ in },
        onShowPreviousDay: {},
        onShowNextDay: {},
        onShowDay: { _ in }
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
        navigation: TodayPreviewData.navigation(showing: TodayPreviewData.date),
        isTravellingBackward: false,
        gettingStarted: TodayPreviewData.firstRunChecklist,
        onOpenSettings: {},
        onAddEntry: {},
        onOpenMeal: { _ in },
        onShowPreviousDay: {},
        onShowNextDay: {},
        onShowDay: { _ in }
    )
    .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

#Preview("Empty day, after the first meal") {
    TodayView(
        presentation: TodayPresentation(
            entries: [],
            mode: .goal(.default),
            date: TodayPreviewData.date
        ),
        navigation: TodayPreviewData.navigation(showing: TodayPreviewData.date),
        isTravellingBackward: false,
        gettingStarted: TodayPreviewData.retiredChecklist,
        onOpenSettings: {},
        onAddEntry: {},
        onOpenMeal: { _ in },
        onShowPreviousDay: {},
        onShowNextDay: {},
        onShowDay: { _ in }
    )
    .environment(\.fuelPalette, FuelPalette(theme: .light, accent: .mono))
}

/// A past day nobody logged to, which is neither the day list nor the
/// checklist: the back arrow is live, the forward arrow is dead, and the title
/// says which day rather than `Today`.
#Preview("A past day with nothing on it") {
    TodayView(
        presentation: TodayPresentation(
            entries: [],
            mode: .goal(.default),
            date: TodayPreviewData.pastDate
        ),
        navigation: TodayPreviewData.navigation(showing: TodayPreviewData.pastDate),
        isTravellingBackward: true,
        gettingStarted: TodayPreviewData.retiredChecklist,
        onOpenSettings: {},
        onAddEntry: {},
        onOpenMeal: { _ in },
        onShowPreviousDay: {},
        onShowNextDay: {},
        onShowDay: { _ in }
    )
    .environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
}

/// The day the export draws, so a preview shows the screen the design shows.
private enum TodayPreviewData {

    /// A first run: onboarding is answered, nothing is customised and nothing
    /// has been logged.
    static let firstRunChecklist = TodayGettingStarted(
        hasChosenTheme: false,
        hasChosenAccent: false,
        hasLoggedMeal: false
    )

    /// A user who has logged before, so there is no checklist left to offer.
    /// A day with entries in it is in this state by definition.
    static let retiredChecklist = TodayGettingStarted(
        hasChosenTheme: true,
        hasChosenAccent: true,
        hasLoggedMeal: true
    )

    /// Local midnight, because the rows print `TimeZone.current`. Anchoring to
    /// UTC would slide every drawn time by the machine's offset and the
    /// preview would stop being the day the export draws.
    static let date: Date = {
        let reference = Date(timeIntervalSince1970: 1_756_771_200)
        return Calendar.current.startOfDay(for: reference)
    }()

    /// Four days before it, so both a `Yesterday` and a weekday title are a
    /// step away and the walk back has somewhere to go.
    static let pastDate = Calendar.current.date(byAdding: .day, value: -4, to: date) ?? date

    /// A browse whose day is the one the preview draws and whose history
    /// reaches a fortnight behind it, so the arrows show both of their states:
    /// the forward one dead on `date`, both live on `pastDate`.
    static func navigation(showing day: Date) -> TodayDayNavigation {
        TodayDayNavigation(
            showing: day,
            now: date,
            firstEntry: Calendar.current.date(byAdding: .day, value: -14, to: date),
            calendar: .current
        )
    }

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

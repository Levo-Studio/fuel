import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Fixtures

/// A moment on the current day, so a placeholder built from it is on the day the
/// shell calls today.
private nonisolated func today(at hour: Int, _ minute: Int = 0) -> Date {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: Date())
    return calendar.date(byAdding: DateComponents(hour: hour, minute: minute), to: start) ?? start
}

/// The row as Today would offer it: on today, on a day with nothing on it, with
/// the checklist already retired. Every case that is *not* that says so by
/// naming the answer it changes.
private nonisolated func placeholder(
    isToday: Bool = true,
    hasEntries: Bool = false,
    isGettingStartedOffered: Bool = false,
    at moment: Date
) -> TodayEmptyDay? {
    TodayEmptyDay(
        isToday: isToday,
        hasEntries: hasEntries,
        isGettingStartedOffered: isGettingStartedOffered,
        now: moment,
        calendar: .current
    )
}

// MARK: - Which days get it

/// The three exclusions, one at a time.
@Suite("Today · which days carry the empty day's row")
struct TodayEmptyDayOfferTests {

    @Test("today with nothing on it and the checklist retired carries the row")
    func offered() {
        #expect(placeholder(at: today(at: 9, 41)) != nil)
    }

    /// A past day is `TodayEmptyPastDay`'s. The label would describe now rather
    /// than that day, and the log flow writes to the current day whatever day
    /// Today is showing.
    @Test("a past day carries no row, however empty it is")
    func notOnAPastDay() {
        #expect(placeholder(isToday: false, at: today(at: 9, 41)) == nil)
    }

    @Test("a day with something on it carries no row")
    func notOnADayWithEntries() {
        #expect(placeholder(hasEntries: true, at: today(at: 9, 41)) == nil)
    }

    /// The collision on a brand-new user's first day: both would stand in the
    /// same place, and the checklist already carries `Log your first meal`.
    @Test("the get-started checklist keeps the place while it is offered")
    func theChecklistWins() {
        #expect(placeholder(isGettingStartedOffered: true, at: today(at: 9, 41)) == nil)
    }

    /// The two hand over at one moment and never overlap: the first logged meal
    /// retires the checklist, and that is the same event that takes the row off
    /// the day it was logged on.
    @Test("the checklist and the row are never both offered")
    func neverBothAtOnce() {
        let firstRun = TodayGettingStarted(
            hasChosenTheme: false,
            hasChosenAccent: false,
            hasLoggedMeal: false
        )
        let retired = TodayGettingStarted(
            hasChosenTheme: false,
            hasChosenAccent: false,
            hasLoggedMeal: true
        )

        #expect(firstRun.isOffered)
        #expect(placeholder(isGettingStartedOffered: firstRun.isOffered, at: today(at: 9)) == nil)

        #expect(retired.isOffered == false)
        #expect(placeholder(isGettingStartedOffered: retired.isOffered, at: today(at: 9)) != nil)
    }
}

// MARK: - What the heading says

/// The heading names the meal a real entry would get, which is not the same
/// thing as the meal whose window the clock is inside.
@Suite("Today · what the empty day's heading names")
struct TodayEmptyDayLabelTests {

    /// The rule's own answer at every hour of an empty day. The afternoon is the
    /// one worth reading twice: `15:00 – 17:59` is `Lunch`, not `Snack`, because
    /// lunch's reach runs through a gap the day never used — the case
    /// `design/Fuel Design Notes.md` says the rule exists for.
    @Test(
        "the heading is the label the rule gives at that hour",
        arguments: [
            (0, MealLabel.snack), (2, .snack), (3, .snack),
            (4, .breakfast), (8, .breakfast), (10, .breakfast),
            (11, .lunch), (14, .lunch), (15, .lunch), (16, .lunch), (17, .lunch),
            (18, .dinner), (20, .dinner), (22, .dinner), (23, .dinner),
        ]
    )
    func labelByHour(hour: Int, expected: MealLabel) {
        #expect(placeholder(at: today(at: hour, 30))?.label == expected)
    }

    /// The heading the owner did not name, and the reason it has to be reachable:
    /// the small hours claim nothing, so a row offered at 02:00 says `Snack`
    /// rather than promising a breakfast the store would not file.
    @Test("the small hours are a snack, so the heading can read Snack")
    func snackIsReachable() {
        #expect(placeholder(at: today(at: 2, 15))?.label == .snack)
    }

    /// **The promise, checked against the thing that keeps it.** The heading is
    /// worthless unless a meal logged at the same moment is filed under the same
    /// name, so this asks the store rather than the rule: it logs one meal into
    /// an otherwise empty day and reads back the label the store wrote.
    @MainActor
    @Test("a meal logged at that moment is filed under the heading's own label", arguments: 0..<24)
    func headingMatchesWhatTheStoreFiles(hour: Int) throws {
        let moment = today(at: hour, 30)
        let promised = try #require(placeholder(at: moment)?.label)

        let store = try FuelStore(inMemory: true)
        try store.log(
            title: "One meal",
            kilocalories: 400,
            macros: MacroTotals(protein: 20, carbs: 40, fat: 10),
            loggedAt: moment,
            source: .text
        )

        let filed = try #require(store.nutritionEntries(on: moment).first?.label)
        #expect(
            promised == filed,
            "the heading promised \(promised) at \(hour):30 and the store filed \(filed)"
        )
    }
}

// MARK: - The shell

/// What the shell offers, and what it stops offering, with a real store under
/// it. Nothing here reaches a provider, a camera or a Keychain.
@MainActor
@Suite("Today · the empty day's row through the shell")
struct TodayEmptyDayShellTests {

    // MARK: - Fixtures

    private func makePreferences() -> SettingsPreferences {
        let suite = "apps.levo-studio.Fuel.tests.emptyday.\(UUID().uuidString)"
        return SettingsPreferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func makeModel(store: FuelStore) -> RootShellModel {
        RootShellModel(
            store: store,
            validator: UnusedValidator(),
            preferences: makePreferences(),
            makeCameraLog: { store, provider in
                CameraLogModel(
                    store: store,
                    client: UnusedEstimator(),
                    camera: CountingCamera(),
                    keys: StoredKey(),
                    provider: provider
                )
            },
            makeTextLog: { store, provider in
                TextLogModel(
                    store: store,
                    client: UnusedEstimator(),
                    keys: StoredKey(),
                    provider: provider,
                    pace: {}
                )
            }
        )
    }

    /// Onboarding answered and nothing ever logged: the state the checklist
    /// belongs to.
    private func makeFirstRunStore() throws -> FuelStore {
        let store = try FuelStore(inMemory: true)
        try store.setCountingMode(.goal(.default))
        return store
    }

    /// Onboarding answered and one meal some days back, so the checklist is
    /// retired and today is empty.
    private func makeReturningStore() throws -> FuelStore {
        let store = try makeFirstRunStore()
        let start = store.calendar.startOfDay(for: Date())
        let earlier = store.calendar.date(byAdding: .day, value: -3, to: start) ?? start
        try store.log(
            title: "Oats with skyr",
            kilocalories: 420,
            macros: MacroTotals(protein: 30, carbs: 55, fat: 9),
            loggedAt: earlier.addingTimeInterval(29_640),
            source: .photo
        )
        return store
    }

    // MARK: - Offered

    @Test("an empty day offers the row once the checklist is retired")
    func emptyDayOffersIt() throws {
        let model = makeModel(store: try makeReturningStore())

        #expect(model.today.hasEntries == false)
        #expect(model.gettingStarted.isOffered == false)
        #expect(model.emptyDay != nil)
    }

    @Test("a first run offers the checklist and not the row")
    func firstRunOffersTheChecklist() throws {
        let model = makeModel(store: try makeFirstRunStore())

        #expect(model.gettingStarted.isOffered)
        #expect(model.emptyDay == nil)
    }

    /// The row opens no route of its own: what it is given is the plus's
    /// destination, and it works from the state the row is drawn in.
    @Test("the row's destination is the plus's, and it opens the log flow")
    func theRouteOpensTheLogFlow() throws {
        let model = makeModel(store: try makeReturningStore())
        #expect(model.emptyDay != nil)
        #expect(model.destination == nil)

        model.openLogFlow()

        #expect(model.destination == .logFlow)
    }

    // MARK: - Gone

    /// The owner's own words: the moment the first meal is logged it is gone.
    @Test("the first meal of the day takes the row away")
    func aLoggedMealRetiresIt() throws {
        let store = try makeReturningStore()
        let model = makeModel(store: store)
        #expect(model.emptyDay != nil)

        model.openLogFlow()
        try store.log(
            title: "Chicken bowl, rice",
            kilocalories: 680,
            macros: MacroTotals(protein: 52, carbs: 78, fat: 21),
            loggedAt: Date(),
            source: .text
        )
        model.dismissDestinationAfterLogging()

        #expect(model.today.hasEntries)
        #expect(model.emptyDay == nil)
    }

    /// A swipe off today is what makes this worth its own state rather than
    /// riding on the checklist's refresh, which a day change deliberately skips.
    @Test("stepping back to an empty past day takes the row away, and coming back returns it")
    func aPastDayLosesIt() throws {
        let model = makeModel(store: try makeReturningStore())
        #expect(model.emptyDay != nil)

        model.showPreviousDay()
        #expect(model.dayNavigation.isToday == false)
        #expect(model.today.hasEntries == false)
        #expect(model.emptyDay == nil)

        model.showNextDay()
        #expect(model.dayNavigation.isToday)
        #expect(model.emptyDay != nil)
    }

    // MARK: - It is not an entry

    /// Nothing the row draws reaches the day: the totals, the ring and the three
    /// macro figures read exactly what an empty day reads without it.
    @Test("the row changes no total, no ring and no macro figure")
    func theDayIsUnchanged() throws {
        let withTheRow = makeModel(store: try makeReturningStore())
        let withoutIt = makeModel(store: try makeFirstRunStore())

        #expect(withTheRow.emptyDay != nil)
        #expect(withoutIt.emptyDay == nil)

        #expect(withTheRow.today.totals == withoutIt.today.totals)
        #expect(withTheRow.today.groups == withoutIt.today.groups)
        #expect(withTheRow.today.summary == withoutIt.today.summary)

        #expect(withTheRow.today.totals.kilocalories == 0)
        #expect(withTheRow.today.groups.isEmpty)
        #expect(withTheRow.today.summary.goal?.percentage == 0)
        #expect(withTheRow.today.summary.goal?.bars.allSatisfy { $0.used == 0 } == true)
    }

    /// And nothing of it reaches the store: the day it is drawn on still has no
    /// entry, and the browse's far bound has not moved onto it.
    @Test("the row writes nothing")
    func nothingIsWritten() throws {
        let store = try makeReturningStore()
        let model = makeModel(store: store)
        #expect(model.emptyDay != nil)

        #expect(try store.nutritionEntries(on: Date()).isEmpty)
        let earliest = try #require(try store.earliestEntryDate())
        #expect(store.calendar.isDateInToday(earliest) == false)
    }
}

// MARK: - On the screen

/// What the screen actually draws, rather than what a value holds.
///
/// **Rendered, for the reason `TodayListFadeTests` is rendered.** The claims here
/// are that the row is on the screen, that it stands where the day list's own
/// rows stand, and that its heading is the one the value names — and a test over
/// `TodayEmptyDay` alone would pass with the view deleted.
@MainActor
@Suite("Today · the empty day's row on the screen", .serialized)
struct TodayEmptyDayDrawingTests {

    // MARK: - Fixtures

    /// Light, so the ink stands as far from the ground as it ever does — the
    /// pair `TodayListFadeTests` measures against.
    private static let palette = FuelPalette(theme: .light, accent: .blue)

    private static let date = Calendar.current.startOfDay(
        for: Date(timeIntervalSince1970: 1_756_771_200)
    )

    private static func emptyDay(_ label: MealLabel) -> TodayEmptyDay? {
        let hour: Int
        switch label {
        case .snack: hour = 2
        case .breakfast: hour = 8
        case .lunch: hour = 12
        case .dinner: hour = 20
        }
        return TodayEmptyDay(
            isToday: true,
            hasEntries: false,
            isGettingStartedOffered: false,
            now: date.addingTimeInterval(Double(hour) * 3_600),
            calendar: .current
        )
    }

    private static func entry(_ label: MealLabel) -> NutritionEntry {
        NutritionEntry(
            title: "Oats with skyr",
            kilocalories: 420,
            macros: MacroTotals(protein: 30, carbs: 55, fat: 9),
            loggedAt: date.addingTimeInterval(29_640),
            source: .photo,
            label: label
        )
    }

    /// A block on the app's own ground, in the app's own margin, so the two
    /// things compared below are laid out exactly as Today lays them out.
    private func hosted(_ content: some View) throws -> HostedScreen {
        try HostedScreen(
            VStack(alignment: .leading, spacing: .zero) { content }
                .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Self.palette.background),
            palette: Self.palette
        )
    }

    // MARK: - Measuring

    /// How much ink stands at each height of the window.
    private func profile(of hosted: HostedScreen, leadingHalfOnly: Bool = false) throws -> [Int] {
        let drawing = try #require(hosted.drawing)
        let ground = DrawnPixels.Channels(Self.palette.background)
        let width = Int(drawing.size.width)
        let columns = leadingHalfOnly ? 0..<(width / 2) : 0..<width
        return (0..<Int(drawing.size.height)).map { y in
            drawing.peakDeviation(fromColour: ground, y: y, x: columns)
        }
    }

    private func firstInk(in profile: [Int], from start: Int = 0) -> Int? {
        (start..<profile.count).first { profile[$0] > DrawnPixels.tolerance }
    }

    /// Where the `hair` rule under a heading is drawn: the first height at which
    /// ink runs across the whole content width.
    private func rule(in hosted: HostedScreen, below start: Int) throws -> Int {
        let drawing = try #require(hosted.drawing)
        let ground = DrawnPixels.Channels(Self.palette.background)
        let width = Int(drawing.size.width)
        let inset = Int(FuelMetrics.Screen.horizontalPadding)
        let content = inset..<(width - inset)

        let found = (start..<Int(drawing.size.height)).first { y in
            content.allSatisfy { x in
                drawing.deviation(fromColour: ground, x: x, y: y) > DrawnPixels.tolerance
            }
        }
        return try #require(found)
    }

    // MARK: - The row is a meal row

    /// The block is headed and closed the way a section of the day list is,
    /// because it draws that heading and that row rather than each stating its
    /// own.
    ///
    /// The rule under the heading is allowed the one point `expect(_:isTheDrawn:)`
    /// allows anywhere: the day list's heading carries the group's calories in
    /// `DM Mono` beside the label and the empty day's carries nothing there, and
    /// a second face in the row lays out a line box a point taller than the
    /// label alone.
    @Test("the row is headed and closed the way a section of the day list is")
    func standsWhereAMealRowStands() throws {
        let emptyDay = try #require(Self.emptyDay(.breakfast))
        let placeholder = try hosted(TodayEmptyDayView(emptyDay: emptyDay, onAddEntry: {}))
        let list = try hosted(
            TodayDayList(
                groups: DayGrouping.groups(of: [Self.entry(.breakfast)]),
                onSelect: { _ in }
            )
        )

        let placeholderHeading = try #require(firstInk(in: try profile(of: placeholder)))
        let listHeading = try #require(firstInk(in: try profile(of: list)))
        #expect(placeholderHeading == listHeading)

        let placeholderRule = try rule(in: placeholder, below: placeholderHeading)
        let listRule = try rule(in: list, below: listHeading)
        expect(placeholderRule, isTheDrawn: CGFloat(listRule))

        // The row is closed, which is the day list's reading of the export
        // rather than the checklist's: a rule under the last row is what a list
        // that continues looks like, and this one continues as the day is
        // logged.
        let closing = try rule(in: placeholder, below: placeholderRule + 2)
        let listClosing = try rule(in: list, below: listRule + 2)

        // The row's own leading edge is the day list's: both titles start on the
        // screen's margin, which a row drawn inside a block of its own would
        // lose.
        let ground = DrawnPixels.Channels(Self.palette.background)
        let placeholderDrawn = try #require(placeholder.drawing)
        let listDrawn = try #require(list.drawing)
        let placeholderRow = try #require(
            placeholderDrawn.inkBox(
                against: ground,
                in: band(from: placeholderRule, to: closing, of: placeholderDrawn)
            )
        )
        let listRow = try #require(
            listDrawn.inkBox(
                against: ground,
                in: band(from: listRule, to: listClosing, of: listDrawn)
            )
        )
        #expect(placeholderRow.left == listRow.left)

        // Nothing of the row is drawn outside its two rules, which is what a
        // block laying out its own padding would break.
        #expect(placeholderRow.top > placeholderRule)
        #expect(Int(placeholderDrawn.size.height) - placeholderRow.bottom - 1 < closing)
    }

    /// The strip between two rules, which is where a row's own ink is and
    /// nothing else's.
    private func band(from rule: Int, to closing: Int, of drawing: DrawnPixels) -> CGRect {
        CGRect(
            x: .zero,
            y: CGFloat(rule + 1),
            width: drawing.size.width,
            height: CGFloat(closing - rule - 1)
        )
    }

    /// The plus is drawn where a row's value is drawn: on the trailing edge of
    /// the content, inside the screen's own margin.
    @Test("the plus stands on the row's trailing edge")
    func thePlusIsOnTheTrailingEdge() throws {
        let emptyDay = try #require(Self.emptyDay(.breakfast))
        let screen = try hosted(TodayEmptyDayView(emptyDay: emptyDay, onAddEntry: {}))
        let drawing = try #require(screen.drawing)

        let heading = try #require(firstInk(in: try profile(of: screen)))
        let rule = try rule(in: screen, below: heading)
        let row = CGRect(
            x: drawing.size.width / 2,
            y: CGFloat(rule + 1),
            width: drawing.size.width / 2,
            height: drawing.size.height - CGFloat(rule + 1)
        )
        let box = try #require(
            drawing.inkBox(against: DrawnPixels.Channels(Self.palette.background), in: row),
            "nothing is drawn on the trailing half of the row"
        )

        // Type carries a side bearing the export's own margin does not, so the
        // claim is that the glyph sits inside the margin and against it, not on
        // it to the point.
        #expect(CGFloat(box.right) >= FuelMetrics.Screen.horizontalPadding)
        #expect(
            CGFloat(box.right) < FuelMetrics.Screen.horizontalPadding + FuelMetrics.Space.s8,
            "the plus stands \(box.right) from the edge with the margin at \(FuelMetrics.Screen.horizontalPadding)"
        )
    }

    // MARK: - The heading is the one the value names

    /// Each of the four labels draws the heading the day list draws for that
    /// same label — which is what a heading wired to a constant would fail.
    @Test("the heading drawn is the day list's own heading for that label", arguments: MealLabel.allCases)
    func headingMatchesTheDayList(label: MealLabel) throws {
        let emptyDay = try #require(Self.emptyDay(label))
        let placeholder = try hosted(TodayEmptyDayView(emptyDay: emptyDay, onAddEntry: {}))
        let list = try hosted(
            TodayDayList(groups: DayGrouping.groups(of: [Self.entry(label)]), onSelect: { _ in })
        )

        // The leading half only: the day list draws the group's calories on the
        // trailing edge and the empty day draws nothing there, which is the one
        // difference between the two headings.
        let drawn = try #require(placeholder.drawing)
        let heading = CGRect(
            x: .zero,
            y: .zero,
            width: drawn.size.width / 2,
            height: CGFloat(try rule(in: placeholder, below: 0))
        )
        let ground = DrawnPixels.Channels(Self.palette.background)

        let listDrawn = try #require(list.drawing)
        let placeholderBox = try #require(drawn.inkBox(against: ground, in: heading))
        let listBox = try #require(listDrawn.inkBox(against: ground, in: heading))

        #expect(placeholderBox.left == listBox.left)
        #expect(placeholderBox.right == listBox.right)
        #expect(placeholderBox.top == listBox.top)
        #expect(placeholderBox.bottom == listBox.bottom)
    }

    /// And the four are not one drawing: a heading that ignored its label would
    /// pass the comparison above against a day list that ignored its own.
    @Test("the four labels draw four different headings")
    func theFourHeadingsDiffer() throws {
        var widths: Set<Int> = []
        for label in MealLabel.allCases {
            let emptyDay = try #require(Self.emptyDay(label))
            let screen = try hosted(TodayEmptyDayView(emptyDay: emptyDay, onAddEntry: {}))
            let drawn = try #require(screen.drawing)
            let heading = CGRect(
                x: .zero,
                y: .zero,
                width: drawn.size.width / 2,
                height: CGFloat(try rule(in: screen, below: 0))
            )
            let box = try #require(
                drawn.inkBox(against: DrawnPixels.Channels(Self.palette.background), in: heading)
            )
            widths.insert(box.right)
        }
        #expect(widths.count == MealLabel.allCases.count)
    }

    // MARK: - On Today itself

    /// The screen with the row on it, against the same screen without it: the
    /// export's own nothing is what an empty day drew before, and it is still
    /// what it draws when the row is not offered.
    @Test("Today draws the row on an empty day and nothing at all without it")
    func todayDrawsIt() throws {
        let withTheRow = try hostedToday(emptyDay: Self.emptyDay(.breakfast), entries: [])
        let withoutIt = try hostedToday(emptyDay: nil, entries: [])

        let listArea = try summaryEnd(of: withoutIt)
        let ground = DrawnPixels.Channels(Self.palette.background)
        let region = CGRect(
            x: .zero,
            y: CGFloat(listArea),
            // The leading half and short of the fade band, so neither the add
            // button nor the band itself is what either reading finds — the
            // same narrowing `TodayListFadeTests` takes, for the same reason.
            width: withTheRow.window.bounds.width / 2,
            height: withTheRow.window.bounds.height - CGFloat(listArea) - FuelMetrics.ListFade.height
        )

        let drawnWith = try #require(withTheRow.drawing)
        let drawnWithout = try #require(withoutIt.drawing)
        #expect(drawnWith.inkBox(against: ground, in: region) != nil)
        #expect(drawnWithout.inkBox(against: ground, in: region) == nil)
    }

    /// The day list wins the moment there is an entry, so a screen handed both
    /// draws exactly the screen that was handed only the list.
    @Test("a day with one meal on it draws the list and not the row")
    func aLoggedMealHidesIt() throws {
        let day = [Self.entry(.breakfast)]
        let both = try hostedToday(emptyDay: Self.emptyDay(.dinner), entries: day)
        let listOnly = try hostedToday(emptyDay: nil, entries: day)

        #expect(try profile(of: both) == (try profile(of: listOnly)))
    }

    /// And the summary above it is the same drawing either way: the ring, the
    /// percentage and the three bars cannot see the row.
    @Test("the ring and the macro bars are drawn identically with the row and without")
    func theSummaryIsUntouched() throws {
        let withTheRow = try hostedToday(emptyDay: Self.emptyDay(.breakfast), entries: [])
        let withoutIt = try hostedToday(emptyDay: nil, entries: [])
        let end = try summaryEnd(of: withoutIt)

        let above = try profile(of: withTheRow, leadingHalfOnly: true).prefix(end)
        let alone = try profile(of: withoutIt, leadingHalfOnly: true).prefix(end)
        #expect(above == alone)
    }

    // MARK: - Under a finger

    /// The band between the two rules is what answers to a finger, and it is at
    /// least a fingertip.
    ///
    /// **Whether a touch is actually delivered is not observable from a unit
    /// test here**, for the reason `SettingsChromeTests` writes down: a hosting
    /// view answers `hitTest` for every point inside it, and SwiftUI builds no
    /// accessibility element until an assistive client asks for one. What is
    /// observable is the geometry the delivery follows from, which is what this
    /// measures — on the drawn screen rather than over `FuelMetrics`.
    @Test("the row is at least a fingertip tall")
    func theRowTakesAFinger() throws {
        let emptyDay = try #require(Self.emptyDay(.breakfast))
        let screen = try hosted(TodayEmptyDayView(emptyDay: emptyDay, onAddEntry: {}))

        let heading = try #require(firstInk(in: try profile(of: screen)))
        let opening = try rule(in: screen, below: heading)
        let closing = try rule(in: screen, below: opening + 2)

        #expect(
            CGFloat(closing - opening) >= FuelMetrics.Control.minimumHitTarget,
            "the row is \(closing - opening) tall against a minimum of \(FuelMetrics.Control.minimumHitTarget)"
        )
    }

    // MARK: - Hosting Today

    private func hostedToday(
        emptyDay: TodayEmptyDay?,
        entries: [NutritionEntry]
    ) throws -> HostedScreen {
        try HostedScreen(
            TodayView(
                presentation: TodayPresentation(
                    entries: entries,
                    mode: .goal(.default),
                    date: Self.date
                ),
                navigation: TodayDayNavigation(
                    showing: Self.date,
                    now: Self.date,
                    firstEntry: Calendar.current.date(byAdding: .day, value: -14, to: Self.date),
                    calendar: .current
                ),
                isTravellingBackward: false,
                // Retired, so the checklist is never the thing being measured.
                gettingStarted: TodayGettingStarted(
                    hasChosenTheme: true,
                    hasChosenAccent: true,
                    hasLoggedMeal: true
                ),
                emptyDay: emptyDay,
                onOpenSettings: {},
                onAddEntry: {},
                onOpenMeal: { _ in },
                onShowPreviousDay: {},
                onShowNextDay: {},
                onShowDay: { _ in }
            ),
            palette: Self.palette
        )
    }

    /// Where the summary block stops and the list's place begins: the last
    /// height at which the screen *without* a row draws anything.
    ///
    /// Taken from the bare screen rather than stated as a number, because what
    /// it is for is a region below everything the summary draws — and the
    /// summary's own height is not this feature's to pin. The leading half
    /// only, so the add button standing at the trailing edge is not what the
    /// scan comes back with.
    private func summaryEnd(of hosted: HostedScreen) throws -> Int {
        let drawn = try profile(of: hosted, leadingHalfOnly: true)
        let band = Int(hosted.window.bounds.height - FuelMetrics.ListFade.height)
        let last = (0..<band).last { drawn[$0] > DrawnPixels.tolerance }
        return try #require(last) + 1
    }
}

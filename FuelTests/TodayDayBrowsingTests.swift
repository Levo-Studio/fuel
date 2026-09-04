import Foundation
import Testing

@testable import Fuel

// MARK: - Browsing back through the days

/// What the shell does when the day changes, as against `TodayDayNavigationTests`,
/// which holds the arithmetic on plain values. Here the store is real, the
/// bounds are read out of it, and the question is what Today ends up drawing.
///
/// **Nothing here reaches a provider, a camera or a Keychain.** The two log
/// halves are built from the shared stand-ins, because what a shell is asked in
/// this suite is which day is up, never what an estimate came back as.
@Suite("Today · browsing back through the days")
struct TodayDayBrowsingTests {

    // MARK: - Fixtures

    /// A store whose calendar is the machine's, because the shell reads
    /// `store.calendar` and every expectation below is stated against the same
    /// one. Pinning it to UTC would make "today" mean one thing to the model
    /// and another to the test on any machine that is not on UTC.
    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true)
    }

    private func makePreferences() -> SettingsPreferences {
        let suite = "apps.levo-studio.Fuel.tests.daynav.\(UUID().uuidString)"
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

    /// A store that has been through onboarding and holds one meal on a day
    /// some way back, so there is a history to walk into.
    private func makeBrowsableStore(historyDaysBack: Int = 6) throws -> FuelStore {
        let store = try makeStore()
        try store.setCountingMode(.goal(.default))
        try store.log(
            title: "Oats with skyr",
            kilocalories: 420,
            macros: MacroTotals(protein: 30, carbs: 55, fat: 9),
            loggedAt: Self.day(historyDaysBack, before: store),
            source: .photo
        )
        return store
    }

    private static func day(_ daysBack: Int, before store: FuelStore) -> Date {
        let today = store.calendar.startOfDay(for: Date())
        return store.calendar.date(byAdding: .day, value: -daysBack, to: today) ?? today
    }

    private func startOfToday(_ store: FuelStore) -> Date {
        store.calendar.startOfDay(for: Date())
    }

    // MARK: - Where it opens

    /// A browsed day is not a preference and is not stored: it is where the
    /// user walked to in this session.
    @Test("the app opens on the current day")
    func opensOnToday() throws {
        let store = try makeBrowsableStore()
        let model = makeModel(store: store)

        #expect(model.dayNavigation.isToday)
        #expect(model.today.date == startOfToday(store))
    }

    // MARK: - Moving

    @Test("the back arrow retreats a day and the forward arrow returns")
    func retreatsAndAdvances() throws {
        let store = try makeBrowsableStore()
        let model = makeModel(store: store)
        let today = startOfToday(store)

        model.showPreviousDay()
        #expect(model.dayNavigation.day == store.calendar.date(byAdding: .day, value: -1, to: today))
        #expect(model.today.date == model.dayNavigation.day)
        #expect(model.dayTravelIsBackward)

        model.showNextDay()
        #expect(model.dayNavigation.day == today)
        #expect(!model.dayTravelIsBackward)
    }

    /// The forward bound, which is why the arrow is drawn disabled on today.
    @Test("the future is not browsable, however hard the forward control is used")
    func cannotGoPastToday() throws {
        let store = try makeBrowsableStore()
        let model = makeModel(store: store)
        let today = startOfToday(store)

        #expect(!model.dayNavigation.canGoForward)

        model.showNextDay()
        model.showDay(store.calendar.date(byAdding: .day, value: 5, to: today) ?? today)

        #expect(model.dayNavigation.day == today)
        #expect(model.today.date == today)
    }

    /// The far bound. Past the first meal ever logged there is nothing the app
    /// could show, so the walk stops there rather than going on forever.
    @Test("the walk back stops at the day of the first meal ever logged")
    func stopsAtTheFirstEntry() throws {
        let store = try makeBrowsableStore(historyDaysBack: 2)
        let model = makeModel(store: store)
        let earliest = Self.day(2, before: store)

        model.showPreviousDay()
        model.showPreviousDay()
        #expect(model.dayNavigation.day == earliest)
        #expect(!model.dayNavigation.canGoBackward)

        model.showPreviousDay()
        #expect(model.dayNavigation.day == earliest)
    }

    /// A store nothing has been logged to has no history to walk into, so both
    /// arrows are dead and the picker offers the current day alone.
    @Test("a store with nothing in it browses nowhere")
    func emptyStoreBrowsesNowhere() throws {
        let store = try makeStore()
        try store.setCountingMode(.goal(.default))
        let model = makeModel(store: store)

        #expect(!model.dayNavigation.canGoBackward)
        #expect(!model.dayNavigation.canGoForward)
        #expect(model.dayNavigation.browsableDays == startOfToday(store)...startOfToday(store))
    }

    /// The jump is the same movement as an arrow and lands on the same value,
    /// which is what makes the three controls one feature rather than three.
    @Test("a jump from the picker lands where the arrows would")
    func jumpMatchesTheArrows() throws {
        let store = try makeBrowsableStore()
        let jumped = makeModel(store: store)
        let stepped = makeModel(store: store)

        jumped.showDay(Self.day(3, before: store))
        stepped.showPreviousDay()
        stepped.showPreviousDay()
        stepped.showPreviousDay()

        #expect(jumped.dayNavigation.day == stepped.dayNavigation.day)
        #expect(jumped.dayTravelIsBackward)
        #expect(stepped.dayTravelIsBackward)
    }

    // MARK: - A past day with nothing on it

    /// Not the same thing as a new user, and not the same thing as an empty
    /// today: the day is closed and nothing was logged in it.
    @Test("a past day nobody logged to is empty rather than a fresh start")
    func emptyPastDayIsEmpty() throws {
        let store = try makeBrowsableStore()
        let model = makeModel(store: store)

        model.showPreviousDay()

        #expect(!model.dayNavigation.isToday)
        #expect(!model.today.hasEntries)
        #expect(model.today.totals.kilocalories == 0)
        #expect(model.today.groups.isEmpty)
    }

    /// A past day that does have meals on it draws them, and the totals are
    /// that day's rather than the current one's.
    @Test("a past day shows its own meals and its own totals")
    func pastDayShowsItsOwnMeals() throws {
        let store = try makeBrowsableStore(historyDaysBack: 3)
        let model = makeModel(store: store)

        #expect(model.today.totals.kilocalories == 0)

        model.showDay(Self.day(3, before: store))

        #expect(model.today.hasEntries)
        #expect(model.today.totals.kilocalories == 420)
        #expect(model.today.groups.first?.entries.first?.title == "Oats with skyr")
    }

    // MARK: - The counting mode on a past day

    /// The mode is a preference on screen 17, not a property a day carries, so
    /// a past day draws whichever of screens 05 and 06 the user is in now.
    @Test("a past day draws the ring in goal mode and no ring in count-only")
    func pastDayFollowsTheCountingMode() throws {
        let store = try makeBrowsableStore(historyDaysBack: 3)
        let goal = makeModel(store: store)

        goal.showDay(Self.day(3, before: store))
        #expect(goal.today.showsRing)
        #expect(goal.today.summary.goal?.bars.map(\.macro) == [.protein, .carbs, .fat])

        try store.setCountingMode(.countOnly)
        let counting = makeModel(store: store)
        counting.showDay(Self.day(3, before: store))
        #expect(!counting.today.showsRing)
        #expect(counting.today.summary.goal == nil)
    }

    // MARK: - Logging while a past day is up

    /// The one the owner's prior names: logging always means now.
    ///
    /// The log flow takes the device clock and draws no control for choosing a
    /// date, so a meal logged while Tuesday is up still lands on today — and
    /// the flow closes onto the day it landed in, because coming back onto
    /// Tuesday would leave the user looking at a day their meal is not on.
    @Test("a meal logged while a past day is up lands on today, and Today comes back to it")
    func loggingAlwaysMeansNow() throws {
        let store = try makeBrowsableStore()
        let model = makeModel(store: store)
        let today = startOfToday(store)

        model.showPreviousDay()
        #expect(!model.dayNavigation.isToday)

        model.openLogFlow()
        #expect(
            model.logFlow.log(
                RecentMeal(
                    id: UUID(),
                    title: "Chicken bowl, rice",
                    kilocalories: 680,
                    macros: MacroTotals(protein: 52, carbs: 78, fat: 21)
                )
            )
        )
        model.dismissDestinationAfterLogging()

        // The entry is on today and on no other day.
        #expect(try store.entries(on: today).map(\.title) == ["Chicken bowl, rice"])
        #expect(try store.entries(on: Self.day(1, before: store)).isEmpty)

        // And Today is showing it, rather than the day the flow was opened on.
        #expect(model.dayNavigation.isToday)
        #expect(model.today.date == today)
        #expect(model.today.totals.kilocalories == 680)
    }

    /// Cancelling writes nothing, so there is nowhere else to be: the browse
    /// stays where the user left it.
    @Test("cancelling the flow leaves the browsed day where it was")
    func cancellingKeepsTheBrowsedDay() throws {
        let store = try makeBrowsableStore()
        let model = makeModel(store: store)

        model.showPreviousDay()
        let browsed = model.dayNavigation.day

        model.openLogFlow()
        model.dismissDestination()

        #expect(model.dayNavigation.day == browsed)
        #expect(model.today.date == browsed)
    }
}

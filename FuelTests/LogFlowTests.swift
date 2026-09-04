import Foundation
import Testing

@testable import Fuel

// MARK: - Log flow

/// The flow's chrome and its Recent tab.
///
/// Nothing here constructs a `KeychainStore`, an `AIProvider` or a URL session,
/// and that absence is the subject of `logsWithoutAnyKey` rather than an
/// accident of what was convenient to write: the Recent tab is what makes Fuel
/// usable on the day it is installed, before a key exists.
@Suite("Log flow")
struct LogFlowTests {

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    // MARK: - Tabs

    @Test("the bar offers exactly three tabs, in the drawn order")
    func threeTabs() {
        #expect(LogFlowTab.allCases == [.camera, .text, .recent])
        #expect(LogFlowTab.allCases.count == 3)
    }

    @Test("selecting a tab changes the one being shown")
    func selectingATab() throws {
        let model = LogFlowModel(store: try makeStore())
        #expect(model.selectedTab == .camera)

        model.selectedTab = .recent
        #expect(model.selectedTab == .recent)

        model.selectedTab = .text
        #expect(model.selectedTab == .text)
    }

    // MARK: - The list

    @Test("a fresh store offers no recent meals")
    func emptyOnAFreshStore() throws {
        let model = LogFlowModel(store: try makeStore())
        model.reload()

        #expect(model.recentMeals.isEmpty)
    }

    @Test("the list runs newest first")
    func newestFirst() throws {
        let store = try makeStore()
        try store.log(title: "Oats with skyr", kilocalories: 420, macros: .zero, loggedAt: at(8, 10), source: .photo)
        try store.log(title: "Chicken bowl, rice", kilocalories: 680, macros: .zero, loggedAt: at(12, 30), source: .text)

        let model = LogFlowModel(store: store)
        model.reload()

        #expect(model.recentMeals.map(\.title) == ["Chicken bowl, rice", "Oats with skyr"])
    }

    @Test("a meal eaten twice appears once, as its most recent version")
    func repeatsCollapse() throws {
        let store = try makeStore()
        try store.log(title: "Oats with skyr", kilocalories: 400, macros: .zero, loggedAt: at(8, 0, day: 0), source: .photo)
        try store.log(title: "Oats with skyr", kilocalories: 420, macros: .zero, loggedAt: at(8, 0, day: 1), source: .photo)

        let model = LogFlowModel(store: store)
        model.reload()

        #expect(model.recentMeals.map(\.title) == ["Oats with skyr"])
        #expect(model.recentMeals.first?.kilocalories == 420)
    }

    @Test("the list is capped")
    func capped() {
        let entries = (0..<(RecentMeals.maximumRows + 5)).map { index in
            RecentEntry(title: "Meal \(index)", kilocalories: 0, macros: .zero)
        }

        #expect(RecentMeals.list(from: entries).count == RecentMeals.maximumRows)
    }

    // MARK: - Logging

    @Test("tapping a meal writes an entry with the source's macros")
    func tappingLogsTheMeal() throws {
        let store = try makeStore()
        let macros = MacroTotals(protein: 32, carbs: 48, fat: 9)
        try store.log(title: "Oats with skyr", kilocalories: 420, macros: macros, loggedAt: at(8, 10, day: 0), source: .photo)

        let model = LogFlowModel(store: store, selectedTab: .recent, now: { at(12, 30, day: 1) })
        model.reload()
        let meal = try #require(model.recentMeals.first)

        #expect(model.log(meal))

        let day = try store.nutritionEntries(on: at(12, 0, day: 1))
        let logged = try #require(day.first)
        #expect(logged.title == "Oats with skyr")
        #expect(logged.kilocalories == 420)
        #expect(logged.macros == macros)
        #expect(logged.source == .recent)
    }

    @Test("a repeated meal brings the whole breakdown back, item for item")
    func repeatingCarriesTheItems() throws {
        let store = try makeStore()
        // The three items of screen 14, translated, with the middle one left
        // without macros on purpose: CIQUAL has no fat figure for cooked
        // polenta, so a grounded item can legitimately arrive with `nil` here
        // and that absence is the marking. It has to survive the repeat exactly
        // as the two complete ones do.
        let items = [
            RecognisedItem(
                name: "Salmon fillet, fried",
                kilocalories: 240,
                macros: MacroTotals(protein: 34, carbs: 0, fat: 11),
                note: .photo(confidence: .confident, approximateGrams: 150)
            ),
            RecognisedItem(
                name: "Polenta",
                kilocalories: 150,
                note: .photo(confidence: .confident, approximateGrams: 180)
            ),
            RecognisedItem(
                name: "Leaf spinach",
                kilocalories: 70,
                macros: MacroTotals(protein: 3, carbs: 2, fat: 1),
                note: .photo(confidence: .unsure, approximateGrams: 90)
            )
        ]
        try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 37, carbs: 26, fat: 23),
            loggedAt: at(19, 20, day: 0),
            source: .photo,
            items: items
        )

        let model = LogFlowModel(store: store, selectedTab: .recent, now: { at(19, 30, day: 1) })
        model.reload()
        let meal = try #require(model.recentMeals.first)
        #expect(meal.items == items)

        #expect(model.log(meal))

        // Newest first, so the repeat is the first row.
        let repeated = try #require(try store.recentEntries(limit: 1).first)
        #expect(repeated.loggedAt == at(19, 30, day: 1))
        #expect(repeated.source == .recent)
        #expect(repeated.items.count == 3)
        // Whole-value equality, which pins each item's name, its own
        // kilocalories, its note and its identity as well as its macros.
        #expect(repeated.items == items)
        // Spelled out separately because it is the one that is easy to lose to
        // a re-estimate: the middle item stays without macros rather than
        // gaining a zero nothing measured.
        #expect(repeated.items.map(\.macros) == items.map(\.macros))
    }

    @Test("the label comes from the time of day, not from the meal it repeats")
    func labelComesFromTheTimeOfDay() throws {
        let store = try makeStore()
        // The source was a breakfast. What it is called the second time around
        // is decided by the day it lands in, and nothing else.
        try store.log(title: "Oats with skyr", kilocalories: 420, macros: .zero, loggedAt: at(8, 10, day: 0), source: .photo)
        #expect(try store.nutritionEntries(on: at(8, 0, day: 0)).first?.label == .breakfast)

        let model = LogFlowModel(store: store, selectedTab: .recent, now: { at(19, 20, day: 1) })
        model.reload()
        #expect(model.log(try #require(model.recentMeals.first)))

        #expect(try store.nutritionEntries(on: at(19, 0, day: 1)).first?.label == .dinner)
    }

    @Test("the second meal of a morning is a snack, as the day rule says")
    func labelFollowsTheCourseOfTheDay() throws {
        let store = try makeStore()
        try store.log(title: "Oats with skyr", kilocalories: 420, macros: .zero, loggedAt: at(7, 30), source: .photo)

        let model = LogFlowModel(store: store, selectedTab: .recent, now: { at(9, 45) })
        model.reload()
        #expect(model.log(try #require(model.recentMeals.first)))

        let day = try store.nutritionEntries(on: at(9, 0))
        #expect(day.map(\.label) == [.breakfast, .snack])
    }

    @Test("logging from Recent needs no API key")
    func logsWithoutAnyKey() throws {
        // The whole path, built from a store and a clock. There is no key in
        // this test, no Keychain call and nothing to reach the network with —
        // which is the point of the tab: Fuel is not useless on day one.
        let store = try makeStore()
        try store.log(title: "Chicken bowl, rice", kilocalories: 680, macros: .zero, loggedAt: at(12, 30, day: 0), source: .text)

        let model = LogFlowModel(store: store, selectedTab: .recent, now: { at(12, 40, day: 1) })
        model.reload()

        let meal = try #require(model.recentMeals.first)
        #expect(model.log(meal))
        #expect(try store.nutritionEntries(on: at(12, 0, day: 1)).count == 1)
    }
}

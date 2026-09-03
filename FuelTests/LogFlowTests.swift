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
            entry(at: at(0, index), title: "Meal \(index)")
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

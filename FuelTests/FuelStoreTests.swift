import Foundation
import Testing

@testable import Fuel

// MARK: - Store

/// The store's own job: fetch a day, write an entry, and convert at the
/// boundary. The arithmetic and the label rule are tested on plain values
/// elsewhere; what is checked here is that the store hands them the right ones.
@Suite("Store")
struct FuelStoreTests {

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    @Test("logging derives the day's labels")
    func derivesLabelsWhileLogging() throws {
        let store = try makeStore()
        try store.log(title: "Porridge", kilocalories: 420, macros: .zero, loggedAt: at(8, 14), source: .photo)
        try store.log(title: "Coffee", kilocalories: 110, macros: .zero, loggedAt: at(9, 45), source: .recent)
        try store.log(title: "Bowl", kilocalories: 680, macros: .zero, loggedAt: at(12, 40), source: .text)

        let day = try store.nutritionEntries(on: at(12, 0))
        #expect(day.map(\.label) == [.breakfast, .snack, .lunch])
    }

    @Test("a day only sees its own entries")
    func fetchesOneDay() throws {
        let store = try makeStore()
        try store.log(title: "Yesterday", kilocalories: 500, macros: .zero, loggedAt: at(20, 0, day: 0), source: .text)
        try store.log(title: "Today", kilocalories: 300, macros: .zero, loggedAt: at(8, 0, day: 1), source: .text)

        let day = try store.nutritionEntries(on: at(23, 0, day: 1))
        #expect(day.map(\.title) == ["Today"])
    }

    @Test("the hand-off carries the entry's values")
    func handOff() throws {
        let store = try makeStore()
        let macros = MacroTotals(protein: 34, carbs: 28, fat: 23)
        let entry = try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: macros,
            loggedAt: at(19, 20),
            source: .photo,
            items: [
                RecognisedItem(
                    name: "Salmon fillet",
                    kilocalories: 240,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            ]
        )

        let value = entry.nutritionValue
        #expect(value.id == entry.entryID)
        #expect(value.title == "Salmon with polenta")
        #expect(value.kilocalories == 460)
        #expect(value.macros == macros)
        #expect(value.source == .photo)
        #expect(value.label == .dinner)
        #expect(value.isLabelUserSet == false)
        #expect(entry.items.count == 1)
    }

    @Test("a back-dated entry takes the meal, and the later one gives it up")
    func backDatedEntry() throws {
        let store = try makeStore()
        try store.log(title: "Late", kilocalories: 400, macros: .zero, loggedAt: at(19, 0), source: .text)
        try store.log(title: "Earlier", kilocalories: 300, macros: .zero, loggedAt: at(18, 30), source: .text)

        let day = try store.nutritionEntries(on: at(12, 0))
        #expect(day.map(\.title) == ["Earlier", "Late"])
        #expect(day.map(\.label) == [.dinner, .snack])
    }

    @Test("a back-dated entry cannot take a meal the user claimed by hand")
    func backDatedEntryRespectsAnOverride() throws {
        let store = try makeStore()
        let late = try store.log(title: "Late", kilocalories: 400, macros: .zero, loggedAt: at(19, 0), source: .text)
        try store.overrideLabel(.dinner, on: late)
        try store.log(title: "Earlier", kilocalories: 300, macros: .zero, loggedAt: at(18, 30), source: .text)

        let day = try store.nutritionEntries(on: at(12, 0))
        #expect(day.map(\.label) == [.snack, .dinner])
        #expect(late.isLabelUserSet)
    }

    @Test("yesterday's meals do not claim today's")
    func mealsAreClaimedPerDay() throws {
        let store = try makeStore()
        try store.log(title: "Yesterday", kilocalories: 400, macros: .zero, loggedAt: at(19, 0, day: 0), source: .text)
        try store.log(title: "Today", kilocalories: 400, macros: .zero, loggedAt: at(19, 0, day: 1), source: .text)

        #expect(try store.nutritionEntries(on: at(19, 0, day: 1)).map(\.label) == [.dinner])
    }

    @Test("a label the user picks is marked as theirs")
    func overrideLabel() throws {
        let store = try makeStore()
        let entry = try store.log(title: "Eggs", kilocalories: 628, macros: .zero, loggedAt: at(8, 0), source: .text)
        #expect(entry.label == .breakfast)

        try store.overrideLabel(.snack, on: entry)
        #expect(entry.label == .snack)
        #expect(entry.isLabelUserSet)
    }

    @Test("recent entries come back newest first")
    func recents() throws {
        let store = try makeStore()
        try store.log(title: "First", kilocalories: 100, macros: .zero, loggedAt: at(8, 0), source: .text)
        try store.log(title: "Second", kilocalories: 100, macros: .zero, loggedAt: at(12, 0), source: .text)
        try store.log(title: "Third", kilocalories: 100, macros: .zero, loggedAt: at(19, 0), source: .text)

        let recents = try store.recentEntries(limit: 2)
        #expect(recents.map(\.title) == ["Third", "Second"])
    }

    @Test("there are no goal settings until onboarding answers")
    func goalSettingsAreCreatedOnDemand() throws {
        let store = try makeStore()
        #expect(try store.existingGoalSettings() == nil)
        #expect(try store.countingMode() == .goal(.default))

        let settings = try store.goalSettings()
        #expect(settings.mode == .goal(.default))
        #expect(try store.existingGoalSettings() != nil)
    }

    @Test("switching to count-only keeps the targets for the way back")
    func countOnlyKeepsTargets() throws {
        let store = try makeStore()
        let targets = DailyTargets(kilocalories: 1800, protein: 140, carbs: 180, fat: 60)
        try store.setCountingMode(.goal(targets))
        try store.setCountingMode(.countOnly)

        #expect(try store.countingMode() == .countOnly)
        #expect(try store.goalSettings().targets == targets)
    }
}


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

    @Test("nothing has ever been logged until something is")
    func hasAnyEntry() throws {
        let store = try makeStore()
        #expect(try store.hasAnyEntry() == false)

        try store.log(title: "Porridge", kilocalories: 420, macros: .zero, loggedAt: at(8, 14), source: .photo)
        #expect(try store.hasAnyEntry())
    }

    @Test("a meal logged on another day still counts as ever logged")
    func hasAnyEntryIsNotScopedToADay() throws {
        let store = try makeStore()
        try store.log(title: "Yesterday", kilocalories: 500, macros: .zero, loggedAt: at(20, 0, day: 0), source: .text)

        #expect(try store.nutritionEntries(on: at(12, 0, day: 1)).isEmpty)
        #expect(try store.hasAnyEntry())
    }

    // MARK: - The far end of the history

    @Test("an empty store has no earliest entry")
    func earliestOfAnEmptyStore() throws {
        let store = try makeStore()
        #expect(try store.earliestEntryDate() == nil)
    }

    /// The oldest, not the first written. Entries arrive in whatever order the
    /// user logs them, and a meal backdated behind everything already stored
    /// moves the far end of the history rather than joining behind it.
    @Test("the earliest entry is the oldest one, whenever it was written")
    func earliestIsTheOldestNotTheFirstWritten() throws {
        let store = try makeStore()
        try store.log(title: "Bowl", kilocalories: 680, macros: .zero, loggedAt: at(12, 40, day: 4), source: .text)
        try store.log(title: "Porridge", kilocalories: 420, macros: .zero, loggedAt: at(8, 14, day: 1), source: .photo)
        try store.log(title: "Salmon", kilocalories: 430, macros: .zero, loggedAt: at(19, 20, day: 7), source: .photo)

        #expect(try store.earliestEntryDate() == at(8, 14, day: 1))
    }

    // MARK: - A meal already in the store

    @Test("an entry comes back by the identity the hand-off carries")
    func fetchesOneEntryByID() throws {
        let store = try makeStore()
        let wanted = try store.log(title: "Bowl", kilocalories: 680, macros: .zero, loggedAt: at(12, 40), source: .text)
        try store.log(title: "Porridge", kilocalories: 420, macros: .zero, loggedAt: at(8, 14), source: .photo)

        #expect(try store.entry(withID: wanted.entryID)?.title == "Bowl")
        #expect(try store.entry(withID: UUID()) == nil)
    }

    /// The one the write-back exists for: a re-analysis replaces what the model
    /// said and touches nothing the user did not ask it to.
    @Test("updating a meal replaces the estimate and leaves its place in the day alone")
    func updateReplacesTheEstimateInPlace() throws {
        let store = try makeStore()
        let entry = try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
            loggedAt: at(19, 20),
            source: .photo,
            advice: "Plenty of protein.",
            items: [RecognisedItem(name: "Polenta", kilocalories: 150, note: .text(amount: .estimated))]
        )
        let identity = entry.entryID

        try store.update(
            entry,
            title: "Salmon with polenta, raw 50 g",
            kilocalories: 390,
            macros: MacroTotals(protein: 34, carbs: 15, fat: 21),
            advice: "Plenty of protein, and now with the polenta weighed.",
            items: [RecognisedItem(name: "Polenta, raw 50 g", kilocalories: 80, note: .text(amount: .recognised))]
        )

        let day = try store.entries(on: at(19, 20))
        #expect(day.count == 1)
        let stored = try #require(day.first)
        // Updated in place: the same row, not a second one beside it.
        #expect(stored.entryID == identity)
        #expect(stored.kilocalories == 390)
        #expect(stored.macros == MacroTotals(protein: 34, carbs: 15, fat: 21))
        #expect(stored.items.map(\.name) == ["Polenta, raw 50 g"])
        // The advisor line is part of what the screen shows about a meal, so a
        // re-priced meal says what it now reads rather than keeping a sentence
        // written about the figures it used to have.
        #expect(stored.advice == "Plenty of protein, and now with the polenta weighed.")
        // The meal was eaten when it was eaten, and it is still the photo entry
        // the day list draws.
        #expect(stored.loggedAt == at(19, 20))
        #expect(stored.source == .photo)
        #expect(stored.label == .dinner)
    }

    @Test("deleting a meal takes it out of its day")
    func deleteRemovesTheEntry() throws {
        let store = try makeStore()
        let entry = try store.log(title: "Bowl", kilocalories: 680, macros: .zero, loggedAt: at(12, 40), source: .text)
        try store.log(title: "Porridge", kilocalories: 420, macros: .zero, loggedAt: at(8, 14), source: .photo)

        try store.delete(entry)

        #expect(try store.entries(on: at(12, 40)).map(\.title) == ["Porridge"])
        #expect(try store.entry(withID: entry.entryID) == nil)
    }

    /// Breakfast is handed out once a day, so deleting the entry holding it
    /// gives the meal back to the one that had to settle for a snack.
    @Test("deleting a meal frees its label for the rest of the day")
    func deleteRelabelsTheDay() throws {
        let store = try makeStore()
        let first = try store.log(title: "Porridge", kilocalories: 420, macros: .zero, loggedAt: at(8, 14), source: .photo)
        try store.log(title: "Toast", kilocalories: 200, macros: .zero, loggedAt: at(9, 45), source: .text)
        #expect(try store.nutritionEntries(on: at(9, 0)).map(\.label) == [.breakfast, .snack])

        try store.delete(first)

        #expect(try store.nutritionEntries(on: at(9, 0)).map(\.label) == [.breakfast])
    }

    @Test("there are no goal settings until onboarding answers")
    func goalSettingsAreCreatedOnDemand() throws {
        let store = try makeStore()
        #expect(try store.existingGoalSettings() == nil)
        #expect(try store.countingMode() == .goal(.default))

        let settings = try store.goalSettingsCreatingIfNeeded()
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
        #expect(try store.goalSettingsCreatingIfNeeded().targets == targets)
    }
}

// MARK: - Recognised items

/// The breakdown is stored as an encoded value rather than as its own model,
/// so its coding is the thing that can break a row.
@Suite("Recognised item")
struct RecognisedItemTests {

    @Test(
        "a note survives a round trip",
        arguments: [
            RecognisedItem.Note.photo(confidence: .confident, approximateGrams: 150),
            RecognisedItem.Note.photo(confidence: .unsure, approximateGrams: 90),
            RecognisedItem.Note.text(amount: .recognised),
            RecognisedItem.Note.text(amount: .estimated),
        ]
    )
    func roundTrip(note: RecognisedItem.Note) throws {
        let data = try JSONEncoder().encode(note)
        #expect(try JSONDecoder().decode(RecognisedItem.Note.self, from: data) == note)
    }

    @Test("a note shape this build does not know reads as unknown")
    func unknownNote() throws {
        let data = Data(#"{"kind":"video","confidence":"confident"}"#.utf8)
        #expect(try JSONDecoder().decode(RecognisedItem.Note.self, from: data) == .unknown)
    }

    @Test("a note missing its confidence reads as the less certain one")
    func missingConfidence() throws {
        let data = Data(#"{"kind":"photo"}"#.utf8)
        let note = try JSONDecoder().decode(RecognisedItem.Note.self, from: data)
        #expect(note == .photo(confidence: .unsure, approximateGrams: 0))
    }

    @Test("items come back off a stored entry")
    func itemsSurviveTheStore() throws {
        let store = try FuelStore(inMemory: true, calendar: testCalendar)
        let items = [
            RecognisedItem(
                name: "Salmon fillet",
                kilocalories: 240,
                note: .photo(confidence: .confident, approximateGrams: 150)
            ),
            RecognisedItem(name: "Polenta", kilocalories: 150, note: .text(amount: .estimated)),
        ]
        try store.log(
            title: "Salmon with polenta",
            kilocalories: 390,
            macros: .zero,
            loggedAt: at(19, 20),
            source: .photo,
            items: items
        )

        let stored = try store.entries(on: at(19, 20)).first
        #expect(stored?.items == items)
    }
}

import Foundation
import Testing

@testable import Fuel

// MARK: - Storing the figure

/// What survives being written down, and what deliberately does not.
@Suite("Accuracy in the store")
struct AccuracyStorageTests {

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    private func scannedItem(_ name: String, kilocalories: Int, percent: Int?) -> RecognisedItem {
        RecognisedItem(
            name: name,
            kilocalories: kilocalories,
            confidence: percent.map { ItemConfidence(estimatePercent: $0) },
            note: .photo(confidence: .confident, approximateGrams: 100)
        )
    }

    @Test("a logged figure is read back off the entry the detail screen opens")
    func figureIsStored() throws {
        let store = try makeStore()
        let entry = try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: .zero,
            loggedAt: at(19, 20),
            source: .photo,
            estimateConfidencePercent: 73,
            items: [scannedItem("Salmon", kilocalories: 240, percent: 90)]
        )

        #expect(try store.entry(withID: entry.entryID)?.estimateConfidencePercent == 73)
    }

    /// A meal logged before the model was ever asked. The property is new and
    /// optional, so the row opens with nothing here rather than failing to
    /// open — the same migration `advice` and `typedSentence` got.
    @Test("an entry from before the field existed has no figure")
    func olderEntryHasNoFigure() throws {
        let store = try makeStore()
        let entry = try store.log(
            title: "Porridge",
            kilocalories: 420,
            macros: .zero,
            loggedAt: at(8, 14),
            source: .photo
        )

        #expect(try store.entry(withID: entry.entryID)?.estimateConfidencePercent == nil)
    }

    /// The case the figure is stored rather than derived for. A repeat carries
    /// the breakdown of the meal it repeats, and averaging that breakdown would
    /// print a percentage for an estimate nobody made.
    @Test("a meal repeated from Recent claims nothing, and carries nothing to claim it with")
    func recentRepeatHasNoFigure() throws {
        let store = try makeStore()
        try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: .zero,
            loggedAt: at(19, 20),
            source: .photo,
            estimateConfidencePercent: 90,
            items: [
                scannedItem("Salmon", kilocalories: 240, percent: 90),
                scannedItem("Polenta", kilocalories: 150, percent: 90)
            ]
        )

        let entries = try store.recentEntries(limit: RecentMeals.entriesRead).map(\.recentValue)
        let recent = try #require(RecentMeals.list(from: entries).first)

        // The rows repeat whole — same names, same figures — and the
        // confidences are the one thing left behind.
        #expect(recent.items.count == 2)
        #expect(recent.items.allSatisfy { $0.confidence == nil })
        #expect(EstimateConfidence.percent(of: recent.items.map(\.confidence)) == nil)

        let model = LogFlowModel(store: store, now: { at(15, 5) })
        #expect(model.log(recent))

        let repeated = try #require(try store.entries(on: at(15, 5)).first { $0.source == .recent })
        #expect(repeated.estimateConfidencePercent == nil)
    }

    /// `update` has no default for the figure, so a caller that re-priced a
    /// meal has to say what the model now thinks of it — including that it does
    /// not know.
    @Test("a re-priced meal cannot keep a figure the new numbers were not about")
    func updateRewritesTheFigure() throws {
        let store = try makeStore()
        let entry = try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: .zero,
            loggedAt: at(19, 20),
            source: .photo,
            estimateConfidencePercent: 90,
            items: [scannedItem("Salmon", kilocalories: 240, percent: 90)]
        )

        try store.update(
            entry,
            title: entry.title,
            kilocalories: 390,
            macros: .zero,
            advice: nil,
            estimateConfidencePercent: nil,
            items: [scannedItem("Salmon", kilocalories: 170, percent: nil)]
        )

        #expect(try store.entry(withID: entry.entryID)?.estimateConfidencePercent == nil)
    }
}

// MARK: - The figure on a draft

/// How the figure moves while the user is still working on a result screen.
@Suite("Accuracy on a draft")
struct AccuracyDraftTests {

    private func item(_ name: String, kilocalories: Int, percent: Int?) -> RecognisedItem {
        RecognisedItem(
            name: name,
            kilocalories: kilocalories,
            confidence: percent.map { ItemConfidence(estimatePercent: $0) },
            note: .text(amount: .estimated)
        )
    }

    private func draft(_ items: [RecognisedItem]) -> MealResultDraft {
        MealResultDraft(
            title: "A meal",
            kilocalories: items.reduce(0) { $0 + $1.kilocalories },
            macros: .zero,
            estimateConfidencePercent: EstimateConfidence.percent(of: items.map(\.confidence)),
            items: items,
            label: .lunch,
            isLabelUserSet: false,
            isFavourite: false
        )
    }

    @Test("a draft's figure is the average of the rows it holds")
    func averagesItsRows() {
        let subject = draft([
            item("Rice", kilocalories: 300, percent: 90),
            item("Curry", kilocalories: 400, percent: 50)
        ])

        #expect(subject.estimateConfidencePercent == 70)
    }

    /// A row the user threw out is not part of this meal, so what the model
    /// said about it is not part of how sure it is about this meal.
    @Test("removing a row re-averages over what is left")
    func removalReAverages() throws {
        var subject = draft([
            item("Rice", kilocalories: 300, percent: 90),
            item("Curry", kilocalories: 400, percent: 50)
        ])

        subject.removeItem(try #require(subject.items.last).id)

        #expect(subject.items.count == 1)
        #expect(subject.estimateConfidencePercent == 90)
    }

    /// The confidence went with the old words. Leaving it would let a rewritten
    /// line go on vouching for itself until a re-analysis happened to replace
    /// it — the same reason the row's calorie figure stops being drawn.
    @Test("rewriting a row drops the confidence that described the old words")
    func editClearsTheRowsConfidence() {
        var subject = draft([
            item("Rice", kilocalories: 300, percent: 90),
            item("Curry", kilocalories: 400, percent: 50)
        ])
        let rice = subject.items[0].id

        subject.editItem(rice, to: "Rice, 300 g raw")

        #expect(subject.items[0].confidence == nil)
        #expect(subject.estimateConfidencePercent == 50)
    }

    /// An added row was never estimated and never priced, so it counts for
    /// nothing rather than dragging the average to zero.
    @Test("adding a row leaves the figure alone")
    func additionCountsForNothing() {
        var subject = draft([item("Rice", kilocalories: 300, percent: 90)])

        subject.addItem("A fried egg")

        #expect(subject.items.count == 2)
        #expect(subject.estimateConfidencePercent == 90)
    }

    /// A splice: the untouched row keeps its own answer, the corrected row
    /// takes the reply's, and the meal is the average of both.
    @Test("a re-analysis moves the figure only where the model was asked again")
    func spliceReAverages() throws {
        var subject = draft([
            item("Rice", kilocalories: 300, percent: 90),
            item("Curry", kilocalories: 400, percent: 50)
        ])
        subject.editItem(subject.items[1].id, to: "Chicken curry, 400 g")

        // The reply answers about the corrected row alone, which is all the
        // request asked about.
        let reply = MealEstimate(
            title: "Chicken curry",
            kilocalories: 420,
            macros: .zero,
            items: [item("Chicken curry, 400 g", kilocalories: 420, percent: 80)]
        )

        let merged = try #require(subject.applying(reply))

        #expect(merged.items[0].confidence?.estimatePercent == 90)
        #expect(merged.items[1].confidence?.estimatePercent == 80)
        #expect(merged.estimateConfidencePercent == 85)
    }

    /// Every row changed, so the reply describes the whole meal and replaces it
    /// wholesale — the figure with it.
    @Test("a whole replacement takes the new estimate's figure")
    func wholeReplacement() {
        var subject = draft([item("Rice", kilocalories: 300, percent: 90)])
        subject.editItem(subject.items[0].id, to: "Basmati rice, 300 g")

        let reply = MealEstimate(
            title: "Basmati rice",
            kilocalories: 330,
            macros: .zero,
            items: [item("Basmati rice, 300 g", kilocalories: 330, percent: 60)]
        )

        #expect(subject.applying(reply)?.estimateConfidencePercent == 60)
    }

    /// A meal the model answered nothing readable about draws nothing at all,
    /// on every screen, exactly as it did before this existed.
    @Test("a draft whose rows answered nothing has no figure")
    func noAnswersNoFigure() {
        let subject = draft([
            item("Rice", kilocalories: 300, percent: nil),
            item("Curry", kilocalories: 400, percent: nil)
        ])

        #expect(subject.estimateConfidencePercent == nil)
    }
}

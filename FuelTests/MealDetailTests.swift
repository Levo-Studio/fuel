import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Meal detail

/// The result screen opened on a meal that is already in the store: what it
/// writes back and when, what a re-analysis costs, and what `Delete` takes.
///
/// **Nothing here reaches a network or a Keychain.** Both are injected — see
/// `AILogStandIns` — so every test runs on the same evidence whatever the
/// machine's connection is doing, and no test needs a keychain-access group.
@Suite("Meal detail")
@MainActor
struct MealDetailTests {

    // MARK: - Fixtures

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    /// A meal in the store, logged the way a photo scan logs one.
    @discardableResult
    private func logMeal(
        in store: FuelStore,
        at moment: Date = at(19, 20),
        items: [RecognisedItem] = MealDetailTests.twoItems,
        source: EntrySource = .photo,
        capturedPhotoData: Data? = nil,
        typedSentence: String? = nil
    ) throws -> FoodEntry {
        try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
            loggedAt: moment,
            source: source,
            advice: "Plenty of protein and healthy fats.",
            items: items,
            capturedPhotoData: capturedPhotoData,
            typedSentence: typedSentence
        )
    }

    private static let twoItems = [
        RecognisedItem(
            name: "Salmon fillet, fried",
            kilocalories: 240,
            note: .photo(confidence: .confident, approximateGrams: 150)
        ),
        RecognisedItem(
            name: "Polenta",
            kilocalories: 150,
            note: .photo(confidence: .confident, approximateGrams: 180)
        ),
    ]

    /// A meal the model priced without splitting it much — the case where the
    /// remove mark has nothing it is allowed to do.
    private static let oneItem = [
        RecognisedItem(
            name: "Salmon fillet, fried",
            kilocalories: 240,
            note: .photo(confidence: .confident, approximateGrams: 150)
        )
    ]

    private func makeModel(
        entry: FoodEntry,
        store: FuelStore,
        client: ScriptedClient,
        keys: any MealKeyPresence = StoredKey()
    ) throws -> MealDetailModel {
        let model = MealDetailModel(
            entryID: entry.entryID,
            store: store,
            client: client,
            keys: keys,
            provider: .claude,
            // The four analysis steps are paced for the eye, not for the
            // request. Walking them instantly keeps the tests about outcomes.
            pace: {}
        )
        // Unwrapped by hand rather than through `#require`: the macro puts the
        // expression in a closure it wants `Sendable`, and a main-actor model
        // is not one.
        guard let model else { throw FixtureFailure.noStoredMeal }
        return model
    }

    /// The fixture could not be built, which means the store did not keep the
    /// meal the test had just logged.
    private enum FixtureFailure: Error {
        case noStoredMeal
    }

    /// What the model comes back with once the user has corrected one line.
    ///
    /// **One row, because one row is what it was asked about.** A re-analysis
    /// sends the rows the user rewrote and nothing else, so a reply naming the
    /// salmon nobody touched would be a reply to a question that was never put.
    private static let reestimate = MealEstimate(
        title: "Polenta, raw 50 g",
        kilocalories: 80,
        macros: MacroTotals(protein: 2, carbs: 17, fat: 1),
        items: [
            RecognisedItem(name: "Polenta, raw 50 g", kilocalories: 80, note: .text(amount: .recognised))
        ]
    )

    // MARK: - Opening

    @Test("the screen opens on the meal the row was tapped on")
    func opensOnTheStoredMeal() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.stage == .detail)
        #expect(model.draft.title == "Salmon with polenta")
        #expect(model.draft.kilocalories == 460)
        // The advisor line the meal was logged with, drawn again rather than
        // asked for again — a second request would spend the user's credit to
        // be told what they have already read.
        #expect(model.draft.advice == "Plenty of protein and healthy fats.")
        #expect(model.draft.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
        #expect(model.draft.items.map(\.name) == ["Salmon fillet, fried", "Polenta"])
        #expect(model.draft.label == .dinner)
        // Nothing has changed yet, so the footer is the caller's verb.
        #expect(model.draft.hasItemEdits == false)
    }

    @Test("a camera-mode meal decodes its stored photo and carries no sentence")
    func opensWithAStoredPhoto() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store, source: .photo, capturedPhotoData: try onePixelJPEG())
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.photo != nil)
        #expect(model.typedSentence == nil)
    }

    @Test("a text-mode meal carries its typed sentence and no photo")
    func opensWithAStoredSentence() throws {
        let store = try makeStore()
        let entry = try logMeal(
            in: store,
            source: .text,
            typedSentence: "2 eggs with 200g cottage cheese and polenta"
        )
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.typedSentence == "2 eggs with 200g cottage cheese and polenta")
        #expect(model.photo == nil)
    }

    @Test("a Recent-sourced meal carries neither a photo nor a sentence")
    func openedFromRecentHasNoLedeContent() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store, source: .recent)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.photo == nil)
        #expect(model.typedSentence == nil)
    }

    @Test("a meal logged before the field existed carries neither, the same as Recent")
    func preExistingMealHasNoLedeContent() throws {
        // Nothing distinguishes this row from one a build before this feature
        // wrote: `capturedPhotoData` and `typedSentence` are both optional
        // with no default that back-fills them, so an older row and a
        // Recent-sourced one decode to the same `nil, nil` — which is the
        // whole point of the lightweight migration this leans on.
        let store = try makeStore()
        let entry = try logMeal(in: store, source: .photo)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.photo == nil)
        #expect(model.typedSentence == nil)
    }

    @Test("a meal that is not in the store has no screen")
    func missingMealHasNoScreen() throws {
        let store = try makeStore()

        #expect(
            MealDetailModel(
                entryID: UUID(),
                store: store,
                client: ScriptedClient(answer: .success(Self.reestimate)),
                keys: StoredKey(),
                provider: .claude,
                pace: {}
            ) == nil
        )
    }

    // MARK: - The footer's verb

    /// `MealResultView.primaryAction` reads exactly this flag, and it is the
    /// one thing the screen decides for itself rather than taking as a
    /// parameter — so what the footer says is what this flag is.
    @Test("the footer's verb is the caller's until an item changes and Re-analyse after")
    func footerVerbFollowsTheEdits() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))
        #expect(model.draft.hasItemEdits == false)

        let polenta = try #require(model.draft.items.last?.id)
        model.editItem(polenta, to: "Polenta, raw 50 g")

        #expect(model.draft.hasItemEdits)
        // Two different words in the same place, which is the whole point of
        // the swap.
        #expect(MealDetailCopy.delete != MealResultCopy.reanalyse)
    }

    @Test("a removed row is stored at once and an added one waits for the model")
    func removingIsWrittenThroughAndAddingIsNot() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        let polenta = try #require(model.draft.items.last?.id)
        model.removeItem(polenta)
        #expect(model.draft.items.count == 1)
        // Nothing is pending: the row is out of the database already, so
        // `‹ Back` has nothing to warn about and the footer has nothing to ask
        // the model.
        #expect(model.draft.hasItemEdits == false)
        #expect(model.draft.canReanalyse == false)
        let stored = try #require(try store.entry(withID: entry.entryID))
        #expect(stored.items.map(\.name) == ["Salmon fillet, fried"])
        #expect(stored.kilocalories == 310)

        // An added row is the other case: it is text nobody has priced, so it
        // stays on the screen until a re-analysis answers for it.
        model.addItem("Olive oil, 1 tbsp")
        #expect(model.draft.items.count == 2)
        #expect(model.draft.hasItemEdits)
        #expect(model.draft.canReanalyse)
        #expect(try store.entry(withID: entry.entryID)?.items.count == 1)
    }

    /// An edited list with the old figures over it is not a meal anybody
    /// estimated, so it does not reach the store until the re-analysis does.
    @Test("an item edit alone writes nothing")
    func itemEditsAreNotWrittenBack() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        let polenta = try #require(model.draft.items.last?.id)
        model.editItem(polenta, to: "Polenta, raw 50 g")
        model.addItem("Olive oil, 1 tbsp")

        let stored = try #require(try store.entry(withID: entry.entryID))
        #expect(stored.items.map(\.name) == ["Salmon fillet, fried", "Polenta"])
        #expect(stored.kilocalories == 460)
    }

    // MARK: - The label and the favourite mark

    @Test("cycling the label writes it through as the user's own")
    func cyclingTheLabelWritesThrough() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))
        #expect(model.draft.label == .dinner)

        model.cycleLabel()

        #expect(model.draft.label == .breakfast)
        #expect(model.draft.isLabelUserSet)
        let stored = try #require(try store.entry(withID: entry.entryID))
        #expect(stored.label == .breakfast)
        // Marked as theirs, so re-deriving the day leaves it alone.
        #expect(stored.isLabelUserSet)
    }

    @Test("the favourite mark writes through")
    func favouriteWritesThrough() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))
        #expect(model.draft.isFavourite == false)

        model.toggleFavourite()

        #expect(model.draft.isFavourite)
        #expect(try store.entry(withID: entry.entryID)?.isFavourite == true)
    }

    // MARK: - Re-analysing

    /// The one the write-back exists for: the meal is re-priced, not logged a
    /// second time.
    @Test("a re-analysis updates the stored meal rather than adding a second one")
    func reanalysisUpdatesTheStoredMeal() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let client = ScriptedClient(answer: .success(Self.reestimate))
        let model = try makeModel(entry: entry, store: store, client: client)

        let polenta = try #require(model.draft.items.last?.id)
        model.editItem(polenta, to: "Polenta, raw 50 g")
        await model.reanalysing()

        #expect(client.requests == 1)
        #expect(client.lastText == "Polenta, raw 50 g")
        #expect(model.stage == .detail)
        // 240 for the row nobody touched, 80 for the one the model was asked
        // about.
        #expect(model.draft.kilocalories == 320)
        #expect(model.draft.hasItemEdits == false)

        let day = try store.entries(on: at(19, 20))
        #expect(day.count == 1)
        let stored = try #require(day.first)
        #expect(stored.entryID == entry.entryID)
        #expect(stored.kilocalories == 320)
        // **What reaches the database is the composed meal, not the reply.**
        // The reply answered for one line, so the meal keeps its own name and
        // its own macros, and the untouched row keeps the weight the
        // photograph gave it.
        #expect(stored.title == "Salmon with polenta")
        #expect(stored.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
        #expect(stored.items.map(\.name) == ["Salmon fillet, fried", "Polenta, raw 50 g"])
        #expect(stored.items.first?.note == .photo(confidence: .confident, approximateGrams: 150))
        // The meal was eaten when it was eaten, and it is still the photo entry
        // the day list draws.
        #expect(stored.loggedAt == at(19, 20))
        #expect(stored.source == .photo)
    }

    @Test("a re-analysis keeps the label and the favourite mark the user set")
    func reanalysisKeepsTheUsersChoices() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        model.cycleLabel()
        model.toggleFavourite()
        let polenta = try #require(model.draft.items.last?.id)
        model.editItem(polenta, to: "Polenta, raw 50 g")
        await model.reanalysing()

        #expect(model.draft.label == .breakfast)
        #expect(model.draft.isLabelUserSet)
        #expect(model.draft.isFavourite)
        let stored = try #require(try store.entry(withID: entry.entryID))
        #expect(stored.label == .breakfast)
        #expect(stored.isFavourite)
    }

    @Test("an unchanged breakdown makes no request")
    func reanalysingWithoutAnEditIsRefused() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let client = ScriptedClient(answer: .success(Self.reestimate))
        let model = try makeModel(entry: entry, store: store, client: client)

        await model.reanalysing()

        #expect(client.requests == 0)
        #expect(model.stage == .detail)
        #expect(model.draft.kilocalories == 460)
    }

    /// The pin the BYOK rule earns: a screen with no key behind it does not
    /// spend a request finding out.
    @Test("with no key stored a re-analysis makes no request and keeps the edits")
    func reanalysingWithoutAKey() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let client = ScriptedClient(answer: .success(Self.reestimate))
        let keys = MutableKeys(hasKey: true)
        let model = try makeModel(entry: entry, store: store, client: client, keys: keys)

        model.addItem("Olive oil, 1 tbsp")
        // The key goes away in Settings while the screen is up.
        keys.hasKey = false
        // Driven through the helper, not through a bare `reanalyse()`: that
        // returns before its task would have run, so the request count below
        // would read zero whether the guard was there or not and could never go
        // red. Waiting the way a real re-analysis is waited on is what makes it
        // an assertion.
        await model.reanalysing()

        #expect(client.requests == 0)
        #expect(model.stage == .failed(.invalidKey))
        #expect(try store.entry(withID: entry.entryID)?.kilocalories == 460)

        model.dismissFailure()
        #expect(model.stage == .detail)
        #expect(model.draft.items.count == 3)
        #expect(model.draft.hasItemEdits)
    }

    @Test("a re-analysis that fails keeps the meal and its edits")
    func reanalysisThatFails() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let client = ScriptedClient(answer: .failure(.network))
        let model = try makeModel(entry: entry, store: store, client: client)

        model.addItem("Olive oil, 1 tbsp")
        await model.reanalysing()

        #expect(model.stage == .failed(.retry(.transport)))
        #expect(try store.entry(withID: entry.entryID)?.kilocalories == 460)

        model.dismissFailure()
        #expect(model.stage == .detail)
        #expect(model.draft.hasItemEdits)
    }

    @Test("trying a failed re-analysis again sends the edited list")
    func retryingAReanalysis() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let client = ScriptedClient(answers: [.failure(.network), .success(Self.reestimate)])
        let model = try makeModel(entry: entry, store: store, client: client)

        let polenta = try #require(model.draft.items.last?.id)
        model.editItem(polenta, to: "Polenta, raw 50 g")
        await model.reanalysing()
        #expect(model.stage == .failed(.retry(.transport)))

        model.retry()
        while case .analysing = model.stage {
            await Task.yield()
        }

        #expect(client.requests == 2)
        #expect(client.lastText == "Polenta, raw 50 g")
        #expect(model.stage == .detail)
        #expect(try store.entry(withID: entry.entryID)?.kilocalories == 320)
    }

    /// The bug this pins, same shape as its counterpart in `CameraLogTests`
    /// and `TextLogTests`: `cancelReanalysis()` cancelled the `Task` but left
    /// the run current, so a re-analysis that happened to complete in the
    /// window between the tap and the continuation resuming still passed
    /// `isCurrent` — and wrote a fresh estimate over a meal the user had just
    /// stopped re-analysing, on the one of the three models with no test
    /// exercising the race. `GatedClient` holds the answer open past the
    /// cancel and releases it afterwards, which is the only way to put a test
    /// in that window.
    @Test("a re-analysis that completes after CANCEL does not overwrite the meal")
    func cancelledReanalysisDoesNotOverwriteTheStoredMeal() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let client = GatedClient(answers: [.success(Self.reestimate)])
        let built = MealDetailModel(
            entryID: entry.entryID,
            store: store,
            client: client,
            keys: StoredKey(),
            provider: .claude,
            pace: {}
        )
        guard let model = built else { throw FixtureFailure.noStoredMeal }

        let polenta = try #require(model.draft.items.last?.id)
        model.editItem(polenta, to: "Polenta, raw 50 g")
        model.reanalyse()
        while client.requests < 1 { await Task.yield() }

        model.cancelReanalysis()
        #expect(model.stage == .detail)

        // The request the user backed out of answers anyway.
        client.release(0)
        for _ in 0..<50 { await Task.yield() }

        #expect(model.stage == .detail)
        #expect(model.draft.kilocalories == 460)
        #expect(try store.entry(withID: entry.entryID)?.kilocalories == 460)
    }

    // MARK: - Leaving with edits

    /// `‹ Back` confirms once the breakdown has been changed, and the dialog it
    /// raises is `MealResultView`'s. What it says has to be this screen's: on a
    /// meal that is already in the store nothing is discarded and the meal
    /// survives either answer, so the estimate wording would be false twice.
    /// This is what goes red if the detail screen is ever pointed back at it.
    @Test("leaving an edited meal asks about the changes, not about an estimate")
    func backConfirmationNamesTheChanges() {
        #expect(MealDetailCopy.discardEditsConfirmation.title != MealResultCopy.discardConfirmation.title)
        #expect(MealDetailCopy.discardEditsConfirmation.confirm != MealResultCopy.discardConfirmation.confirm)
    }

    // MARK: - Deleting the meal

    /// The corner button's own confirmation — one sentence and two words, not
    /// the edit-discard dialog's wording. The two are easy to reach for
    /// interchangeably since both sit behind a destructive-looking control on
    /// this same screen; this is what goes red if `deleteCorner` is ever
    /// pointed at `discardEditsConfirmation` instead, or the other way round.
    @Test("the delete confirmation is one sentence, with Delete and Keep as the two answers")
    func deleteConfirmationCopy() {
        #expect(MealDetailCopy.deleteTitle == "Delete this meal?")
        #expect(MealDetailCopy.deleteConfirm == "Delete")
        #expect(MealDetailCopy.deleteCancel == "Keep")
        #expect(MealDetailCopy.deleteTitle != MealDetailCopy.discardEditsConfirmation.title)
        #expect(MealDetailCopy.deleteCancel != MealDetailCopy.discardEditsConfirmation.cancel)
    }

    // MARK: - The last row

    /// The last row of a breakdown cannot be thrown out, so the state the
    /// previous finding was about — an emptied list, a dead `Re-analyse`, and
    /// `Delete` gone from the screen with it — cannot be reached at all.
    ///
    /// A refused removal marks nothing: the estimate is not stale, because
    /// nothing happened to it.
    @Test("the last row of a breakdown cannot be thrown out")
    func theLastRowCannotBeRemoved() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store, items: Self.oneItem)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        // What the row reads to decide whether to draw the remove mark at all.
        #expect(model.draft.canRemoveItems == false)

        let only = try #require(model.draft.items.first?.id)
        model.removeItem(only)

        #expect(model.draft.items.count == 1)
        #expect(model.draft.hasItemEdits == false)
        #expect(model.draft.canReanalyse == false)
    }

    @Test("the mark comes back as soon as there is more than one row")
    func removingIsOfferedAgainWithTwoRows() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))
        #expect(model.draft.items.count == 2)
        #expect(model.draft.canRemoveItems)

        let polenta = try #require(model.draft.items.last?.id)
        model.removeItem(polenta)

        #expect(model.draft.items.count == 1)
        // One row left, so the mark is gone and the list cannot go to nothing.
        #expect(model.draft.canRemoveItems == false)
    }

    /// The reachability the finding asked for, from the other end: a meal whose
    /// breakdown nobody has touched offers `Delete`, and it works.
    @Test("a meal with one row still offers Delete and it works")
    func singleRowMealStillOffersDelete() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store, items: Self.oneItem)
        let client = ScriptedClient(answer: .success(Self.reestimate))
        let model = try makeModel(entry: entry, store: store, client: client)

        let only = try #require(model.draft.items.first?.id)
        model.removeItem(only)

        // The footer is the caller's own action, not the swap.
        #expect(model.draft.canReanalyse == false)

        // And a press that got through anyway sends nothing.
        await model.reanalysing()
        #expect(client.requests == 0)
        #expect(model.stage == .detail)

        #expect(model.delete())
        #expect(try store.entry(withID: entry.entryID) == nil)
    }

    /// An estimate that arrived with no breakdown at all is untouched by the
    /// rule: nothing has been changed, so the footer was already the caller's.
    @Test("a meal that never had a breakdown is not offered a re-analysis either")
    func mealWithoutABreakdownOffersNoReanalysis() throws {
        let store = try makeStore()
        let entry = try store.log(
            title: "Espresso, banana",
            kilocalories: 110,
            macros: MacroTotals(protein: 2, carbs: 24, fat: 1),
            loggedAt: at(15, 5),
            source: .recent
        )
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.draft.items.isEmpty)
        #expect(model.draft.hasItemEdits == false)
        #expect(model.draft.canReanalyse == false)
    }

    // MARK: - Deleting

    /// The confirmation is the view's `@State` and `delete()` is what answering
    /// it calls, so what this pins is the other half: nothing else the screen
    /// offers can take the meal, and dismissing the dialog runs none of it.
    @Test("nothing but Delete takes the meal, so a dismissed confirmation costs nothing")
    func onlyDeleteRemovesTheMeal() async throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        // Every control on the screen except the footer's own, including the
        // one that empties the list.
        model.cycleLabel()
        model.toggleFavourite()
        for item in model.draft.items {
            model.removeItem(item.id)
        }
        model.addItem("Olive oil, 1 tbsp")
        await model.reanalysing()

        #expect(try store.entry(withID: entry.entryID) != nil)
        #expect(try store.entries(on: at(19, 20)).count == 1)
    }

    @Test("Delete takes the meal out of its day and reports that it went")
    func deleteRemovesTheMeal() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        try store.log(title: "Toast", kilocalories: 200, macros: .zero, loggedAt: at(8, 14), source: .text)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        #expect(model.delete())

        #expect(try store.entry(withID: entry.entryID) == nil)
        #expect(try store.entries(on: at(19, 20)).map(\.title) == ["Toast"])
    }

    /// A meal deleted with an edited list still goes: the edits were never in
    /// the store, and there is nothing left to write them to.
    @Test("Delete works on a meal whose breakdown was edited")
    func deleteAfterEditing() throws {
        let store = try makeStore()
        let entry = try logMeal(in: store)
        let model = try makeModel(entry: entry, store: store, client: ScriptedClient(answer: .success(Self.reestimate)))

        model.addItem("Olive oil, 1 tbsp")
        #expect(model.delete())

        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }
}

// MARK: - Driving a re-analysis

private extension MealDetailModel {

    /// Taps `Re-analyse` and waits for it to settle.
    ///
    /// `reanalyse` deliberately returns before the request does — the interface
    /// has to draw the first analysis step immediately — so a test needs a way
    /// to wait. Polling the stage rather than exposing the task keeps the
    /// production type free of a hook that exists only for tests.
    func reanalysing() async {
        reanalyse()
        while case .analysing = stage {
            await Task.yield()
        }
    }
}

// MARK: - Stand-ins

/// One opaque pixel, compressed through the same path `CameraLogModel` sends
/// a scan through — a stand-in for `capturedPhotoData`, which on a real entry
/// is written down through that same call. What is under test where this is
/// used is the decode on the way back out, not the compression itself, which
/// has its own suite.
@MainActor
private func onePixelJPEG() throws -> Data {
    let size = CGSize(width: 1, height: 1)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
        context.fill(CGRect(origin: .zero, size: size))
    }
    return try MealPhotoCompressor.compress(image).jpegData
}

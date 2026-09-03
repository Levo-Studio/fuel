import Foundation
import Testing

@testable import Fuel

// MARK: - Text log

/// The text half of the log flow: the keyless tab, the estimate, the failure
/// mapping, the edits screen 15 allows, and what leaving without adding costs.
///
/// **Nothing here reaches a network or a Keychain.** Both are injected — see
/// `AILogStandIns` — so every test runs on the same evidence whatever the
/// machine's connection is doing, and no test needs a keychain-access group.
@Suite("Text log")
@MainActor
struct TextLogTests {

    // MARK: - Fixtures

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    private func makeModel(
        store: FuelStore,
        client: ScriptedClient,
        keys: any MealKeyPresence = StoredKey(),
        at moment: Date = at(19, 20)
    ) -> TextLogModel {
        TextLogModel(
            store: store,
            client: client,
            keys: keys,
            provider: .claude,
            now: { moment },
            // The four analysis steps are paced for the eye, not for the
            // request. Walking them instantly keeps the tests about outcomes.
            pace: {}
        )
    }

    private static let sentence = "2 eggs with 200g cottage cheese and polenta"

    private static let estimate = MealEstimate(
        title: "Eggs with cottage cheese and polenta",
        kilocalories: 628,
        macros: MacroTotals(protein: 47, carbs: 63, fat: 25),
        items: [
            RecognisedItem(name: "2 eggs", kilocalories: 158, note: .text(amount: .recognised)),
            RecognisedItem(name: "Polenta", kilocalories: 150, note: .text(amount: .estimated)),
        ]
    )

    /// What the model comes back with once the user has corrected the list.
    private static let reestimate = MealEstimate(
        title: "Eggs with cottage cheese and polenta",
        kilocalories: 520,
        macros: MacroTotals(protein: 44, carbs: 41, fat: 23),
        items: [
            RecognisedItem(name: "2 eggs", kilocalories: 158, note: .text(amount: .recognised)),
            RecognisedItem(name: "Polenta, raw 50 g", kilocalories: 180, note: .text(amount: .recognised)),
        ]
    )

    // MARK: - No key

    @Test("with no key stored the tab is disabled and no request is made")
    func noKeyDisablesTheTab() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client, keys: NoKeys())
        model.typedText = Self.sentence

        model.refreshAvailability()
        #expect(model.stage == .noKey)

        // The field is not drawn in this state, but the model must refuse the
        // estimate anyway: the key can go away between the draw and the tap,
        // and a tab that looks unavailable and still sends the request would
        // pass a test that only read the stage.
        //
        // Awaited rather than tapped and read: `analyse` returns before any
        // request would, so a counter read straight after the tap is zero
        // whether the guard is there or not. Waiting for the flow to settle is
        // what makes the zero mean something.
        await model.estimating()

        #expect(model.stage == .noKey)
        #expect(client.requests == 0)
        #expect(model.draft == nil)
    }

    @Test("a key appearing enables the tab again")
    func aKeyEnablesTheTab() throws {
        let keys = MutableKeys(hasKey: false)
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            keys: keys
        )

        model.refreshAvailability()
        #expect(model.stage == .noKey)

        keys.hasKey = true
        model.refreshAvailability()
        #expect(model.stage == .entry)
    }

    // MARK: - An empty field

    @Test("a field holding nothing but space costs no request", arguments: ["", "   ", "\n \n"])
    func emptyFieldIsRefused(_ typed: String) async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)
        model.typedText = typed

        await model.estimating()

        #expect(model.stage == .entry)
        #expect(client.requests == 0)
    }

    @Test("the sentence is sent without the space around it")
    func theSentenceIsTrimmed() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)
        model.typedText = "  \(Self.sentence)\n"

        await model.estimating()

        #expect(client.lastText == Self.sentence)
    }

    // MARK: - A successful estimate

    @Test("a successful estimate produces the result state with its items")
    func successfulEstimate() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)
        model.typedText = Self.sentence

        await model.estimating()

        #expect(model.stage == .result)
        #expect(client.requests == 1)
        let draft = try #require(model.draft)
        #expect(draft.title == "Eggs with cottage cheese and polenta")
        #expect(draft.kilocalories == 628)
        #expect(draft.macros == MacroTotals(protein: 47, carbs: 63, fat: 25))
        #expect(draft.items.map(\.name) == ["2 eggs", "Polenta"])
        // A typed amount was either given or it was not, which is the whole of
        // what screen 15 prints under an item.
        #expect(draft.items.map(\.note) == [
            .text(amount: .recognised),
            .text(amount: .estimated),
        ])
    }

    @Test("the result's label is the one the day rule gives that moment")
    func provisionalLabel() async throws {
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            at: at(19, 20)
        )
        model.typedText = Self.sentence

        await model.estimating()

        #expect(model.draft?.label == .dinner)
        #expect(model.draft?.isLabelUserSet == false)
    }

    /// The case a clock stub cannot pass.
    ///
    /// 19:20 above is `.dinner` under the day rule *and* under a naive
    /// `labelFor(hour)` — the stub the export ships for its click-through and
    /// that `design/Fuel Design Notes.md` warns is not the spec — so that test
    /// alone would stay green through exactly the fork it is named for. 16:00
    /// sits in the gap between the lunch and dinner windows: a clock says
    /// Snack, and the rule says Lunch, because the lunch window passed unused
    /// and dinner has not been reached. See `design/Fuel Design Notes.md`,
    /// "The meal label", second consequence.
    ///
    /// It proves the delegation, not the rule. The rule itself is
    /// `MealLabeler`'s and is covered against it directly in `MealLabelTests`.
    @Test("an entry at 16:00 on a day with no lunch is lunch, not a snack")
    func provisionalLabelUsesTheDayRuleAndNotTheClock() async throws {
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            at: at(16, 0)
        )
        model.typedText = Self.sentence

        await model.estimating()

        #expect(model.draft?.label == .lunch)
    }

    // MARK: - Failures

    @Test("each provider error maps to the state that is drawn for it", arguments: [
        (AIError.invalidKey, AnalysisFailure.invalidKey),
        (AIError.missingKey, AnalysisFailure.invalidKey),
        (AIError.network, AnalysisFailure.retry),
        (AIError.malformedResponse, AnalysisFailure.retry),
    ])
    func errorMapping(error: AIError, expected: AnalysisFailure) async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(error)))
        model.typedText = Self.sentence

        await model.estimating()

        #expect(model.stage == .failed(expected))
    }

    @Test("an exhausted balance carries the provider's own billing page")
    func noCreditCarriesItsLink() async throws {
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .failure(.noCredit(for: .claude)))
        )
        model.typedText = Self.sentence

        await model.estimating()

        #expect(model.stage == .failed(.noCredit(billingPage: AIError.billingPage(for: .claude))))
    }

    @Test("a cancelled estimate is silent, and the sentence survives it")
    func cancelledEstimateIsSilent() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(.cancelled)))
        model.typedText = Self.sentence

        await model.estimating()

        #expect(model.stage == .entry)
        #expect(model.draft == nil)
        // Someone who cancelled is back in the field they were typing in, not
        // in an empty one.
        #expect(model.typedText == Self.sentence)
    }

    @Test("a retry sends the same sentence again")
    func retrySendsTheSameSentence() async throws {
        let client = ScriptedClient(answer: .failure(.network))
        let model = makeModel(store: try makeStore(), client: client)
        model.typedText = Self.sentence

        await model.estimating()
        #expect(model.stage == .failed(.retry))

        model.retry()
        while case .analysing = model.stage {
            await Task.yield()
        }

        #expect(client.requests == 2)
        #expect(client.lastText == Self.sentence)
    }

    @Test("the advice after a failure never tells a typist to take a photo")
    func failureHintsAreToldApart() {
        // Both hints name what the user did, so neither may be shown to the
        // other mode. The words themselves live in the catalog; what is pinned
        // here is that the two are not the same string.
        #expect(
            AnalysisCopy.failureHint(.retry, mode: .text)
                != AnalysisCopy.failureHint(.retry, mode: .photo)
        )
        #expect(
            AnalysisCopy.failureHint(.invalidKey, mode: .text)
                != AnalysisCopy.failureHint(.invalidKey, mode: .photo)
        )
        // An exhausted balance names only the account, which is the same
        // sentence either way.
        let billing = AnalysisFailure.noCredit(billingPage: AIError.billingPage(for: .claude))
        #expect(
            AnalysisCopy.failureHint(billing, mode: .text)
                == AnalysisCopy.failureHint(billing, mode: .photo)
        )
    }

    // MARK: - Editing the result

    @Test("the label pill cycles breakfast, lunch, snack, dinner and wraps")
    func labelPillCycles() async throws {
        // 08:10 on an empty day, so the first label is breakfast and the cycle
        // starts where the design's list does.
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            at: at(8, 10)
        )
        model.typedText = Self.sentence
        await model.estimating()

        #expect(model.draft?.label == .breakfast)

        model.cycleLabel()
        #expect(model.draft?.label == .lunch)
        #expect(model.draft?.isLabelUserSet == true)

        model.cycleLabel()
        #expect(model.draft?.label == .snack)

        model.cycleLabel()
        #expect(model.draft?.label == .dinner)

        model.cycleLabel()
        #expect(model.draft?.label == .breakfast)
    }

    @Test("the favourite toggle goes both ways")
    func favouriteToggles() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        model.typedText = Self.sentence
        await model.estimating()

        #expect(model.draft?.isFavourite == false)
        model.toggleFavourite()
        #expect(model.draft?.isFavourite == true)
        model.toggleFavourite()
        #expect(model.draft?.isFavourite == false)
    }

    // MARK: - Re-analysing

    @Test("a changed breakdown is re-estimated from the edited list, not the sentence")
    func reanalysingSendsTheEditedList() async throws {
        let client = ScriptedClient(answers: [.success(Self.estimate), .success(Self.reestimate)])
        let model = makeModel(store: try makeStore(), client: client)
        model.typedText = Self.sentence
        await model.estimating()

        let polenta = try #require(model.draft?.items.last?.id)
        model.editItem(polenta, to: "Polenta r50g")
        await model.reanalysing()

        #expect(client.requests == 2)
        #expect(client.lastText == "2 eggs, Polenta r50g")
        // The sentence itself is untouched: screen 15 still quotes it back and
        // `‹ Back` still returns to the field holding it.
        #expect(model.typedText == Self.sentence)

        #expect(model.stage == .result)
        #expect(model.draft?.kilocalories == 520)
        #expect(model.draft?.hasItemEdits == false)
    }

    @Test("an unchanged breakdown makes no request")
    func reanalysingWithoutAnEditIsRefused() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)
        model.typedText = Self.sentence
        await model.estimating()

        // Driven through the helper for the same reason the keyless test is:
        // `reanalyse()` returns before its task would have run, so a bare call
        // leaves the count below reading 1 whether the guard is there or not.
        // This is the assertion that says a screen with nothing changed cannot
        // spend the user's credit, so it has to be able to fail.
        await model.reanalysing()

        #expect(client.requests == 1)
        #expect(model.stage == .result)
    }

    @Test("with no key stored a re-analysis makes no request and keeps the draft")
    func reanalysingWithoutAKey() async throws {
        let client = ScriptedClient(answers: [.success(Self.estimate), .success(Self.reestimate)])
        let keys = MutableKeys(hasKey: true)
        let model = makeModel(store: try makeStore(), client: client, keys: keys)
        model.typedText = Self.sentence
        await model.estimating()

        model.addItem("Olive oil, 1 tbsp")
        // The key goes away in Settings while the result screen is up.
        keys.hasKey = false
        // Driven through the helper, not through a bare `reanalyse()`: that
        // returns before its task would have run, so the request count below
        // would read 1 whether the guard was there or not and could never go
        // red. Waiting the way a real re-analysis is waited on is what makes it
        // an assertion.
        await model.reanalysing()

        #expect(client.requests == 1)
        #expect(model.stage == .failed(.invalidKey))

        model.dismissFailure()
        #expect(model.stage == .result)
        #expect(model.draft?.items.count == 3)
        #expect(model.draft?.hasItemEdits == true)
    }

    // MARK: - Committing

    @Test("committing writes a text entry whose macros and items match the estimate")
    func commitWritesTheEstimate() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        model.typedText = Self.sentence
        await model.estimating()

        model.toggleFavourite()
        #expect(model.commit())

        let entries = try store.entries(on: at(19, 20))
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        // The estimate's name, not the user's wording: the sentence is what
        // was asked, and the entry records what the meal was.
        #expect(entry.title == "Eggs with cottage cheese and polenta")
        #expect(entry.kilocalories == 628)
        #expect(entry.macros == MacroTotals(protein: 47, carbs: 63, fat: 25))
        #expect(entry.isFavourite)
        #expect(entry.source == .text)
        #expect(entry.items.map(\.name) == ["2 eggs", "Polenta"])
        #expect(entry.items.map(\.kilocalories) == [158, 150])
        #expect(entry.items.map(\.note) == [
            .text(amount: .recognised),
            .text(amount: .estimated),
        ])
    }

    @Test("a label the user picked survives the commit as theirs")
    func commitKeepsTheUsersLabel() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)), at: at(19, 20))
        model.typedText = Self.sentence
        await model.estimating()

        #expect(model.draft?.label == .dinner)
        model.cycleLabel()
        #expect(model.commit())

        let entry = try #require(try store.entries(on: at(19, 20)).first)
        #expect(entry.label == .breakfast)
        #expect(entry.isLabelUserSet)
    }

    @Test("committing empties the field and returns to it")
    func commitClearsTheEntry() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        model.typedText = Self.sentence
        await model.estimating()

        #expect(model.commit())

        #expect(model.stage == .entry)
        #expect(model.draft == nil)
        #expect(model.typedText.isEmpty)
    }

    @Test("walking away from a result writes nothing")
    func leavingWritesNothing() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        model.typedText = Self.sentence
        await model.estimating()

        model.returnToEntry()

        #expect(model.stage == .entry)
        #expect(model.draft == nil)
        #expect(try store.entries(on: at(19, 20)).isEmpty)
        // `Back` is a way to the field, not a way to lose what is in it.
        #expect(model.typedText == Self.sentence)
    }

    @Test("New writes nothing either, and starts an empty entry")
    func newWritesNothing() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        model.typedText = Self.sentence
        await model.estimating()

        model.discard()

        #expect(model.stage == .entry)
        #expect(model.draft == nil)
        #expect(model.typedText.isEmpty)
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }

    @Test("a commit with nothing to commit reports failure rather than writing")
    func commitWithoutADraft() throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))

        #expect(!model.commit())
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }
}

// MARK: - Driving an estimate

private extension TextLogModel {

    /// Taps `Analyse` and waits for it to settle.
    ///
    /// `analyse` deliberately returns before the request does — the interface
    /// has to draw the first analysis step immediately — so a test needs a way
    /// to wait. Polling the stage rather than exposing the task keeps the
    /// production type free of a hook that exists only for tests.
    func estimating() async {
        analyse()
        while case .analysing = stage {
            await Task.yield()
        }
    }

    /// Taps `Re-analyse` and waits for it to settle, for the same reason.
    func reanalysing() async {
        reanalyse()
        while case .analysing = stage {
            await Task.yield()
        }
    }
}

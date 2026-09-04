import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Camera log

/// The camera half of the log flow: the keyless tab, the scan, the failure
/// mapping and the edits the result screen allows.
///
/// **Nothing here reaches a network or a camera.** Both are injected — a
/// `ScriptedClient` that answers from memory and a `MealCamera` that hands back
/// a one-pixel image — so every test runs on the same evidence whatever the
/// machine's connection or hardware is doing. `NoKeys`/`StoredKey` answer the
/// Keychain question without a keychain-access group, which is also why no test
/// here needs one.
@Suite("Camera log")
@MainActor
struct CameraLogTests {

    // MARK: - Fixtures

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    private func makeModel(
        store: FuelStore,
        client: ScriptedClient,
        keys: any MealKeyPresence = StoredKey(),
        camera: any MealCamera = StubCamera(),
        at moment: Date = at(19, 20)
    ) -> CameraLogModel {
        CameraLogModel(
            store: store,
            client: client,
            camera: camera,
            keys: keys,
            provider: .claude,
            now: { moment },
            // The four analysis steps are paced for the eye, not for the
            // request. Walking them instantly keeps the tests about outcomes.
            pace: {}
        )
    }

    private static let estimate = MealEstimate(
        title: "Salmon with polenta",
        kilocalories: 460,
        macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
        items: [
            RecognisedItem(
                name: "Salmon fillet, pan-fried",
                kilocalories: 240,
                note: .photo(confidence: .confident, approximateGrams: 150)
            ),
            RecognisedItem(
                name: "Leaf spinach",
                kilocalories: 70,
                note: .photo(confidence: .unsure, approximateGrams: 90)
            ),
        ]
    )

    /// What the model comes back with once the user has corrected the list.
    private static let reestimate = MealEstimate(
        title: "Salmon with polenta",
        kilocalories: 390,
        macros: MacroTotals(protein: 33, carbs: 21, fat: 19),
        items: [
            RecognisedItem(
                name: "Salmon fillet, pan-fried",
                kilocalories: 240,
                note: .photo(confidence: .confident, approximateGrams: 150)
            ),
            RecognisedItem(
                name: "Polenta",
                kilocalories: 150,
                note: .photo(confidence: .confident, approximateGrams: 50)
            ),
        ]
    )

    // MARK: - No key

    @Test("with no key stored the tab is disabled and no request is made")
    func noKeyDisablesTheTab() throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client, keys: NoKeys())

        model.refreshAvailability()
        #expect(model.stage == .noKey)

        // The shutter is not drawn in this state, but the model must refuse the
        // scan anyway: the key can go away between the draw and the tap.
        model.analyse(pixel())

        #expect(model.stage == .noKey)
        #expect(client.requests == 0)
        #expect(model.photo == nil)
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
        #expect(model.stage == .viewfinder)
    }

    // MARK: - A successful scan

    @Test("a successful estimate produces the result state with its items")
    func successfulScan() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)

        await model.scanning(pixel())

        #expect(model.stage == .result)
        #expect(client.requests == 1)
        let draft = try #require(model.draft)
        #expect(draft.title == "Salmon with polenta")
        #expect(draft.kilocalories == 460)
        #expect(draft.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
        #expect(draft.items.map(\.name) == ["Salmon fillet, pan-fried", "Leaf spinach"])
        #expect(draft.items.map(\.note) == [
            .photo(confidence: .confident, approximateGrams: 150),
            .photo(confidence: .unsure, approximateGrams: 90),
        ])
    }

    @Test("the scan walks all four analysis steps in the drawn order")
    func stepsRunInOrder() {
        #expect(AnalysisStep.allCases == [
            .analysingMeal,
            .identifyingIngredients,
            .estimatingAmounts,
            .calculatingNutrition,
        ])
        // Quarters, one per step, exactly as the export fills the 120×2 bar.
        #expect(AnalysisStep.allCases.map(\.progress) == [0.25, 0.5, 0.75, 1])
    }

    @Test("the result's label is the one the day rule gives that moment")
    func provisionalLabel() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client, at: at(19, 20))

        await model.scanning(pixel())

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
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client, at: at(16, 0))

        await model.scanning(pixel())

        #expect(model.draft?.label == .lunch)
    }

    // MARK: - Failures

    @Test("each provider error maps to the state that is drawn for it", arguments: [
        (AIError.invalidKey, AnalysisFailure.invalidKey),
        (AIError.missingKey, AnalysisFailure.invalidKey),
        (AIError.network, AnalysisFailure.retry(.transport)),
        (AIError.providerRefused, AnalysisFailure.retry(.provider)),
        (AIError.malformedResponse, AnalysisFailure.retry(.reply)),
        (AIError.truncatedReply, AnalysisFailure.retry(.reply)),
        (AIError.imageTooLarge, AnalysisFailure.retry(.device)),
    ])
    func errorMapping(error: AIError, expected: AnalysisFailure) async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(error)))

        await model.scanning(pixel())

        #expect(model.stage == .failed(expected))
    }

    @Test("an exhausted balance carries the provider's own billing page")
    func noCreditCarriesItsLink() async throws {
        let error = AIError.noCredit(for: .claude)
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(error)))

        await model.scanning(pixel())

        #expect(model.stage == .failed(.noCredit(billingPage: AIError.billingPage(for: .claude))))
    }

    @Test("a cancelled scan is silent, not a retry prompt")
    func cancelledScanIsSilent() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(.cancelled)))

        await model.scanning(pixel())

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        // The frame is released with the scan. Nothing of it outlives the tap.
        #expect(model.photo == nil)
    }

    @Test("no failure state can be built from a cancellation")
    func cancellationHasNoDrawnState() {
        #expect(AnalysisFailure(.cancelled) == nil)
    }

    @Test("a camera that cannot deliver a frame is a retry, not silence")
    func failedCaptureIsARetry() async throws {
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            camera: FailingCamera()
        )

        await model.capture()

        // `.device`: the shutter never produced a frame, so nothing was sent.
        #expect(model.stage == .failed(.retry(.device)))
    }

    // MARK: - Editing the result

    @Test("removing an item takes it out of the list and marks the estimate stale")
    func removingAnItem() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        let spinach = try #require(model.draft?.items.last?.id)
        #expect(model.draft?.hasItemEdits == false)

        model.removeItem(spinach)

        #expect(model.draft?.items.map(\.name) == ["Salmon fillet, pan-fried"])
        #expect(model.draft?.hasItemEdits == true)
        // Nothing is recalculated on the device: the figures above the list are
        // still the ones the model gave for the meal it was shown.
        #expect(model.draft?.kilocalories == 460)
        #expect(model.draft?.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
    }

    @Test("removing a line that is not in the list changes nothing")
    func removingAnUnknownItem() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.removeItem(UUID())

        #expect(model.draft?.items.count == 2)
        #expect(model.draft?.hasItemEdits == false)
    }

    @Test("an edited item carries the user's words and loses the model's figure")
    func editingAnItem() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        // The first of the two items is the salmon. Correcting it with a
        // weight the photograph could not give is the case the owner named.
        let salmon = try #require(model.draft?.items.first?.id)
        model.editItem(salmon, to: "  Salmon fillet, r180g  ")

        #expect(model.draft?.items.first?.name == "Salmon fillet, r180g")
        #expect(model.draft?.hasItemEdits == true)
        // The price beside it was the model's answer about a different line.
        #expect(model.draft?.isPriced(salmon) == false)
        #expect(model.draft?.isPriced(try #require(model.draft?.items.last?.id)) == true)
    }

    @Test("an empty item field changes nothing")
    func editingAnItemToNothing() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        let salmon = try #require(model.draft?.items.first?.id)
        model.editItem(salmon, to: "   ")
        model.addItem("\n")

        #expect(model.draft?.items.map(\.name) == ["Salmon fillet, pan-fried", "Leaf spinach"])
        // Emptying a row is what the remove control is for, so neither of these
        // counts as a change the user has to re-analyse.
        #expect(model.draft?.hasItemEdits == false)
    }

    @Test("an added item lands at the end of the list with no figure beside it")
    func addingAnItem() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.addItem("Olive oil, 1 tbsp")

        let items = try #require(model.draft?.items)
        #expect(items.map(\.name) == ["Salmon fillet, pan-fried", "Leaf spinach", "Olive oil, 1 tbsp"])
        #expect(model.draft?.isPriced(try #require(items.last?.id)) == false)
        #expect(model.draft?.hasItemEdits == true)
    }

    @Test("the label pill cycles breakfast, lunch, snack, dinner and wraps")
    func labelPillCycles() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        // 08:10 on an empty day, so the first label is breakfast and the cycle
        // starts where the design's list does.
        let model = makeModel(store: try makeStore(), client: client, at: at(8, 10))
        await model.scanning(pixel())

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
        await model.scanning(pixel())

        #expect(model.draft?.isFavourite == false)
        model.toggleFavourite()
        #expect(model.draft?.isFavourite == true)
        model.toggleFavourite()
        #expect(model.draft?.isFavourite == false)
    }

    // MARK: - Re-analysing

    @Test("a changed breakdown is re-estimated from the edited list, not the photograph")
    func reanalysingSendsTheEditedList() async throws {
        let client = ScriptedClient(answers: [.success(Self.estimate), .success(Self.reestimate)])
        let model = makeModel(store: try makeStore(), client: client)
        await model.scanning(pixel())

        // The second of the two items is the spinach, which is what the model
        // read the polenta as — a misrecognised line, corrected by name and by
        // weight at once.
        let spinach = try #require(model.draft?.items.last?.id)
        model.editItem(spinach, to: "Polenta r50g")
        await model.reanalysing()

        // The text estimate, which is what carries the list. A second photo
        // request would ask the model to re-derive what the user overruled.
        #expect(client.requests == 2)
        #expect(client.lastText == "Salmon fillet, pan-fried, Polenta r50g")

        #expect(model.stage == .result)
        #expect(model.draft?.kilocalories == 390)
        #expect(model.draft?.items.map(\.name) == ["Salmon fillet, pan-fried", "Polenta"])
        // The new estimate is the model's throughout, so the figures are back.
        #expect(model.draft?.hasItemEdits == false)
        #expect(model.draft?.isPriced(try #require(model.draft?.items.last?.id)) == true)
    }

    @Test("an unchanged breakdown makes no request")
    func reanalysingWithoutAnEditIsRefused() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)
        await model.scanning(pixel())

        // Driven through the helper for the same reason the keyless test is:
        // `reanalyse()` returns before its task would have run, so a bare call
        // leaves the count below reading 1 whether the guard is there or not.
        // This is the assertion that says a screen with nothing changed cannot
        // spend the user's credit, so it has to be able to fail.
        await model.reanalysing()

        #expect(client.requests == 1)
        #expect(model.stage == .result)
    }

    @Test("a re-analysis keeps the label and the favourite the user set")
    func reanalysingKeepsTheUsersChoices() async throws {
        let client = ScriptedClient(answers: [.success(Self.estimate), .success(Self.reestimate)])
        let model = makeModel(store: try makeStore(), client: client)
        await model.scanning(pixel())

        model.cycleLabel()
        model.toggleFavourite()
        let label = try #require(model.draft?.label)

        model.addItem("Olive oil, 1 tbsp")
        await model.reanalysing()

        #expect(model.draft?.label == label)
        #expect(model.draft?.isLabelUserSet == true)
        #expect(model.draft?.isFavourite == true)
    }

    @Test("with no key stored a re-analysis makes no request and keeps the draft")
    func reanalysingWithoutAKey() async throws {
        let client = ScriptedClient(answers: [.success(Self.estimate), .success(Self.reestimate)])
        let keys = MutableKeys(hasKey: true)
        let model = makeModel(store: try makeStore(), client: client, keys: keys)
        await model.scanning(pixel())

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

        // And leaving that state puts the user back on the work they had done.
        model.dismissFailure()
        #expect(model.stage == .result)
        #expect(model.draft?.items.count == 3)
        #expect(model.draft?.hasItemEdits == true)
    }

    /// The bug this pins, same shape as its counterpart in `TextLogTests`:
    /// `cancelScan()` cancelled the `Task` but left the run current, so a
    /// scan that happened to complete in the window between the tap and the
    /// continuation resuming still passed `isCurrent` and presented a result
    /// over a cancel the user had just made.
    @Test("a scan that completes after CANCEL is not presented anyway")
    func cancelIsFinalEvenIfTheAnswerArrivesAnyway() async throws {
        let client = GatedClient(answers: [.success(Self.estimate)])
        let model = CameraLogModel(
            store: try makeStore(),
            client: client,
            camera: StubCamera(),
            keys: StoredKey(),
            provider: .claude,
            now: { at(19, 20) },
            pace: {}
        )

        model.analyse(pixel())
        while client.requests < 1 { await Task.yield() }

        model.cancelScan()
        #expect(model.stage == .viewfinder)

        client.release(0)
        for _ in 0..<50 { await Task.yield() }

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
    }

    @Test("a re-analysis that fails leaves the edits where they were")
    func reanalysingThatFails() async throws {
        let client = ScriptedClient(answers: [.success(Self.estimate), .failure(.network)])
        let model = makeModel(store: try makeStore(), client: client)
        await model.scanning(pixel())

        model.addItem("Olive oil, 1 tbsp")
        await model.reanalysing()

        #expect(model.stage == .failed(.retry(.transport)))

        model.dismissFailure()
        #expect(model.stage == .result)
        #expect(model.draft?.items.map(\.name).last == "Olive oil, 1 tbsp")
        #expect(model.draft?.hasItemEdits == true)
    }

    @Test("trying a failed re-analysis again sends the list, not the frame")
    func retryingAReanalysis() async throws {
        let client = ScriptedClient(answers: [
            .success(Self.estimate),
            .failure(.network),
            .success(Self.reestimate),
        ])
        let model = makeModel(store: try makeStore(), client: client)
        await model.scanning(pixel())

        model.removeItem(try #require(model.draft?.items.last?.id))
        await model.reanalysing()
        #expect(model.stage == .failed(.retry(.transport)))

        model.retry()
        while case .analysing = model.stage {
            await Task.yield()
        }

        #expect(client.requests == 3)
        #expect(client.lastText == "Salmon fillet, pan-fried")
        #expect(model.stage == .result)
        #expect(model.draft?.hasItemEdits == false)
    }

    // MARK: - Committing

    @Test("committing writes an entry whose macros and items match the estimate")
    func commitWritesTheEstimate() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.toggleFavourite()
        #expect(model.commit())

        let entries = try store.entries(on: at(19, 20))
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.title == "Salmon with polenta")
        #expect(entry.kilocalories == 460)
        #expect(entry.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
        #expect(entry.isFavourite)
        #expect(entry.source == .photo)
        #expect(entry.items.map(\.name) == ["Salmon fillet, pan-fried", "Leaf spinach"])
        #expect(entry.items.map(\.kilocalories) == [240, 70])
        #expect(entry.items.map(\.note) == [
            .photo(confidence: .confident, approximateGrams: 150),
            .photo(confidence: .unsure, approximateGrams: 90),
        ])
    }

    @Test("committing writes the compressed frame behind the entry, not the raw one")
    func commitWritesTheCompressedPhoto() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        // The model already holds the exact bytes the scan sent — this is the
        // guard against a second, independent compression sneaking back in at
        // commit time.
        let sentToTheModel = try #require(model.capturedPhotoData)
        #expect(model.commit())

        let entry = try #require(try store.entries(on: at(19, 20)).first)
        let stored = try #require(entry.capturedPhotoData)
        #expect(stored == sentToTheModel)
        // JPEG, not the raw pixel buffer — decodable proves it round-trips as
        // an image rather than as opaque bytes that merely happen to be equal.
        #expect(UIImage(data: stored) != nil)
    }

    @Test("a re-analysis keeps the photo it did not resend")
    func reanalysisKeepsThePhoto() async throws {
        let store = try makeStore()
        let client = ScriptedClient(answers: [.success(Self.estimate), .success(Self.reestimate)])
        let model = makeModel(store: store, client: client)
        await model.scanning(pixel())
        let capturedBeforeReanalysis = try #require(model.capturedPhotoData)

        model.editItem(try #require(model.draft?.items.last?.id), to: "Polenta r50g")
        await model.reanalysing()

        #expect(model.capturedPhotoData == capturedBeforeReanalysis)
        #expect(model.commit())
        let entry = try #require(try store.entries(on: at(19, 20)).first)
        #expect(entry.capturedPhotoData == capturedBeforeReanalysis)
    }

    @Test("a label the user picked survives the commit as theirs")
    func commitKeepsTheUsersLabel() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)), at: at(19, 20))
        await model.scanning(pixel())

        #expect(model.draft?.label == .dinner)
        model.cycleLabel()
        #expect(model.commit())

        let entry = try #require(try store.entries(on: at(19, 20)).first)
        #expect(entry.label == .breakfast)
        #expect(entry.isLabelUserSet)
    }

    @Test("a label the user left alone is the store's to derive")
    func commitLeavesADerivedLabelAlone() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)), at: at(19, 20))
        await model.scanning(pixel())

        #expect(model.commit())

        let entry = try #require(try store.entries(on: at(19, 20)).first)
        #expect(entry.label == .dinner)
        #expect(!entry.isLabelUserSet)
    }

    @Test("committing returns to the viewfinder and lets the frame go")
    func commitClearsTheScan() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        #expect(model.commit())

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        #expect(model.photo == nil)
        #expect(model.capturedPhotoData == nil)
    }

    @Test("walking away from a result writes nothing")
    func discardWritesNothing() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.discard()

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        #expect(model.capturedPhotoData == nil)
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }

    @Test("discarding an edited estimate writes nothing and lets the frame go")
    func discardAfterEditingWritesNothing() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.removeItem(try #require(model.draft?.items.first?.id))
        model.addItem("Olive oil, 1 tbsp")
        model.toggleFavourite()

        // What the trash control does once the confirmation is answered. The
        // confirmation itself is the screen's state, not the model's: nothing
        // here runs until it is confirmed, which is what makes backing out of
        // it safe.
        model.discard()

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        #expect(model.photo == nil)
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }

    @Test("a commit with nothing to commit reports failure rather than writing")
    func commitWithoutADraft() throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))

        #expect(!model.commit())
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }

    // MARK: - The context line

    @Test("a scan with nothing typed under the viewfinder carries no context")
    func contextStartsEmpty() throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))

        #expect(model.context.isEmpty)
        #expect(model.photoContext == nil)
    }

    @Test("a field holding only whitespace is a field nothing was typed into")
    func whitespaceIsNoContext() throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))

        model.context = "   \n "

        #expect(model.photoContext == nil)
    }

    @Test("what the request would carry is the typed line, trimmed")
    func contextIsTrimmed() throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))

        model.context = "  Fried in butter, not oil\n"

        #expect(model.photoContext == "Fried in butter, not oil")
    }

    /// The field is optional, and optional has to mean the scan is unchanged by
    /// an empty one — same request, same result, same drawn screen.
    @Test("an empty field leaves the scan exactly as it was")
    func emptyContextChangesNothing() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)

        await model.scanning(pixel())

        #expect(model.stage == .result)
        #expect(client.requests == 1)
        #expect(model.draft?.kilocalories == 460)
    }

    @Test("a typed line survives the scan it was written for")
    func contextSurvivesTheScan() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))

        model.context = "The sauce has cream"
        await model.scanning(pixel())

        #expect(model.photoContext == "The sauce has cream")
    }

    /// The note was written about one plate. Carrying it back to the viewfinder
    /// would attach it to the next photograph without the user seeing it
    /// happen, because the field is not what they are looking at when they
    /// press the shutter again.
    @Test("the line goes with the frame when the scan is thrown away")
    func discardClearsTheContext() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))

        model.context = "Half of what you see"
        await model.scanning(pixel())
        model.discard()

        #expect(model.context.isEmpty)
        #expect(model.photoContext == nil)
    }

    @Test("the line goes with the frame when the meal is logged")
    func commitClearsTheContext() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))

        model.context = "Oat milk, no sugar"
        await model.scanning(pixel())
        #expect(model.commit())

        #expect(model.context.isEmpty)
        #expect(model.photoContext == nil)
    }
}

// MARK: - Driving a scan

private extension CameraLogModel {

    /// Starts a scan and waits for it to settle.
    ///
    /// `analyse` deliberately returns before the request does — the interface
    /// has to draw the first analysis step immediately — so a test needs a way
    /// to wait. Polling the stage rather than exposing the task keeps the
    /// production type free of a hook that exists only for tests.
    func scanning(_ image: UIImage) async {
        analyse(image)
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

// MARK: - Stand-ins

/// A camera that hands back the smallest possible frame.
@MainActor
private final class StubCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage { pixel() }
}

/// A camera that fires and delivers nothing.
@MainActor
private final class FailingCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage {
        throw MealCameraError.captureFailed
    }
}

/// One opaque pixel.
///
/// Small enough that `MealPhotoCompressor` passes it through untouched, so the
/// tests are about the flow rather than about compression, which has its own
/// suite.
@MainActor
private func pixel() -> UIImage {
    let size = CGSize(width: 1, height: 1)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        context.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - Hatch

/// The direction the hatch's bands run.
///
/// It has its own suite because it is the one thing about `PhotoHatch` a reader
/// cannot check by eye in a diff: the angle, the band and the two tones are all
/// correct transcriptions of the export whichever way the bands are stacked,
/// and stacking them the wrong way turns the whole hatch a quarter turn while
/// leaving every number in the file right. That is a mistake a review cannot
/// see, so it is pinned here instead.
@Suite("Hatch")
@MainActor
struct PhotoHatchTests {

    /// Edge of every rendering below. Several band periods across, so a
    /// direction has something to be measured against.
    private static let edge: CGFloat = 80

    /// How far a sample is taken from its neighbour, on both axes at once.
    ///
    /// `band / √2` on each axis is one whole band width along the hatch's
    /// normal, which is the shift that lands squarely in the neighbouring
    /// stripe. Rounded to whole pixels so no sample needs interpolating.
    private static var step: Int {
        Int((FuelMetrics.Hatch.band / 2.0.squareRoot()).rounded())
    }

    @Test("the bands run bottom-left to top-right, as the export draws them")
    func bandsRunAlongTheDrawnDiagonal() throws {
        let hatch = try #require(
            render(PhotoHatch(base: .black, stripe: .white))
        )

        let downRight = meanDifference(in: hatch, dx: Self.step, dy: Self.step)
        let upRight = meanDifference(in: hatch, dx: Self.step, dy: -Self.step)

        // The buffer's row order relative to the view's is a property of the
        // drawing pipeline, not something to assume. A plain top-to-bottom
        // gradient rendered the same way answers it outright.
        //
        // Rendered here rather than inside the helper so that what `#require`
        // unwraps is the image. `#require` on a `Bool?` is ambiguous — it
        // cannot tell "unwrap this optional" from "assert this is true" — and
        // says so as a warning.
        let gradient = try #require(
            render(LinearGradient(colors: [.black, .white], startPoint: .top, endPoint: .bottom))
        )
        let topDown = rowsRunTopDown(in: gradient)

        // In view coordinates a "/" band runs (1, -1): x rises as y falls. A
        // flipped buffer swaps which measured diagonal that is.
        let alongTheBand = topDown ? upRight : downRight
        let acrossTheBands = topDown ? downRight : upRight

        #expect(alongTheBand < acrossTheBands)
        // Not merely smaller — a uniform fill would satisfy that. The bands
        // have to actually be there.
        #expect(acrossTheBands > 64)
        #expect(alongTheBand < 8)
    }

    // MARK: - Measuring

    /// Mean absolute difference between each pixel and the one `dx`, `dy` away.
    private func meanDifference(in image: GrayImage, dx: Int, dy: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 0..<image.height where y + dy >= 0 && y + dy < image.height {
            for x in 0..<image.width where x + dx >= 0 && x + dx < image.width {
                let here = Double(image[x, y])
                let there = Double(image[x + dx, y + dy])
                total += abs(here - there)
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    /// Whether row zero of a rendered buffer is the top of the view.
    ///
    /// Takes an already-rendered image so the caller owns the one thing that
    /// can fail, and this stays a plain measurement over pixels. Given a
    /// gradient that runs black at the top to white at the bottom, the darker
    /// end tells you which row came from the top of the view.
    private func rowsRunTopDown(in image: GrayImage) -> Bool {
        var firstRow = 0.0
        var lastRow = 0.0
        for x in 0..<image.width {
            firstRow += Double(image[x, 0])
            lastRow += Double(image[x, image.height - 1])
        }
        return firstRow < lastRow
    }

    /// Renders a view to an 8-bit grey buffer at scale 1.
    private func render(_ content: some View) -> GrayImage? {
        let renderer = ImageRenderer(
            content: content.frame(width: Self.edge, height: Self.edge)
        )
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let base = buffer.baseAddress,
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return GrayImage(pixels: pixels, width: width, height: height)
    }
}

/// An 8-bit grey rendering, addressed by column and row.
private struct GrayImage {

    let pixels: [UInt8]
    let width: Int
    let height: Int

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

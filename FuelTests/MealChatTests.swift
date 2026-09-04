import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - The conversation

/// The sheet on the meal-detail screen: what it sends, what it refuses to
/// send, and what it is allowed to claim afterwards.
///
/// **Nothing here reaches a network or a Keychain.** Both are injected — see
/// `AILogStandIns` — so every test runs on the same evidence whatever the
/// machine's connection is doing.
@Suite("Meal chat")
@MainActor
struct MealChatTests {

    // MARK: - Fixtures

    /// A subject with no store behind it, for the cases that are about the
    /// conversation rather than about a meal.
    ///
    /// It can be told to refuse a write, which is the one thing an in-memory
    /// store will not do on request and the one thing the sheet must not
    /// paper over.
    @MainActor
    private final class StandInSubject: MealChatSubject {

        var adjustableMeal: AdjustableMeal
        var accepts = true
        private(set) var applied: [AdjustedMeal] = []

        init(meal: AdjustableMeal) {
            adjustableMeal = meal
        }

        func apply(_ adjusted: AdjustedMeal) -> Bool {
            guard accepts else { return false }
            applied.append(adjusted)
            adjustableMeal = AdjustableMeal(
                title: adjustableMeal.title,
                kilocalories: adjusted.kilocalories,
                macros: adjusted.macros,
                items: adjusted.items
            )
            return true
        }
    }

    private static let rice = RecognisedItem(
        id: UUID(uuidString: "8C1F0B22-9B0A-4F17-9C0E-2B5B3D1C7A01")!,
        name: "Rice",
        kilocalories: 232,
        grams: 150,
        macros: MacroTotals(protein: 5, carbs: 50, fat: 1),
        note: .photo(confidence: .confident, approximateGrams: 150)
    )

    private static func meal() -> AdjustableMeal {
        AdjustableMeal(
            title: "Rice and something",
            kilocalories: 460,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            items: [rice]
        )
    }

    /// The same meal with the rice at 300 g, which is what a model that read
    /// "a second, smaller portion" would produce.
    private static func raised() -> AdjustedMeal {
        var heavier = rice
        heavier.setWeight(300)
        heavier.kilocalories = 423
        heavier.macros = MacroTotals(protein: 9, carbs: 91, fat: 2)
        return AdjustedMeal(
            kilocalories: 651,
            macros: MacroTotals(protein: 24, carbs: 101, fat: 13),
            items: [heavier]
        )
    }

    /// The turn a model produces for that, in the shape a scripted client hands
    /// one back: a change it asked for, and the meal that came of it.
    private static func raisedTheRice(saying reply: String? = "Raised the rice.") -> MealAdjustmentOutcome {
        MealAdjustmentOutcome(reply: reply, askedForAChange: true, meal: raised())
    }

    private func makeModel(
        subject: any MealChatSubject,
        client: any AIClient,
        keys: any MealKeyPresence = StoredKey()
    ) -> MealChatModel {
        MealChatModel(
            subject: subject,
            client: client,
            keys: keys,
            provider: .claude,
            // The four analysis steps are paced for the eye, not for the
            // request. Walking them instantly keeps the tests about outcomes.
            pace: {}
        )
    }

    // MARK: - Nothing is sent for nothing

    /// **The one that has to hold whatever else does.** With no key stored,
    /// no request is made at all — the same rule the two log modes and the
    /// re-analysis hold to, because every request spends the user's own
    /// credit.
    @Test("with no key nothing is sent and the user's line survives")
    func keylessSendsNothing() async {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(adjustments: [.success(Self.raisedTheRice(saying: "Done."))])
        let model = makeModel(subject: subject, client: client, keys: NoKeys())

        model.message = "a second, smaller portion"
        model.send()

        #expect(client.adjustRequests == 0)
        #expect(model.stage == .failed(.invalidKey))
        // The line the user wrote is still there: a request that was never
        // made must not cost them what they typed.
        #expect(model.messages.map(\.author) == [.you])
        #expect(subject.applied.isEmpty)
    }

    @Test(
        "an empty field sends nothing at all",
        arguments: ["", "   ", "\n\t "]
    )
    func emptyMessageSendsNothing(written: String) async {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(adjustments: [.success(Self.raisedTheRice(saying: "Done."))])
        let model = makeModel(subject: subject, client: client)

        model.message = written
        #expect(!model.canSend)
        model.send()

        #expect(client.adjustRequests == 0)
        #expect(model.messages.isEmpty)
        #expect(model.stage == .conversation)
    }

    @Test("the field stops accepting past the bound rather than trimming on send")
    func clampsTheMessage() {
        let subject = StandInSubject(meal: Self.meal())
        let model = makeModel(subject: subject, client: ScriptedClient())

        model.message = String(repeating: "a", count: MealChatContract.maximumMessageLength + 200)

        #expect(model.message.count == MealChatContract.maximumMessageLength)
    }

    // MARK: - A turn that changes the meal

    @Test("a successful turn writes the adjustment through and says what moved")
    func successfulTurn() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [.success(Self.raisedTheRice(saying: "Raised the rice to 300 g."))]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "I had a second portion, but smaller"
        model.send()
        await settle(model)

        #expect(client.adjustRequests == 1)
        #expect(client.lastMessage == "I had a second portion, but smaller")
        #expect(model.stage == .conversation)
        #expect(subject.applied.count == 1)
        #expect(subject.adjustableMeal.kilocalories == 651)

        #expect(model.messages.count == 2)
        #expect(model.messages[0].author == .you)
        #expect(model.messages[1].author == .fuel)
        #expect(model.messages[1].text == "Raised the rice to 300 g.")
        #expect(!model.messages[1].movedNothing)
        #expect(model.messages[1].changes.map(\.name) == ["Rice"])
        #expect(model.messages[1].changes.map(\.grams) == [300])
        // The field is emptied by sending, not by the answer arriving.
        #expect(model.message.isEmpty)
    }

    @Test("a reply with no sentence of its own still says the amounts moved")
    func silentButUseful() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [.success(Self.raisedTheRice(saying: nil))]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "twice as much rice"
        model.send()
        await settle(model)

        #expect(model.messages[1].text == MealChatCopy.adjusted)
        #expect(!model.messages[1].movedNothing)
    }

    // MARK: - A turn that changes nothing

    /// The ambiguity rule, from the interface's side: a message the model
    /// could not put a number on must not leave a sentence on screen over
    /// figures that did not move. A model that asked back committed to no
    /// change, so its own question is the whole of what is drawn.
    @Test("an answer that moves nothing writes nothing")
    func unmappableMessage() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [
                .success(MealAdjustmentOutcome(reply: "Roughly how much oil?", askedForAChange: false, meal: nil))
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "it was quite oily"
        model.send()
        await settle(model)

        #expect(subject.applied.isEmpty)
        #expect(subject.adjustableMeal == Self.meal())
        #expect(model.messages[1].text == "Roughly how much oil?")
        #expect(model.messages[1].changes.isEmpty)
        // Not a failure: the request worked and the model answered.
        #expect(model.stage == .conversation)
    }

    /// **The note's whole job, in the one turn that earns it.** The model asked
    /// for a change, said in its sentence that it had made one, and nothing
    /// moved — a row the table could not price, an item number the list does
    /// not have. The sentence is drawn as it was written and contradicted
    /// underneath, because it is the only thing on screen that would otherwise
    /// be believed.
    @Test("a change that moved nothing is still contradicted under its own sentence")
    func claimedChangeThatMovedNothing() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [
                .success(
                    MealAdjustmentOutcome(reply: "Added a spoon of harissa.", askedForAChange: true, meal: nil)
                )
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "there was a spoon of harissa on it"
        model.send()
        await settle(model)

        #expect(subject.applied.isEmpty)
        #expect(subject.adjustableMeal == Self.meal())
        #expect(model.messages[1].text == "Added a spoon of harissa.")
        #expect(model.messages[1].movedNothing)
        #expect(model.stage == .conversation)
    }

    @Test("an answer with neither a sentence nor a change still reads as something")
    func silentAndUseless() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [.success(MealAdjustmentOutcome(reply: nil, askedForAChange: true, meal: nil))]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "hmm"
        model.send()
        await settle(model)

        #expect(model.messages[1].text == MealChatCopy.unchanged)
        #expect(model.messages[1].movedNothing)
    }

    /// The same emptiness after a question is a different sentence, because
    /// "nothing to adjust from that" answers a question nobody asked. Nothing
    /// was being adjusted; the model simply came back with no words.
    @Test("a question that came back wordless does not read as a failed adjustment")
    func silentAnswerToAQuestion() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [.success(MealAdjustmentOutcome(reply: nil, askedForAChange: false, meal: nil))]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "how healthy is this meal?"
        model.send()
        await settle(model)

        #expect(model.messages[1].text == MealChatCopy.noAnswer)
        #expect(!model.messages[1].movedNothing)
    }

    /// A store that refuses is not a change that happened. Nothing may go into
    /// the transcript claiming otherwise.
    @Test("a refused write lands on the retry state and claims nothing")
    func refusedWrite() async throws {
        let subject = StandInSubject(meal: Self.meal())
        subject.accepts = false
        let client = ScriptedClient(
            adjustments: [.success(Self.raisedTheRice())]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        await settle(model)

        #expect(model.stage == .failed(.retry(.device)))
        #expect(model.messages.map(\.author) == [.you])
        #expect(subject.applied.isEmpty)
    }

    // MARK: - A question is an answer

    /// **The owner's report.** "How healthy is this meal" is a question about
    /// the food, the model answers it, and the screen used to print a line
    /// underneath telling the user that naming an amount is what lets a meal be
    /// adjusted — Fuel correcting them for asking something it had just
    /// answered. The answer now stands on its own.
    @Test(
        "a question is answered with nothing underneath it about amounts",
        arguments: [
            "how healthy is this meal?",
            "how long will it keep me full?",
            "what could I add to make it more satisfying?",
        ]
    )
    func aQuestionIsNotCorrected(asked: String) async throws {
        let subject = StandInSubject(meal: Self.meal())
        let answer = "Plenty of starch, and light on protein for its size."
        let client = ScriptedClient(
            adjustments: [.success(MealAdjustmentOutcome(reply: answer, askedForAChange: false, meal: nil))]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = asked
        model.send()
        await settle(model)

        #expect(model.messages[1].text == answer)
        #expect(!model.messages[1].movedNothing)
        #expect(model.messages[1].changes.isEmpty)
        // The meal is exactly as it was, and nothing was written to it — the
        // last of those matters most for the third question, whose answer names
        // food the user has not eaten.
        #expect(subject.applied.isEmpty)
        #expect(subject.adjustableMeal == Self.meal())
        #expect(model.stage == .conversation)
    }

    // MARK: - The conversation

    @Test("the second message carries the first exchange and not its own line")
    func historyTravels() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [
                .success(MealAdjustmentOutcome(reply: "Roughly how much oil?", askedForAChange: false, meal: nil)),
                .success(Self.raisedTheRice(saying: "Added a tablespoon.")),
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "it was quite oily"
        model.send()
        await settle(model)

        model.message = "a tablespoon"
        model.send()
        await settle(model)

        #expect(
            client.lastHistory == [
                MealChatTurn(speaker: .user, text: "it was quite oily"),
                MealChatTurn(speaker: .model, text: "Roughly how much oil?"),
            ]
        )
        #expect(client.lastMessage == "a tablespoon")
    }

    /// **A line the model never answered is not an exchange.** It stays in the
    /// transcript, because the user typed it and can see that they did, and it
    /// stays out of the request: two user turns in a row is a request the
    /// providers are not trained on and can refuse outright.
    @Test("a message that was never answered does not travel as history")
    func unansweredTurnsDoNotTravel() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [
                .failure(.network),
                .success(
                    MealAdjustmentOutcome(reply: "Polenta is boiled maize meal.", askedForAChange: false, meal: nil)
                ),
                .success(Self.raisedTheRice()),
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "it was quite oily"
        model.send()
        await settle(model)

        // The failure is dismissed rather than retried, and something else is
        // asked — which is the one move that leaves an orphan behind.
        model.dismissFailure()
        model.message = "what is in polenta?"
        model.send()
        await settle(model)

        #expect(client.lastHistory == [])

        model.message = "more rice"
        model.send()
        await settle(model)

        // Only the exchange that happened, and the user's unanswered line is
        // still drawn above it.
        #expect(
            client.lastHistory == [
                MealChatTurn(speaker: .user, text: "what is in polenta?"),
                MealChatTurn(speaker: .model, text: "Polenta is boiled maize meal."),
            ]
        )
        #expect(model.messages.map(\.author) == [.you, .you, .fuel, .you, .fuel])
    }

    /// The second message is about the meal the first one produced, so a
    /// snapshot taken when the sheet opened would raise the rice twice from
    /// 150 g.
    @Test("each message is about the meal as it now stands")
    func rereadsTheMeal() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [
                .success(Self.raisedTheRice(saying: "Raised it.")),
                .success(MealAdjustmentOutcome(reply: "Again.", askedForAChange: true, meal: nil)),
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        await settle(model)

        model.message = "even more"
        model.send()
        await settle(model)

        #expect(client.lastAdjustedMeal?.items.first?.grams == 300)
        #expect(client.lastAdjustedMeal?.kilocalories == 651)
    }

    // MARK: - Failing

    @Test("a failure keeps the user's line, and the retry does not repeat it")
    func retryDoesNotDuplicateTheTurn() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(
            adjustments: [
                .failure(.network),
                .success(Self.raisedTheRice()),
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        await settle(model)

        #expect(model.stage == .failed(.retry(.transport)))
        #expect(model.messages.map(\.author) == [.you])

        model.retry()
        await settle(model)

        #expect(client.adjustRequests == 2)
        #expect(model.messages.map(\.author) == [.you, .fuel])
    }

    @Test("a retry with the key gone makes no second request")
    func retryWithoutAKey() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let keys = MutableKeys(hasKey: true)
        let client = ScriptedClient(adjustments: [.failure(.network)])
        let model = makeModel(subject: subject, client: client, keys: keys)

        model.message = "more rice"
        model.send()
        await settle(model)

        keys.hasKey = false
        model.retry()

        #expect(client.adjustRequests == 1)
        #expect(model.stage == .failed(.invalidKey))
    }

    @Test("a cancelled message says nothing at all")
    func cancelledMessage() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = ScriptedClient(adjustments: [.failure(.cancelled)])
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        await settle(model)

        #expect(model.stage == .conversation)
        #expect(model.messages.map(\.author) == [.you])
    }

    /// Cancelling a `Task` does not stop the answer it is already waiting on.
    /// A message the user called off must not come back and write over a meal
    /// nobody was still asking about.
    @Test("an answer to a cancelled message never lands")
    func cancelRetiresTheRun() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = GatedClient(
            adjustments: [.success(Self.raisedTheRice())]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        while client.requests == 0 {
            await Task.yield()
        }

        model.cancel()
        #expect(model.stage == .conversation)

        client.release(0)
        await settle(model)

        #expect(subject.applied.isEmpty)
        #expect(model.messages.map(\.author) == [.you])
        #expect(model.stage == .conversation)
    }

    // MARK: - Which wait a message gets

    /// **The pin.** A question is answered in the conversation, with the
    /// sentence arriving where the reply will sit — and the four analysis
    /// states, which describe work on a meal, never appear over a message that
    /// moves no meal.
    ///
    /// The client is held open on purpose: the only moment this is visible is
    /// while the reply is still being written, which is exactly the moment a
    /// finished-answer test cannot reach.
    @Test("a question is answered without the analysis states")
    func aQuestionShowsNoSteps() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = GatedClient(
            adjustments: [
                .success(
                    MealAdjustmentOutcome(reply: "Polenta is boiled maize meal.", askedForAChange: false, meal: nil)
                )
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "what is in polenta?"
        model.send()
        await waitForAWord(model)

        // Mid-turn: the sentence is on screen and nothing is covering it.
        #expect(model.arrivingReply == "Polenta is boiled maize meal.")
        #expect(model.stage == .conversation)

        client.release(0)
        await settle(model)

        #expect(model.stage == .conversation)
        #expect(model.messages.map(\.author) == [.you, .fuel])
        #expect(model.messages[1].text == "Polenta is boiled maize meal.")
        // An answer, not a failed adjustment: nothing under it says the meal
        // is unchanged, because nothing was being changed.
        #expect(!model.messages[1].movedNothing)
        #expect(model.arrivingReply == nil)
        #expect(subject.applied.isEmpty)
    }

    /// The other half of the same pin: a turn that is moving something still
    /// gets the states, and gets them while the request is still in flight
    /// rather than after it.
    @Test("an adjustment still runs the analysis states")
    func anAdjustmentShowsTheSteps() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = GatedClient(
            adjustments: [.success(Self.raisedTheRice())]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "a second, smaller portion"
        model.send()

        #expect(await reachedTheSteps(model))

        client.release(0)
        await settle(model)

        #expect(model.stage == .conversation)
        #expect(subject.applied.count == 1)
        #expect(model.messages.map(\.author) == [.you, .fuel])
    }

    /// One message at a time. The composer draws a stop rather than a send
    /// while a reply is arriving, and the field's own return key goes through
    /// the same guard.
    @Test("a second message while one is in flight is not sent")
    func oneMessageAtATime() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = GatedClient(
            adjustments: [
                .success(
                    MealAdjustmentOutcome(reply: "Polenta is boiled maize meal.", askedForAChange: false, meal: nil)
                )
            ]
        )
        let model = makeModel(subject: subject, client: client)

        model.message = "what is in polenta?"
        model.send()
        await waitForAWord(model)

        model.message = "and how much protein?"
        model.send()

        #expect(client.requests == 1)
        #expect(model.messages.map(\.author) == [.you])
        // What was typed is still there to send once the first turn is done.
        #expect(model.message == "and how much protein?")

        client.release(0)
        await settle(model)
    }

    // MARK: - A stream that stops

    /// **The other pin.** A reply that began and then lost its connection must
    /// not leave four words in the transcript with nothing saying what
    /// happened. The half sentence goes and the failure takes its place —
    /// dropped rather than truncated, the same rule the bound on a finished
    /// sentence follows.
    @Test("a reply that dies part-way shows the failure and keeps no half sentence")
    func interruptedReply() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = InterruptedClient(sentence: "Raised the rice to")
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        await settle(model)

        #expect(model.stage == .failed(.retry(.transport)))
        #expect(model.arrivingReply == nil)
        #expect(model.messages.map(\.author) == [.you])
        #expect(!model.messages.contains { $0.text == "Raised the rice to" })
        #expect(subject.applied.isEmpty)
    }

    /// And the retry after one is the ordinary retry: the user's line is still
    /// there and is not written twice.
    @Test("the message an interrupted reply was answering can be sent again")
    func retryAfterAnInterruption() async throws {
        let subject = StandInSubject(meal: Self.meal())
        let client = InterruptedClient(sentence: "Raised the rice to")
        let model = makeModel(subject: subject, client: client)

        model.message = "more rice"
        model.send()
        await settle(model)

        model.retry()
        await settle(model)

        #expect(client.adjustRequests == 2)
        #expect(model.messages.map(\.author) == [.you])
    }

    // MARK: - On the meal-detail screen

    @Test("a turn moves the stored meal and the screen with it")
    func writesThroughToTheStore() async throws {
        let store = try FuelStore(inMemory: true, calendar: testCalendar)
        let entry = try store.log(
            title: "Rice and something",
            kilocalories: 460,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            loggedAt: at(19, 20),
            source: .photo,
            items: [Self.rice]
        )

        let client = ScriptedClient(
            adjustments: [.success(Self.raisedTheRice())]
        )
        let detail = MealDetailModel(
            entryID: entry.entryID,
            store: store,
            client: client,
            keys: StoredKey(),
            provider: .claude,
            pace: {}
        )
        guard let detail else { throw ChatFixtureFailure.noStoredMeal }

        detail.chat.message = "a second, smaller portion"
        detail.chat.send()
        await settle(detail.chat)

        // The draft the screen draws, and the row the store holds.
        #expect(detail.draft.kilocalories == 651)
        #expect(detail.draft.items.first?.grams == 300)
        #expect(entry.kilocalories == 651)
        #expect(entry.items.first?.grams == 300)
        // A conversation about amounts does not rename the meal.
        #expect(entry.title == "Rice and something")
        #expect(detail.draft.title == "Rice and something")
    }

    /// Provenance again, this time all the way to the row the store holds: a
    /// CIQUAL figure has to still be one after a conversation moved the
    /// weight.
    @Test("a grounded row is still grounded in the store afterwards")
    func provenanceReachesTheStore() async throws {
        let store = try FuelStore(inMemory: true, calendar: testCalendar)
        let entry = try store.log(
            title: "Rice and something",
            kilocalories: 460,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            loggedAt: at(19, 20),
            source: .photo,
            items: [Self.rice]
        )

        let client = ScriptedClient(
            adjustments: [.success(Self.raisedTheRice())]
        )
        let detail = MealDetailModel(
            entryID: entry.entryID,
            store: store,
            client: client,
            keys: StoredKey(),
            provider: .claude,
            pace: {}
        )
        guard let detail else { throw ChatFixtureFailure.noStoredMeal }

        detail.chat.message = "more rice"
        detail.chat.send()
        await settle(detail.chat)

        let stored = try #require(try store.entry(withID: entry.entryID))
        #expect(stored.items.first?.macros != nil)
        #expect(stored.items.first?.macros == MacroTotals(protein: 9, carbs: 91, fat: 2))
    }

    @Test("deleting the meal stops a message that is still in flight")
    func deletingStopsTheConversation() async throws {
        let store = try FuelStore(inMemory: true, calendar: testCalendar)
        let entry = try store.log(
            title: "Rice and something",
            kilocalories: 460,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            loggedAt: at(19, 20),
            source: .photo,
            items: [Self.rice]
        )

        let client = GatedClient(
            adjustments: [.success(Self.raisedTheRice())]
        )
        let detail = MealDetailModel(
            entryID: entry.entryID,
            store: store,
            client: client,
            keys: StoredKey(),
            provider: .claude,
            pace: {}
        )
        guard let detail else { throw ChatFixtureFailure.noStoredMeal }

        detail.chat.message = "more rice"
        detail.chat.send()
        while client.requests == 0 {
            await Task.yield()
        }

        #expect(detail.delete())

        client.release(0)
        await settle(detail.chat)

        #expect(detail.chat.messages.map(\.author) == [.you])
        #expect(try store.entry(withID: entry.entryID) == nil)
    }

    // MARK: - Helpers

    /// Lets whatever the model started run to completion.
    ///
    /// The client answers from memory and the pacing is instant, so the work
    /// is a handful of continuations rather than a wait. Yielding until the
    /// model is idle is what keeps this from being a sleep with a number
    /// nobody can justify.
    ///
    /// **Idle is both things now, not just the stage.** A turn no longer starts
    /// on the analysis states — a question never reaches them at all — so a
    /// settle that watched only the stage would return before the first message
    /// had been answered. `isAnswering` is the reply still arriving, and it is
    /// cleared on every way a turn can end.
    private func settle(_ model: MealChatModel) async {
        for _ in 0..<200 {
            await Task.yield()
            if model.isAnswering {
                continue
            }
            if case .analysing = model.stage {
                continue
            }
            // One more turn of the loop, so a continuation resumed by this
            // very yield has landed before the assertions run.
            await Task.yield()
            return
        }
    }

    /// Waits until the reply on screen has a word in it, which is where a
    /// held-open turn parks.
    ///
    /// Bounded rather than a `while`: a test that hangs when the behaviour
    /// breaks tells nobody anything, and the assertion after this one is what
    /// says whether the wait was long enough.
    private func waitForAWord(_ model: MealChatModel) async {
        for _ in 0..<200 {
            if model.arrivingReply?.isEmpty == false {
                return
            }
            await Task.yield()
        }
    }

    /// Whether the analysis states were reached at all.
    ///
    /// Any of the four counts: the pacing here is instant, so the walk runs to
    /// the last step as soon as it starts, and which one it has got to is
    /// `AnalysisStep`'s subject rather than this one's.
    private func reachedTheSteps(_ model: MealChatModel) async -> Bool {
        for _ in 0..<200 {
            if case .analysing = model.stage {
                return true
            }
            await Task.yield()
        }
        return false
    }

    private enum ChatFixtureFailure: Error {
        case noStoredMeal
    }
}

// MARK: - The composer on screen

/// The one thing about the sheet that cannot be answered from the model: what
/// the keyboard's own `Send` key does.
///
/// **Hosted rather than reasoned about**, and hosted in the presentation the
/// meal-detail screen actually uses — the platform's `.sheet` at `.large` —
/// because the model's `send()` is provably right on its own and the owner was
/// still left looking at their sentence. The field is a real
/// `SwiftUI.VerticalTextView` on a real window on the test host's scene, and
/// the return key is driven the way the on-screen keyboard drives it:
/// `insertText("\n")` on the first responder, which is what `UIKeyboardImpl`
/// sends a `UITextView` for the return key. Nothing here synthesises an event
/// UIKit would not.
///
/// Nothing reaches a network or a Keychain: both are the same stand-ins the
/// suite above uses.
@Suite("Meal chat · the composer on screen", .serialized)
@MainActor
struct MealChatComposerTests {

    // MARK: - Hosting

    /// `MealChatSheet` exactly as `MealDetailView` presents it, so the field
    /// under test is the one the user types into rather than a bare copy of it.
    private struct Presentation: View {

        let model: MealChatModel

        @State private var isTalking = true

        var body: some View {
            Color.clear
                .sheet(isPresented: $isTalking) {
                    MealChatSheet(
                        model: model,
                        mealTitle: "Rice and something",
                        onClose: { isTalking = false }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
        }
    }

    /// Stands the view on a window of the test host's own scene and lets the
    /// sheet come up.
    ///
    /// Long enough for the presentation to finish: the field lives in a
    /// presented controller, and there is nothing to find until it is on screen.
    private func host(_ view: some View) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(
            rootView: view.environment(\.fuelPalette, FuelPalette(theme: .dark, accent: .mono))
        )
        window.makeKeyAndVisible()
        spin(window, for: 1)
        return window
    }

    /// A turn of the main actor and a turn of the run loop, twice.
    ///
    /// **Both, and the main actor first.** The composer answers the return key
    /// one main-actor hop later — `MealChatSheet.write` says at length why it
    /// has to — and a test that only spun the run loop would hold the main
    /// actor for the whole of it and never let that hop happen. Measured: the
    /// field kept its blank line for six hundred milliseconds of run loop and
    /// emptied on the first `yield`. The run loop afterwards is what carries the
    /// emptied message back down into the text view.
    private func settle(_ window: UIWindow) async {
        for _ in 0..<2 {
            await Task.yield()
            spin(window, for: 0.15)
        }
    }

    private func spin(_ window: UIWindow, for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        window.layoutIfNeeded()
    }

    /// The composer's own text view, out of the presented sheet.
    ///
    /// It is the only text input the sheet has, so the first one found is it.
    private func composer(in window: UIWindow) -> UITextView? {
        guard let presented = window.rootViewController?.presentedViewController?.view else { return nil }
        return textView(in: presented)
    }

    private func textView(in view: UIView) -> UITextView? {
        for subview in view.subviews {
            if let found = subview as? UITextView { return found }
            if let nested = textView(in: subview) { return nested }
        }
        return nil
    }

    // MARK: - Fixtures

    @MainActor
    private final class StandInSubject: MealChatSubject {

        var adjustableMeal = AdjustableMeal(
            title: "Rice and something",
            kilocalories: 460,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: 232,
                    grams: 150,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            ]
        )

        func apply(_ adjusted: AdjustedMeal) -> Bool { true }
    }

    /// A model and the subject it only holds weakly.
    ///
    /// Handed back together because a test that let the subject go would watch
    /// `send()` refuse every message — the model treats a meal that is gone as
    /// nothing to talk about, which is the same guard `deletingStopsTheConversation`
    /// above relies on.
    private struct Composer {

        let subject: StandInSubject
        let model: MealChatModel
    }

    private func makeComposer() -> Composer {
        let subject = StandInSubject()
        return Composer(
            subject: subject,
            model: MealChatModel(
                subject: subject,
                client: ScriptedClient(
                    adjustments: [.success(MealAdjustmentOutcome(reply: "Done.", askedForAChange: true, meal: nil))]
                ),
                keys: StoredKey(),
                provider: .claude,
                pace: {}
            )
        )
    }

    // MARK: - The keyboard's own send

    /// **The bug the owner saw.** `onSubmit` is never called for a
    /// `TextField(axis: .vertical)`: the on-screen return key reaches the
    /// backing `UITextView` as `insertText("\n")` and nothing above it
    /// intercepts, so the sentence stayed in the field, grew a blank line, and
    /// nothing was sent.
    @Test("the keyboard's send key sends what was typed and empties the field")
    func returnKeySends() async throws {
        let fixture = makeComposer()
        let model = fixture.model
        let window = try host(Presentation(model: model))
        let field = try #require(composer(in: window))

        #expect(field.becomeFirstResponder())
        field.insertText("a second, smaller portion")
        await settle(window)

        #expect(model.message == "a second, smaller portion")
        #expect(field.text == "a second, smaller portion")

        field.insertText("\n")
        await settle(window)

        #expect(model.messages.map(\.text) == ["a second, smaller portion"])
        #expect(model.message.isEmpty, "the model still holds \(model.message.debugDescription)")
        #expect(field.text.isEmpty, "the field still holds \(field.text.debugDescription)")
    }

    /// The rule that makes the one above exact: a line break cannot stay in a
    /// field whose return key is drawn as `Send`.
    @Test("a return on an empty field sends nothing and leaves no blank line")
    func returnOnAnEmptyFieldSendsNothing() async throws {
        let fixture = makeComposer()
        let model = fixture.model
        let window = try host(Presentation(model: model))
        let field = try #require(composer(in: window))

        #expect(field.becomeFirstResponder())
        field.insertText("\n")
        await settle(window)

        #expect(model.messages.isEmpty)
        #expect(model.message.isEmpty, "the model still holds \(model.message.debugDescription)")
        #expect(field.text.isEmpty, "the field still holds \(field.text.debugDescription)")
    }

    /// **A paste is text, not an instruction to spend a request on it.** It
    /// arrives whole, so both the length and the line-break count move by more
    /// than one and nothing is read as the return key.
    @Test("a multi-line paste keeps the field and sends nothing")
    func pasteDoesNotSend() async throws {
        let fixture = makeComposer()
        let model = fixture.model
        let window = try host(Presentation(model: model))
        let field = try #require(composer(in: window))

        #expect(field.becomeFirstResponder())
        field.insertText("rice\nand a fried egg")
        await settle(window)

        #expect(model.messages.isEmpty)
        #expect(model.message == "rice\nand a fried egg")
        #expect(field.text == "rice\nand a fried egg")
    }

    /// The send control's own path, measured on the same hosted field, so the
    /// two ways in are known to end in the same place.
    @Test("the send control empties the field too")
    func sendControlEmptiesTheField() async throws {
        let fixture = makeComposer()
        let model = fixture.model
        let window = try host(Presentation(model: model))
        let field = try #require(composer(in: window))

        #expect(field.becomeFirstResponder())
        field.insertText("a second, smaller portion")
        await settle(window)

        model.send()
        await settle(window)

        #expect(model.messages.map(\.text) == ["a second, smaller portion"])
        #expect(model.message.isEmpty, "the model still holds \(model.message.debugDescription)")
        #expect(field.text.isEmpty, "the field still holds \(field.text.debugDescription)")
    }
}

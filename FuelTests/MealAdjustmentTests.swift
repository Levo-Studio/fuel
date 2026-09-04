import Foundation
import Testing

@testable import Fuel

// MARK: - Reading an adjustment

/// What a reply is allowed to say, and what it cannot say however hard it
/// tries.
@Suite("Meal chat contract")
struct MealChatContractTests {

    // MARK: - The shape

    @Test("a well-formed reply reads as the changes it asks for")
    func readsChanges() throws {
        let reply = """
            {"reply":"Raised the rice to 300 g.","changes":[{"item":1,"grams":300}],\
            "additions":[{"name":"Olive oil","grams":10}]}
            """

        let intent = try MealChatContract.intent(from: reply)

        #expect(intent.reply == "Raised the rice to 300 g.")
        #expect(intent.changes == [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)])
        #expect(intent.additions == [MealAdjustmentIntent.Addition(name: "Olive oil", grams: 10)])
    }

    /// The whole architecture in one test. A model that ignores every line of
    /// the prompt and answers with a full nutrition table has still only said
    /// one thing this app reads — how much of the food there was.
    @Test("a reply carrying figures has no field to put them in")
    func figuresAreNotRead() throws {
        let reply = """
            {"reply":"Done.","kilocalories":9999,"protein_g":800,"carbs_g":800,\
            "fat_g":800,"macros":{"protein":1},"changes":[{"item":1,"grams":300,\
            "kilocalories":9999,"protein_g":800}]}
            """

        let intent = try MealChatContract.intent(from: reply)

        // Nothing on the intent can hold a figure, so there is nowhere for any
        // of that to have landed. The change is the weight and only the weight.
        #expect(intent.changes == [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)])
        #expect(intent.additions.isEmpty)
    }

    @Test("prose and a code fence around the object are tolerated")
    func fencedReply() throws {
        let reply = """
            Here is the adjustment:
            ```json
            {"reply":"Raised it.","changes":[{"item":2,"grams":120}]}
            ```
            """

        let intent = try MealChatContract.intent(from: reply)
        #expect(intent.changes == [MealAdjustmentIntent.Change(itemNumber: 2, grams: 120)])
    }

    /// A model that mapped nothing has answered the question, and the answer
    /// is "I could not". It is not a parse failure, and treating it as one
    /// would send the user to a retry screen for a request that worked.
    @Test("an answer that changes nothing is still an answer")
    func emptyAnswerParses() throws {
        let reply = """
            {"reply":"How much oil roughly?","changes":[],"additions":[]}
            """

        let intent = try MealChatContract.intent(from: reply)

        #expect(intent.reply == "How much oil roughly?")
        #expect(intent.changes.isEmpty)
        #expect(intent.additions.isEmpty)
    }

    @Test("both lists missing entirely read as empty rather than throwing")
    func missingLists() throws {
        let intent = try MealChatContract.intent(from: #"{"reply":"Not sure."}"#)
        #expect(intent.changes.isEmpty)
        #expect(intent.additions.isEmpty)
    }

    @Test("a reply field that is not a string costs the sentence and not the changes")
    func replyOfTheWrongType() throws {
        let intent = try MealChatContract.intent(from: #"{"reply":42,"changes":[{"item":1,"grams":90}]}"#)
        #expect(intent.reply == nil)
        #expect(intent.changes.count == 1)
    }

    @Test("numbers written as strings or with a fraction are the same numbers")
    func lenientNumbers() throws {
        let intent = try MealChatContract.intent(
            from: #"{"changes":[{"item":"1","grams":299.6}]}"#
        )
        #expect(intent.changes == [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)])
    }

    @Test(
        "a weight of zero or below is not an amount and the row is dropped",
        arguments: [0, -50]
    )
    func refusesEmptyWeights(grams: Int) throws {
        let intent = try MealChatContract.intent(
            from: #"{"changes":[{"item":1,"grams":\#(grams)}],"additions":[{"name":"Oil","grams":\#(grams)}]}"#
        )
        #expect(intent.changes.isEmpty)
        #expect(intent.additions.isEmpty)
    }

    @Test("an addition with no name is dropped")
    func additionWithoutName() throws {
        let intent = try MealChatContract.intent(from: #"{"additions":[{"grams":10}]}"#)
        #expect(intent.additions.isEmpty)
    }

    // MARK: - An answer written as prose

    /// **The failure the owner saw nine times in ten.** A conversational answer
    /// is an answer, and reading it as one is the difference between the sheet
    /// saying what polenta is and the sheet saying "unreadable response" over a
    /// sentence that was sitting right there.
    @Test("a reply with no object at all is the sentence it plainly is")
    func proseIsAnAnswer() throws {
        let intent = try MealChatContract.intent(from: "Polenta is boiled maize meal.")

        #expect(intent.reply == "Polenta is boiled maize meal.")
        #expect(intent.changes.isEmpty)
        #expect(intent.additions.isEmpty)
    }

    /// Prose is drawn and never read. A sentence with figures in it moves
    /// nothing, because there is no branch that takes a number out of one and
    /// no field on the intent that could hold it.
    @Test("a number written into prose is text and reaches no amount")
    func proseWithFiguresMovesNothing() throws {
        let reply = "I raised the rice to about 300 g, which is roughly 470 kcal and 10 g of protein."

        let intent = try MealChatContract.intent(from: reply)

        #expect(intent.reply == reply)
        #expect(intent.changes.isEmpty)
        #expect(intent.additions.isEmpty)
    }

    @Test("prose is collapsed to one run of words like any other sentence")
    func proseIsCollapsed() throws {
        let intent = try MealChatContract.intent(from: "  Polenta is\n\n  boiled maize meal.  ")
        #expect(intent.reply == "Polenta is boiled maize meal.")
    }

    /// The bound, and the reason it is not the sentence's: prose is the whole
    /// answer rather than a caption beside one.
    @Test("prose past its own bound is dropped rather than shown short")
    func dropsOverlongProse() throws {
        let long = String(repeating: "a", count: MealChatContract.maximumProseLength + 1)
        #expect(throws: AIError.malformedResponse) {
            _ = try MealChatContract.intent(from: long)
        }
        // A paragraph that would have been dropped as a caption is still an
        // answer here.
        let paragraph = String(repeating: "a", count: MealChatContract.maximumReplyLength + 1)
        #expect(try MealChatContract.intent(from: paragraph).reply == paragraph)
    }

    /// A reply with nothing in it is the one thing this parse still refuses:
    /// there is no object, no sentence, and nothing to show a user.
    @Test(
        "a reply with nothing in it at all is still malformed",
        arguments: ["", "   ", "\n\t "]
    )
    func emptyReplyIsMalformed(raw: String) {
        #expect(throws: AIError.malformedResponse) {
            _ = try MealChatContract.intent(from: raw)
        }
    }

    /// **A half-written object is not prose**, and must not be shown to anyone
    /// as a sentence. It is the case `AIError.truncatedReply` is named for, and
    /// it stays a failure here.
    @Test(
        "a reply cut off inside its own object is not read as a sentence",
        arguments: [
            #"{"changes":[{"item":1,"gra"#,
            "Here is the adjustment: {\"changes\":[",
            "```json\n{\"changes\":[",
            "```",
        ]
    )
    func fragmentsAreNotProse(raw: String) {
        #expect(throws: AIError.malformedResponse) {
            _ = try MealChatContract.intent(from: raw)
        }
    }

    // MARK: - The sentence

    @Test("the model's sentence is collapsed to one run of words")
    func collapsesWhitespace() {
        #expect(MealChatContract.boundedReply("  Raised   the\n\nrice.  ") == "Raised the rice.")
    }

    @Test("a sentence past the bound is dropped rather than cut short")
    func dropsAnOverlongReply() {
        let long = String(repeating: "a", count: MealChatContract.maximumReplyLength + 1)
        #expect(MealChatContract.boundedReply(long) == nil)
    }

    @Test("nothing but whitespace is nothing to draw")
    func dropsBlankReply() {
        #expect(MealChatContract.boundedReply("   \n ") == nil)
        #expect(MealChatContract.boundedReply(nil) == nil)
    }

    // MARK: - What goes over the wire

    @Test("the turn carries the numbered items with their weights, and the message last")
    func turnShape() {
        let meal = AdjustableMeal(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
            items: [
                RecognisedItem(name: "Salmon fillet", kilocalories: 240, grams: 150, note: .text(amount: .estimated)),
                RecognisedItem(name: "Polenta", kilocalories: 150, note: .text(amount: .estimated)),
            ]
        )

        let turn = MealChatContract.turn(for: meal, message: "I had a second portion, but smaller")

        #expect(turn.contains("1. Salmon fillet — 150 g"))
        #expect(turn.contains("2. Polenta — amount not recorded"))
        #expect(turn.hasSuffix("Message: I had a second portion, but smaller"))
        // The figures stay behind: handing a model its own last answer invites
        // it to agree with itself rather than to read what was said.
        #expect(!turn.contains("240"))
        #expect(!turn.contains("kcal"))
        #expect(!turn.contains("protein"))
    }

    /// **The rule that does not bend, checked at the other end of it.** The
    /// decoder has no property a figure could land in and the intent has no
    /// field one could travel in; this says the shape the model is shown does
    /// not offer it a key to write one into either. It survives the prompt
    /// being reworded, which it has been, and would not survive a nutritional
    /// field being added back to the shape.
    @Test("the shape the prompt asks for has no field a figure could go in")
    func promptAsksForNoFigures() {
        let prompt = MealChatContract.systemPrompt

        #expect(prompt.contains("\"changes\""))
        #expect(prompt.contains("\"additions\""))
        #expect(prompt.contains("\"reply\""))

        for key in ["\"kilocalories\"", "\"calories\"", "\"protein", "\"carb", "\"fat", "\"energy\""] {
            #expect(!prompt.contains(key))
        }
    }

    /// **A canary over the one rule here that nothing structural enforces.**
    ///
    /// Every other promise this contract makes is kept by the device whatever
    /// the model writes: a figure has no key to arrive in and no property to
    /// land in, a weight is priced against CIQUAL rather than believed, an
    /// unreadable row is dropped. This one cannot be. "The carrots were done in
    /// olive oil" and "what could I add to make this more filling" produce the
    /// same `additions` entry — a food name and a weight — and there is nothing
    /// in the object, the payload or the wire that says which of the two it
    /// came from, so a suggestion written into that key would be logged as food
    /// the user never ate.
    ///
    /// The sentence in the prompt is therefore the whole of the protection, and
    /// this exists so that a reword which quietly drops it fails here instead
    /// of in somebody's day.
    @Test("the prompt says a food it suggested is not a food that was eaten")
    func promptRefusesSuggestions() {
        #expect(MealChatContract.systemPrompt.contains("Only food they ate goes in \"additions\""))
    }

    @Test("a meal with no breakdown says so rather than sending an empty list")
    func turnWithoutItems() {
        let meal = AdjustableMeal(title: "Leftovers", kilocalories: 300, macros: .zero, items: [])
        let turn = MealChatContract.turn(for: meal, message: "twice as much")
        #expect(turn.contains("no itemised breakdown"))
    }
}

// MARK: - Applying an adjustment

/// These run against the bundled artefact, the same one `FoodTableTests` and
/// `FoodTableGroundingTests` do, for the same reason: what matters is whether
/// a weight actually re-prices against the table that ships.
@Suite("Meal adjustment")
struct MealAdjusterTests {

    private let table: FoodTable

    init() throws {
        table = try FoodTable.bundled()
    }

    // MARK: - Fixtures

    /// A meal in the state a photo scan leaves it in: one grounded row and one
    /// the table never matched.
    private func groundedMeal() throws -> AdjustableMeal {
        let row = try #require(FoodTableGrounding.bestMatch(for: "Rice", preferring: .prepared, in: table))
        let portion = PortionCalculator.portion(of: row.per100g, grams: 150)

        return AdjustableMeal(
            title: "Rice and something",
            kilocalories: portion.kilocalories + 200,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: portion.kilocalories,
                    grams: 150,
                    macros: portion.incompleteMacros ? nil : portion.macros,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Zzznotafood",
                    kilocalories: 200,
                    grams: 100,
                    note: .photo(confidence: .unsure, approximateGrams: 100)
                ),
            ]
        )
    }

    private func price(_ name: String, at grams: Double, preferring preparation: FoodPreparation = .prepared) throws
        -> PortionNutrition
    {
        let row = try #require(FoodTableGrounding.bestMatch(for: name, preferring: preparation, in: table))
        return PortionCalculator.portion(of: row.per100g, grams: grams)
    }

    // MARK: - The figures come from the table

    /// The owner's first example: a second helping is one larger amount, and
    /// the price of it is the table's, not the model's.
    @Test("a changed weight is re-priced from the table row, not from the reply")
    func repricesFromTheTable() throws {
        let meal = try groundedMeal()
        let intent = MealAdjustmentIntent(
            reply: "Raised the rice.",
            changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 225)]
        )

        let adjusted = try #require(MealAdjuster.apply(intent, to: meal, table: table))

        let expected = try price("Rice", at: 225)
        #expect(adjusted.items[0].kilocalories == expected.kilocalories)
        #expect(adjusted.items[0].grams == 225)
        // The meal moves by exactly that row's own delta — the same arithmetic
        // `FoodTableGrounding` does when it corrects a row.
        #expect(adjusted.kilocalories == meal.kilocalories + (expected.kilocalories - meal.items[0].kilocalories))
    }

    /// The bug another writer has just fixed for a re-analysis, checked from
    /// this side: a row CIQUAL grounded has to still be grounded afterwards,
    /// with the same figures behind it and only the weight moved.
    @Test("a grounded row is still grounded after its quantity changes")
    func provenanceSurvives() throws {
        let meal = try groundedMeal()
        let before = try #require(meal.items[0].macros)

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]),
                to: meal,
                table: table
            )
        )

        let after = try #require(adjusted.items[0].macros)
        // Non-nil is the marker that says "this is a CIQUAL figure"; it must
        // not flip. And the figures are the same row at the new weight.
        #expect(after == (try price("Rice", at: 300)).macros)
        #expect(after != before)
        // The meal's macros follow by the row's own delta, which is a
        // subtraction of two figures the table produced.
        #expect(adjusted.macros.carbs == meal.macros.carbs + (after.carbs - before.carbs))
        #expect(adjusted.macros.protein == meal.macros.protein + (after.protein - before.protein))
    }

    /// A row the table never matched has no per-100 g figures to look up, so
    /// it moves by the ratio of the two weights — arithmetic on the device,
    /// over the model's own earlier estimate, and not a second guess from a
    /// model.
    @Test("a row the table does not know scales from its own recorded weight")
    func scalesAnUngroundedRow() throws {
        let meal = try groundedMeal()

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 2, grams: 200)]),
                to: meal,
                table: table
            )
        )

        #expect(adjusted.items[1].kilocalories == 400)
        #expect(adjusted.items[1].grams == 200)
        #expect(adjusted.items[1].macros == nil)
        // It contributes nothing to the macro total, because nothing on the
        // device knows what share of the meal's macros it ever had.
        #expect(adjusted.macros == meal.macros)
        #expect(adjusted.kilocalories == meal.kilocalories + 200)
    }

    @Test("a row with no weight and no table row cannot be re-priced at all")
    func refusesAnUnpriceableRow() {
        let meal = AdjustableMeal(
            title: "Something",
            kilocalories: 300,
            macros: .zero,
            items: [RecognisedItem(name: "Zzznotafood", kilocalories: 300, note: .text(amount: .estimated))]
        )

        let adjusted = MealAdjuster.apply(
            MealAdjustmentIntent(
                reply: "Doubled it.",
                changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 400)]
            ),
            to: meal,
            table: table
        )

        // Writing the weight alone would leave the row claiming twice the food
        // for the same calories, under a sentence saying it had been adjusted.
        #expect(adjusted == nil)
    }

    // MARK: - Adding food the message named

    /// The owner's second example. "It was quite oily" names no quantity of
    /// anything already on the plate; what it names is oil, which is a food
    /// with a weight, and that is the only shape this contract has for it.
    @Test("an addition joins the list priced from the table")
    func addsAFood() throws {
        let meal = try groundedMeal()
        let oil = try price("Olive oil", at: 10)

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    reply: "Added the oil it was fried in.",
                    additions: [MealAdjustmentIntent.Addition(name: "Olive oil", grams: 10)]
                ),
                to: meal,
                table: table
            )
        )

        #expect(adjusted.items.count == 3)
        #expect(adjusted.items[2].name == "Olive oil")
        #expect(adjusted.items[2].grams == 10)
        #expect(adjusted.items[2].kilocalories == oil.kilocalories)
        // Nothing here read the amount out of a sentence, so the row claims
        // only that the amount was estimated.
        #expect(adjusted.items[2].note == .text(amount: .estimated))
        #expect(adjusted.kilocalories == meal.kilocalories + oil.kilocalories)
        #expect(adjusted.macros.fat == meal.macros.fat + oil.macros.fat)
    }

    @Test("an addition the table cannot price does not join the list")
    func refusesAnUnpriceableAddition() throws {
        let meal = try groundedMeal()

        let adjusted = MealAdjuster.apply(
            MealAdjustmentIntent(
                reply: "Added it.",
                additions: [MealAdjustmentIntent.Addition(name: "Zzznotafood", grams: 40)]
            ),
            to: meal,
            table: table
        )

        #expect(adjusted == nil)
    }

    // MARK: - What does not count as a change

    /// The pin the whole ambiguity ruling hangs on: a message the model could
    /// not map has to come back as "nothing moved", so the screen can say so
    /// rather than showing a sentence over figures that stayed put.
    @Test("a reply that asks for nothing changes nothing")
    func emptyIntentChangesNothing() throws {
        let meal = try groundedMeal()
        let adjusted = MealAdjuster.apply(
            MealAdjustmentIntent(reply: "How much oil roughly?"),
            to: meal,
            table: table
        )
        #expect(adjusted == nil)
    }

    @Test("an item number the list does not have is dropped")
    func dropsAnUnknownItemNumber() throws {
        let meal = try groundedMeal()

        for number in [0, 3, -1] {
            let adjusted = MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: number, grams: 200)]),
                to: meal,
                table: table
            )
            #expect(adjusted == nil)
        }
    }

    @Test("a weight the row already has is not a change")
    func dropsANonChange() throws {
        let meal = try groundedMeal()
        let adjusted = MealAdjuster.apply(
            MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 150)]),
            to: meal,
            table: table
        )
        #expect(adjusted == nil)
    }

    @Test("one usable change carries a reply whose other rows were not")
    func partialAnswerStillApplies() throws {
        let meal = try groundedMeal()

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    changes: [
                        MealAdjustmentIntent.Change(itemNumber: 9, grams: 500),
                        MealAdjustmentIntent.Change(itemNumber: 1, grams: 225),
                    ]
                ),
                to: meal,
                table: table
            )
        )

        #expect(adjusted.items.count == 2)
        #expect(adjusted.items[0].grams == 225)
    }

    // MARK: - The raw-weight annotation

    /// A row that reads `Polenta (raw 45 g)` and now weighs 90 g is a row
    /// lying to the user in the one place the amount is written in words.
    @Test("a raw annotation in the name is restated at the new weight")
    func restatesTheRawAnnotation() throws {
        let raw = try price("Polenta", at: 90, preferring: .raw)
        let atFortyFive = try price("Polenta", at: 45, preferring: .raw)

        let meal = AdjustableMeal(
            title: "Polenta",
            kilocalories: atFortyFive.kilocalories,
            macros: atFortyFive.macros,
            items: [
                RecognisedItem(
                    name: "Polenta (raw 45 g)",
                    kilocalories: atFortyFive.kilocalories,
                    grams: 45,
                    macros: atFortyFive.incompleteMacros ? nil : atFortyFive.macros,
                    note: .text(amount: .recognised)
                )
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 90)]),
                to: meal,
                table: table
            )
        )

        #expect(adjusted.items[0].name == "Polenta (raw 90 g)")
        // Still priced against the raw row, which is what the annotation says
        // it was priced against in the first place.
        #expect(adjusted.items[0].kilocalories == raw.kilocalories)
    }

    @Test("a name without an annotation is left exactly as the model wrote it")
    func leavesAnUnannotatedName() throws {
        let meal = try groundedMeal()
        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 225)]),
                to: meal,
                table: table
            )
        )
        #expect(adjusted.items[0].name == "Rice")
    }

    // MARK: - Without a table

    /// The bundled artefact should always open. If it ever does not, a message
    /// the user has already paid for should still do what it can.
    @Test("a grounded row still scales when the table cannot be opened")
    func scalesWithoutATable() throws {
        let meal = try groundedMeal()

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]),
                to: meal,
                table: nil
            )
        )

        #expect(adjusted.items[0].grams == 300)
        #expect(adjusted.items[0].kilocalories == meal.items[0].kilocalories * 2)
        // Provenance survives here too: scaling a CIQUAL figure keeps it a
        // CIQUAL figure, and the marker stays non-nil.
        #expect(adjusted.items[0].macros != nil)
    }
}

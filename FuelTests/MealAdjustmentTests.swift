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

    /// **The two turns that arrive looking identical.** Both lists empty is a
    /// model that was never moving anything; a list with something in it is a
    /// model that was. Every later decision about what the screen may say under
    /// the sentence rests on this one flag, so it is read here, off the reply's
    /// own data, and nowhere else.
    @Test("a reply that asks for nothing says so, and one that asks says so too")
    func readsWhetherAChangeWasAskedFor() throws {
        let question = try MealChatContract.intent(from: #"{"changes":[],"additions":[],"reply":"Boiled maize."}"#)
        #expect(!question.askedForAChange)

        let adjustment = try MealChatContract.intent(from: #"{"changes":[{"item":1,"grams":300}]}"#)
        #expect(adjustment.askedForAChange)

        let addition = try MealChatContract.intent(from: #"{"additions":[{"name":"Olive oil","grams":10}]}"#)
        #expect(addition.askedForAChange)
    }

    /// **A row the parse threw away is still a model that set out to move
    /// something**, and the flag is read from the rows as they arrived for
    /// exactly this case. A reply whose sentence claims the rice was raised,
    /// with a change object too broken to use, must not reach the screen
    /// looking like a question — nothing else on the turn would then contradict
    /// the claim.
    ///
    /// It is the same direction `MealChatStreamReader.hasAnElement` counts in,
    /// so the warning the stream gives and the turn that lands cannot disagree
    /// about what kind of turn it was.
    @Test(
        "a change row too broken to use still counts as a turn that asked for one",
        arguments: [
            #"{"changes":[{"item":1}],"reply":"Raised the rice to 300 g."}"#,
            #"{"changes":[{"item":1,"grams":0}],"reply":"Raised the rice to 300 g."}"#,
            #"{"additions":[{"grams":10}],"reply":"Added the olive oil."}"#,
        ]
    )
    func droppedRowsStillAskedForAChange(raw: String) throws {
        let intent = try MealChatContract.intent(from: raw)

        #expect(intent.changes.isEmpty)
        #expect(intent.additions.isEmpty)
        #expect(intent.askedForAChange)
    }

    /// Prose asks for nothing, which is what a sentence with no object behind
    /// it plainly is — including one that talks as though it had changed
    /// something, because there is no branch here that takes a change out of a
    /// sentence.
    @Test("an answer written as prose asked for no change")
    func proseAsksForNothing() throws {
        #expect(!(try MealChatContract.intent(from: "Polenta is boiled maize meal.").askedForAChange))
        #expect(!(try MealChatContract.intent(from: "I raised the rice to 300 g for you.").askedForAChange))
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

    // MARK: - Correcting what a row is

    @Test("a correction reads as the food it names")
    func readsCorrections() throws {
        let reply = """
            {"reply":"That is apple compote.","corrections":[{"item":2,"name":"Apple compote"}]}
            """

        let intent = try MealChatContract.intent(from: reply)

        #expect(
            intent.corrections == [
                MealAdjustmentIntent.Correction(itemNumber: 2, name: "Apple compote", grams: nil)
            ]
        )
        #expect(intent.askedForAChange)
    }

    @Test("a correction may restate the weight as well as the food")
    func readsCorrectionWithWeight() throws {
        let intent = try MealChatContract.intent(
            from: #"{"corrections":[{"item":1,"name":"Apple compote","grams":120}]}"#
        )

        #expect(intent.corrections.first?.grams == 120)
    }

    /// A weight of zero or below is not a smaller portion, so it is dropped and
    /// the amount already recorded stands — the row is still corrected, because
    /// the food is what the message was about.
    @Test(
        "a correction with an impossible weight keeps the food and drops the weight",
        arguments: [0, -50]
    )
    func correctionWithEmptyWeight(grams: Int) throws {
        let intent = try MealChatContract.intent(
            from: #"{"corrections":[{"item":1,"name":"Apple compote","grams":\#(grams)}]}"#
        )

        #expect(intent.corrections.first?.name == "Apple compote")
        #expect(intent.corrections.first?.grams == nil)
    }

    @Test("a correction with no name and one with no item number are both dropped")
    func correctionWithoutTheEssentials() throws {
        #expect(try MealChatContract.intent(from: #"{"corrections":[{"item":1}]}"#).corrections.isEmpty)
        #expect(try MealChatContract.intent(from: #"{"corrections":[{"name":"Apple compote"}]}"#).corrections.isEmpty)
    }

    /// **The architecture, checked on the new key.** A correction is where a
    /// model is most tempted to write the figure it thinks the row should have,
    /// because the message it answers is about a figure. There is nowhere for
    /// one to land here either.
    @Test("a correction carrying figures has no field to put them in")
    func correctionFiguresAreNotRead() throws {
        let reply = """
            {"corrections":[{"item":1,"name":"Apple compote","grams":200,\
            "kilocalories":180,"kcal_per_100g":107,"protein_g":1}]}
            """

        let intent = try MealChatContract.intent(from: reply)

        #expect(
            intent.corrections == [
                MealAdjustmentIntent.Correction(itemNumber: 1, name: "Apple compote", grams: 200)
            ]
        )
    }

    /// A canary over the sentence that tells the model what to do when someone
    /// says a figure is wrong. A reword that drops it goes red rather than
    /// quiet, exactly as `promptRefusesSuggestions` does for its own paragraph.
    @Test("the prompt answers a wrong figure with a food name and never a figure")
    func promptAnswersWrongFiguresWithAName() {
        #expect(MealChatContract.systemPrompt.contains("\"corrections\""))
        #expect(
            MealChatContract.systemPrompt.contains(
                "the answer is the right food name in \"corrections\", never a figure of your own"
            )
        )
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

    // MARK: - Correcting what a row is

    /// **The owner's example, end to end.** `Apple sauce` is a name no CIQUAL
    /// row covers — nothing in the table carries both of those words — so
    /// grounding declined it and the row kept the model's own guess of 400 kcal
    /// for 200 g. `Apple compote` is the same food under the name the table
    /// publishes, at 107 kcal/100 g.
    ///
    /// The message says which food it was; the table says what that costs.
    /// Nothing here reads a figure from anything the model wrote.
    @Test("a row named as a different food is re-priced from that food's row")
    func correctsTheFood() throws {
        let meal = AdjustableMeal(
            title: "Pork with apple sauce",
            kilocalories: 700,
            macros: MacroTotals(protein: 30, carbs: 50, fat: 20),
            items: [
                RecognisedItem(
                    name: "Pork chop", kilocalories: 300, grams: 120,
                    note: .photo(confidence: .confident, approximateGrams: 120)
                ),
                RecognisedItem(
                    name: "Apple sauce", kilocalories: 400, grams: 200,
                    confidence: ItemConfidence(estimatePercent: 90),
                    note: .photo(confidence: .confident, approximateGrams: 200)
                ),
            ]
        )

        // The premise: the recorded name resolves to nothing, which is why the
        // row was never priced from the table in the first place.
        #expect(FoodTableGrounding.bestMatch(for: "Apple sauce", preferring: .prepared, in: table) == nil)

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    reply: "Re-priced that as apple compote.",
                    corrections: [
                        MealAdjustmentIntent.Correction(itemNumber: 2, name: "Apple compote")
                    ]
                ),
                to: meal,
                table: table
            )
        )

        let compote = try price("Apple compote", at: 200)
        #expect(adjusted.items[1].name == "Apple compote")
        #expect(adjusted.items[1].kilocalories == compote.kilocalories)
        #expect(adjusted.items[1].macros == compote.macros)
        // The weight was not restated, so the one already recorded stands.
        #expect(adjusted.items[1].grams == 200)
        // Far less than 400, which is what the owner said and what the table says.
        #expect(adjusted.items[1].kilocalories < 400)
        #expect(adjusted.kilocalories == 700 + (compote.kilocalories - 400))
    }

    /// **Only the named item changes.** The row the message did not mention
    /// keeps its name, its figures, its weight, its note and its confidence,
    /// byte for byte — the rule a spliced re-analysis holds to, checked here
    /// because a correction is the instruction most able to break it.
    @Test("a correction leaves every other row exactly as it was")
    func correctionTouchesOnlyItsOwnRow() throws {
        let meal = AdjustableMeal(
            title: "Pork with apple sauce",
            kilocalories: 700,
            macros: MacroTotals(protein: 30, carbs: 50, fat: 20),
            items: [
                RecognisedItem(
                    name: "Pork chop", kilocalories: 300, grams: 120,
                    macros: MacroTotals(protein: 25, carbs: 0, fat: 20),
                    confidence: ItemConfidence(estimatePercent: 80),
                    note: .photo(confidence: .confident, approximateGrams: 120)
                ),
                RecognisedItem(
                    name: "Apple sauce", kilocalories: 400, grams: 200,
                    note: .photo(confidence: .confident, approximateGrams: 200)
                ),
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    corrections: [
                        MealAdjustmentIntent.Correction(itemNumber: 2, name: "Apple compote")
                    ]
                ),
                to: meal,
                table: table
            )
        )

        #expect(adjusted.items[0] == meal.items[0])
    }

    /// The confidence goes with the old name. It measured how sure the model
    /// was about a food this row is no longer, so it leaves the meal's accuracy
    /// average rather than vouching for a reading the user has just corrected.
    @Test("a corrected row loses the confidence it was read with")
    func correctionClearsConfidence() throws {
        let meal = AdjustableMeal(
            title: "Apple sauce",
            kilocalories: 400,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Apple sauce", kilocalories: 400, grams: 200,
                    confidence: ItemConfidence(estimatePercent: 90),
                    note: .photo(confidence: .confident, approximateGrams: 200)
                )
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    corrections: [
                        MealAdjustmentIntent.Correction(itemNumber: 1, name: "Apple compote")
                    ]
                ),
                to: meal,
                table: table
            )
        )

        #expect(meal.items[0].confidence != nil)
        #expect(adjusted.items[0].confidence == nil)
    }

    /// A correction may restate the amount as well as the food, and then both
    /// move together off the row the new name resolves to.
    @Test("a correction that also names a weight prices the new food at it")
    func correctionCarriesAWeight() throws {
        let meal = AdjustableMeal(
            title: "Apple sauce",
            kilocalories: 400,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Apple sauce", kilocalories: 400, grams: 200,
                    note: .photo(confidence: .confident, approximateGrams: 200)
                )
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    corrections: [
                        MealAdjustmentIntent.Correction(itemNumber: 1, name: "Apple compote", grams: 120)
                    ]
                ),
                to: meal,
                table: table
            )
        )

        let compote = try price("Apple compote", at: 120)
        #expect(adjusted.items[0].grams == 120)
        #expect(adjusted.items[0].kilocalories == compote.kilocalories)
    }

    /// **No scaling branch behind a correction**, unlike a quantity change. A
    /// name the table cannot resolve leaves the row alone rather than stretching
    /// the figures of the food it was wrongly recorded as under a new name.
    @Test("a correction the table cannot resolve changes nothing")
    func refusesAnUnresolvableCorrection() throws {
        let meal = AdjustableMeal(
            title: "Apple sauce",
            kilocalories: 400,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Apple sauce", kilocalories: 400, grams: 200,
                    note: .photo(confidence: .confident, approximateGrams: 200)
                )
            ]
        )

        let adjusted = MealAdjuster.apply(
            MealAdjustmentIntent(
                corrections: [
                    MealAdjustmentIntent.Correction(itemNumber: 1, name: "Zzznotafood")
                ]
            ),
            to: meal,
            table: table
        )

        #expect(adjusted == nil)
    }

    /// A row that never had a weight cannot be priced as any food at any
    /// amount, so a correction naming no weight of its own is declined rather
    /// than recorded at an amount nobody stated.
    @Test("a correction with no weight anywhere is declined")
    func refusesACorrectionWithNoWeight() {
        let meal = AdjustableMeal(
            title: "Something",
            kilocalories: 400,
            macros: .zero,
            items: [RecognisedItem(name: "Apple sauce", kilocalories: 400, note: .text(amount: .estimated))]
        )

        #expect(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    corrections: [
                        MealAdjustmentIntent.Correction(itemNumber: 1, name: "Apple compote")
                    ]
                ),
                to: meal,
                table: table
            ) == nil
        )
    }

    /// Corrections run after changes, so a reply that both re-weighs and
    /// re-identifies the same row settles on the food, at the weight the change
    /// just set.
    @Test("a correction over a change in the same reply prices the new food at the new weight")
    func correctionFollowsAChangeOnTheSameRow() throws {
        let meal = AdjustableMeal(
            title: "Apple sauce",
            kilocalories: 400,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Apple sauce", kilocalories: 400, grams: 200,
                    note: .photo(confidence: .confident, approximateGrams: 200)
                )
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(
                    changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 150)],
                    corrections: [
                        MealAdjustmentIntent.Correction(itemNumber: 1, name: "Apple compote")
                    ]
                ),
                to: meal,
                table: table
            )
        )

        let compote = try price("Apple compote", at: 150)
        #expect(adjusted.items[0].name == "Apple compote")
        #expect(adjusted.items[0].grams == 150)
        #expect(adjusted.items[0].kilocalories == compote.kilocalories)
    }

    // MARK: - The macros move with the calories

    /// A meal whose every row the table knows, carrying the model's own
    /// meal-wide macro guess over the top of them.
    ///
    /// **That combination is not contrived: it is what a meal logged before
    /// this rule existed looks like on disk.** Grounding used to correct the
    /// meal's macros only for a single-item reply, so every stored multi-item
    /// meal has CIQUAL figures on its rows and the model's guess above them.
    /// Those entries are still in the store and are still what a message
    /// arrives about.
    private func fullyGroundedMeal() throws -> AdjustableMeal {
        let rice = try price("Rice", at: 150)
        let chicken = try price("Chicken breast", at: 100)

        return AdjustableMeal(
            title: "Rice and chicken",
            kilocalories: rice.kilocalories + chicken.kilocalories,
            macros: MacroTotals(protein: 41, carbs: 62, fat: 14),
            items: [
                RecognisedItem(
                    name: "Rice", kilocalories: rice.kilocalories, grams: 150, macros: rice.macros,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Chicken breast", kilocalories: chicken.kilocalories, grams: 100,
                    macros: chicken.macros,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                ),
            ]
        )
    }

    /// **The defect, on the table branch.** The rice moves and the meal's
    /// protein, carbohydrate and fat move with it, to the figures the rows now
    /// carry rather than to the model's meal-wide guess nudged by a delta.
    ///
    /// The expectation is written as the two rows added up, so that it follows
    /// the arithmetic rather than standing over it as a constant.
    @Test("a changed weight moves the meal's macros as well as its calories")
    func macrosFollowTheTableBranch() throws {
        let meal = try fullyGroundedMeal()

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]),
                to: meal,
                table: table
            )
        )

        let rice = try price("Rice", at: 300)
        let chicken = try price("Chicken breast", at: 100)
        #expect(adjusted.macros == rice.macros + chicken.macros)
        #expect(adjusted.macros != meal.macros)
        #expect(adjusted.kilocalories != meal.kilocalories)
    }

    /// **The defect as the owner met it**: a row that had no macro figure at
    /// all before the message and has CIQUAL's afterwards.
    ///
    /// A typed meal whose sentence named no weight is never grounded — there is
    /// no amount to price it at — so it arrives here with the model's own
    /// kilocalorie guess, no per-row macros, and the model's meal-wide macro
    /// estimate over the top. The message supplies the weight. The calories
    /// then moved and the macros stood still, because a delta needs a figure on
    /// both sides of the change and this row had none on the near side.
    @Test("a row that gains its first macro figure moves the meal's macros too")
    func macrosFollowARowThatHadNone() throws {
        let modelMacros = MacroTotals(protein: 9, carbs: 40, fat: 7)
        let meal = AdjustableMeal(
            title: "Rice",
            kilocalories: 250,
            macros: modelMacros,
            items: [
                RecognisedItem(name: "Rice", kilocalories: 250, note: .text(amount: .estimated))
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 200)]),
                to: meal,
                table: table
            )
        )

        let rice = try price("Rice", at: 200)
        #expect(adjusted.items[0].macros == rice.macros)
        #expect(adjusted.macros == rice.macros)
        #expect(adjusted.macros != modelMacros)
    }

    /// **The same defect on the scaling branch**, where no table row is
    /// involved at any point. Both rows carry macros the meal's own figure was
    /// never composed from, so the delta moved the meal off a base that had
    /// nothing to do with the rows underneath it.
    @Test("a scaled row moves the meal's macros to what the rows now say")
    func macrosFollowTheScalingBranch() throws {
        let first = MacroTotals(protein: 10, carbs: 20, fat: 4)
        let second = MacroTotals(protein: 6, carbs: 12, fat: 2)
        let meal = AdjustableMeal(
            title: "Two things the table has never heard of",
            kilocalories: 500,
            // Deliberately not the sum of the rows: this is the model's own
            // meal-wide guess, which is what such a meal actually carries.
            macros: MacroTotals(protein: 31, carbs: 55, fat: 19),
            items: [
                RecognisedItem(
                    name: "Zzznotafood", kilocalories: 300, grams: 100, macros: first,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                ),
                RecognisedItem(
                    name: "Qqxnotafood", kilocalories: 200, grams: 100, macros: second,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                ),
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 150)]),
                to: meal,
                table: table
            )
        )

        // Neither row resolved, so both figures are the device scaling the
        // model's own earlier estimate by the ratio of the two weights.
        let scaled = MacroTotals(protein: 15, carbs: 30, fat: 6)
        #expect(adjusted.items[0].macros == scaled)
        #expect(adjusted.items[1].macros == second)
        #expect(adjusted.macros == scaled + second)
        #expect(adjusted.kilocalories == 500 + 150)
    }

    /// The rule stops where the rows stop being able to answer. One row without
    /// a macro figure means summing would drop it, so the meal's standing
    /// figure is moved by the honest deltas instead — which is what
    /// `groundedMeal` already exercises and what this pins as deliberate.
    @Test("a meal with one figureless row still moves by the delta and not by a sum")
    func mixedMealKeepsTheDeltaRule() throws {
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
        #expect(adjusted.items[1].macros == nil)
        #expect(adjusted.macros == MacroTotals(
            protein: meal.macros.protein + (after.protein - before.protein),
            carbs: meal.macros.carbs + (after.carbs - before.carbs),
            fat: meal.macros.fat + (after.fat - before.fat)
        ))
        // And emphatically not the sum of the rows, which would have thrown the
        // second row's share of the meal away.
        #expect(adjusted.macros != after)
    }

    // MARK: - A meal logged before any row carried macros

    /// A meal in the state the store is full of: rows the table could price,
    /// with no macro figure on any of them, under the model's own meal-wide
    /// guess.
    ///
    /// **The kilocalorie figures are deliberately the model's and not the
    /// table's**, so that a test can tell a row that was left alone from a row
    /// that was quietly re-priced. And the meal's own macros are deliberately
    /// not the sum of anything: they are what a model wrote about the plate,
    /// which is the only figure such an entry has ever held.
    private func unpricedMeal() -> AdjustableMeal {
        AdjustableMeal(
            title: "Rice and chicken",
            kilocalories: 430,
            macros: MacroTotals(protein: 11, carbs: 70, fat: 6),
            items: [
                RecognisedItem(
                    name: "Rice", kilocalories: 250, grams: 150,
                    confidence: ItemConfidence(estimatePercent: 80),
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Chicken breast", kilocalories: 180, grams: 100,
                    confidence: ItemConfidence(estimatePercent: 70),
                    note: .photo(confidence: .confident, approximateGrams: 100)
                ),
            ]
        )
    }

    /// **The defect the owner reported twice.** Every row of an older meal is
    /// figureless, so the sum rule declined and the delta rule had nothing to
    /// take a difference of: the calories moved and the macros did not, on any
    /// row, however the message was worded.
    ///
    /// The rows are priced against the table at the amounts already recorded
    /// for them before a single instruction is applied, so the sum rule applies
    /// and the meal's macros are what its rows now say.
    @Test("a meal whose rows never carried macros moves them when an amount changes")
    func macrosMoveOnAMealWithNoRowFigures() throws {
        let meal = unpricedMeal()

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]),
                to: meal,
                table: table
            )
        )

        let rice = try price("Rice", at: 300)
        let chicken = try price("Chicken breast", at: 100)
        #expect(adjusted.macros == rice.macros + chicken.macros)
        #expect(adjusted.macros != meal.macros)
    }

    /// **The row nobody asked about must not move where the user can see it.**
    /// Pricing fills in the chicken's macros, which is a figure that was
    /// missing; it must not touch the chicken's calories, its name, its note or
    /// its confidence, because a stored figure changing under a row the message
    /// never mentioned is a change the user did not ask for.
    ///
    /// The rice is the row the message was about, and it is re-priced from the
    /// table in full — which is the change that *was* asked for.
    @Test("pricing a row for its macros leaves its calories, name and confidence alone")
    func pricingIsInvisibleOnRowsTheMessageDidNotName() throws {
        let meal = unpricedMeal()

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]),
                to: meal,
                table: table
            )
        )

        let chicken = try price("Chicken breast", at: 100)
        // The chicken gained the table's macros and nothing else. Its stored
        // energy is still the model's 180 and not the table's figure for 100 g.
        #expect(adjusted.items[1].macros == chicken.macros)
        #expect(adjusted.items[1].kilocalories == 180)
        #expect(adjusted.items[1].kilocalories != chicken.kilocalories)
        #expect(adjusted.items[1].name == "Chicken breast")
        #expect(adjusted.items[1].grams == 100)
        #expect(adjusted.items[1].confidence == ItemConfidence(estimatePercent: 70))
        #expect(adjusted.items[1].note == .photo(confidence: .confident, approximateGrams: 100))

        // And the row that was asked about is priced in full, energy included.
        let rice = try price("Rice", at: 300)
        #expect(adjusted.items[0].kilocalories == rice.kilocalories)
        #expect(adjusted.items[0].macros == rice.macros)
        #expect(adjusted.items[0].confidence == ItemConfidence(estimatePercent: 80))
    }

    /// **One row the table has never heard of used to freeze the whole meal**,
    /// including when the message was about a different row entirely. It no
    /// longer does: the rice is priced at the weight it already had, so the
    /// change to it has a real figure on both sides and the delta rule — which
    /// is still what applies, because summing would drop the unknown row —
    /// finally has something to move by.
    @Test("a meal with one row the table cannot cover still moves when another row changes")
    func macrosMoveAroundAnUngroundableRow() throws {
        let meal = AdjustableMeal(
            title: "Rice and something",
            kilocalories: 630,
            macros: MacroTotals(protein: 11, carbs: 70, fat: 6),
            items: [
                RecognisedItem(
                    name: "Rice", kilocalories: 250, grams: 150,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Zzznotafood", kilocalories: 200, grams: 100,
                    note: .photo(confidence: .unsure, approximateGrams: 100)
                ),
                RecognisedItem(
                    name: "Chicken breast", kilocalories: 180, grams: 100,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                ),
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 300)]),
                to: meal,
                table: table
            )
        )

        let before = try price("Rice", at: 150)
        let after = try price("Rice", at: 300)
        #expect(adjusted.macros == MacroTotals(
            protein: meal.macros.protein + (after.macros.protein - before.macros.protein),
            carbs: meal.macros.carbs + (after.macros.carbs - before.macros.carbs),
            fat: meal.macros.fat + (after.macros.fat - before.macros.fat)
        ))
        #expect(adjusted.macros != meal.macros)

        // The unknown row is still unknown, and is untouched in every other
        // respect too. The chicken is priced for its macros and keeps its
        // energy, exactly as on a meal with no unknown row in it.
        #expect(adjusted.items[1].macros == nil)
        #expect(adjusted.items[1].kilocalories == 200)
        #expect(adjusted.items[1].name == "Zzznotafood")
        #expect(adjusted.items[2].macros == (try price("Chicken breast", at: 100)).macros)
        #expect(adjusted.items[2].kilocalories == 180)
    }

    /// **What stands when nothing in the meal can be priced.** A single row
    /// whose name no CIQUAL row covers has no macro figure before the message
    /// and none after it, so the sum is impossible and the delta is honestly
    /// zero: the meal keeps the model's macro estimate while its energy scales
    /// with the amount. That is the same answer as before this pass existed,
    /// and it is the honest one — nothing on the device knows what that row is
    /// made of.
    @Test("a meal of rows the table cannot cover keeps the macro figure it had")
    func anUngroundableMealKeepsItsStandingMacros() throws {
        let standing = MacroTotals(protein: 12, carbs: 44, fat: 9)
        let meal = AdjustableMeal(
            title: "Something the table has never heard of",
            kilocalories: 300,
            macros: standing,
            items: [
                RecognisedItem(
                    name: "Zzznotafood", kilocalories: 300, grams: 100,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                )
            ]
        )

        let adjusted = try #require(
            MealAdjuster.apply(
                MealAdjustmentIntent(changes: [MealAdjustmentIntent.Change(itemNumber: 1, grams: 150)]),
                to: meal,
                table: table
            )
        )

        #expect(adjusted.items[0].macros == nil)
        #expect(adjusted.macros == standing)
        #expect(adjusted.kilocalories == 450)
    }

    /// A turn that moved nothing writes nothing, and that includes the macros
    /// this pass would have filled in. `nil` is what tells the caller the meal
    /// is as it was, so a question about a meal must not come back holding a
    /// repriced version of it.
    @Test("a question about a meal does not price its rows behind the user's back")
    func aQuestionPricesNothing() {
        let question = MealAdjustmentIntent(reply: "How filling is this?")

        #expect(MealAdjuster.apply(question, to: unpricedMeal(), table: table) == nil)
    }
}

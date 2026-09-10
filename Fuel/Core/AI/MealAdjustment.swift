import Foundation

// MARK: - The meal being talked about

/// A logged meal, in the shape a conversation about its amounts needs it.
///
/// **Deliberately not `MealEstimate`.** That type is what a model produced;
/// this is what a meal already is, and the difference shows in what is
/// missing. There is no `advice` here, because a remark written about the meal
/// as it was estimated is not a remark about the meal after the rice was
/// doubled, and there is no path here that would rewrite one. The `title` is
/// present but is never written back — see `AdjustedMeal`.
nonisolated struct AdjustableMeal: Sendable, Equatable {

    var title: String
    var kilocalories: Int
    var macros: MacroTotals
    var items: [RecognisedItem]

    init(title: String, kilocalories: Int, macros: MacroTotals, items: [RecognisedItem]) {
        self.title = title
        self.kilocalories = kilocalories
        self.macros = macros
        self.items = items
    }
}

// MARK: - What the model asked for

/// The changes a reply asks for, before anything has decided whether they can
/// be made.
///
/// **It carries no figure of any kind and there is no field it could carry one
/// in.** Names and weights are the whole of what it says about food. See
/// `MealChatContract` for why that is the architecture rather than a
/// simplification.
///
/// **A correction is a third kind of instruction and still not a figure.** A
/// user who says the apple sauce cannot possibly be 400 kcal is not quoting a
/// number they want written down; they are saying the row is not the food it
/// was priced as. `Correction` carries the food it actually was, and the table
/// prices it. See that type.
nonisolated struct MealAdjustmentIntent: Sendable, Equatable {

    /// The model's own sentence, already bounded. `nil` where it wrote nothing
    /// usable, which is not an error and not rare.
    var reply: String?

    var changes: [Change]
    var corrections: [Correction]
    var additions: [Addition]

    /// Whether the reply asked for anything at all to move.
    ///
    /// **What tells a question apart from a change that moved nothing**, which
    /// are otherwise the same thing by the time they reach the screen: a
    /// sentence over a meal that did not budge. One of them is an answer and
    /// wants nothing said under it; the other is a model claiming something
    /// happened that did not, and has to be contradicted. Neither is readable
    /// from the words, and neither has to be — the model wrote which it was
    /// when it opened or did not open its three arrays.
    ///
    /// **Stored rather than `!changes.isEmpty || !additions.isEmpty`, and the
    /// difference is the reason it exists.** A row the parse could not read —
    /// an item with no weight on it, an addition with no name — is dropped from
    /// the arrays above and is still a model that committed to moving
    /// something. `MealChatStreamReader.hasAnElement` counts a half-written
    /// object for exactly the same reason and in the same direction, so the
    /// early warning and the finished turn cannot disagree about what kind of
    /// turn this was.
    var askedForAChange: Bool

    /// `askedForAChange` follows from the rows unless it is stated, so the only
    /// caller that has to think about it is the one that has seen rows this
    /// initialiser never will: `MealChatContract.intent(from:)`, which reads
    /// the three arrays as they arrived rather than after they were filtered.
    init(
        reply: String? = nil,
        changes: [Change] = [],
        corrections: [Correction] = [],
        additions: [Addition] = [],
        askedForAChange: Bool? = nil
    ) {
        self.reply = reply
        self.changes = changes
        self.corrections = corrections
        self.additions = additions
        self.askedForAChange = askedForAChange
            ?? (!changes.isEmpty || !corrections.isEmpty || !additions.isEmpty)
    }

    /// One existing row, at a new weight.
    ///
    /// `itemNumber` is one-based and is exactly what the model wrote. It has
    /// not been checked against anything yet: this type is the reply, not the
    /// verdict on it.
    nonisolated struct Change: Sendable, Equatable {

        var itemNumber: Int
        var grams: Int

        init(itemNumber: Int, grams: Int) {
            self.itemNumber = itemNumber
            self.grams = grams
        }
    }

    /// One existing row, said to be a different food from the one it is
    /// recorded as.
    ///
    /// **This is the answer to "these figures are far too high", and the reason
    /// that sentence does not need a figure field to answer it.** A row is
    /// priced by looking its name up in CIQUAL; a row whose figures are wrong
    /// is, almost always, a row whose name found the wrong table entry or found
    /// none at all. `Apple sauce` is the live example — no CIQUAL row covers
    /// both of those words, so the row keeps the model's own guess of 400 kcal
    /// for 200 g, while `Apple compote` is right there at 107 kcal/100 g. The
    /// remedy is a better name, not a better number.
    ///
    /// So this carries the food it actually was, and `MealAdjuster` prices that
    /// against the table exactly as it prices everything else. A model that
    /// wanted to assert 180 kcal still has nowhere to write it.
    ///
    /// `grams` is `nil` where the message corrected only the food. The weight
    /// already recorded for the row then stands — the user said what it was,
    /// not how much of it there was, and inventing a new amount would answer a
    /// question nobody asked.
    nonisolated struct Correction: Sendable, Equatable {

        var itemNumber: Int
        var name: String
        var grams: Int?

        init(itemNumber: Int, name: String, grams: Int? = nil) {
            self.itemNumber = itemNumber
            self.name = name
            self.grams = grams
        }
    }

    /// A food the message named that the list does not have.
    nonisolated struct Addition: Sendable, Equatable {

        var name: String
        var grams: Int

        init(name: String, grams: Int) {
            self.name = name
            self.grams = grams
        }
    }
}

// MARK: - What the meal became

/// A meal after an adjustment, in the three things an adjustment is allowed to
/// move.
///
/// **The title is not one of them, and neither is the advisor line where one
/// exists.** A message about how much rice there was does not rename the meal,
/// and a model asked only about weights has not been asked what the meal is
/// called. This is the same rule a spliced re-analysis holds to, arrived at
/// from the other side: what was not asked about does not change.
nonisolated struct AdjustedMeal: Sendable, Equatable {

    var kilocalories: Int
    var macros: MacroTotals
    var items: [RecognisedItem]

    init(kilocalories: Int, macros: MacroTotals, items: [RecognisedItem]) {
        self.kilocalories = kilocalories
        self.macros = macros
        self.items = items
    }
}

// MARK: - What came back

/// One turn's answer: what the model said, what it asked to move, and what —
/// if anything — actually moved.
///
/// **The three are separate on purpose, and `meal` being `nil` is the case
/// worth building for.** A model that could not map "it was quite oily" onto a
/// weight, a model that named an item number the list does not have, a model
/// that asked for a food the table cannot price — all of them produce a
/// sentence and no change. The screen has to be able to say that, rather than
/// showing a reply over figures that did not move and letting the user infer
/// that they did.
///
/// **And a question produces a sentence and no change as well, which is why
/// there are three of these and not two.** "How filling is this" was never
/// about the amounts, so a note saying they did not move is Fuel answering a
/// question nobody asked; the same note under a model that claimed to have
/// raised the rice is the only thing on screen telling the truth.
nonisolated struct MealAdjustmentOutcome: Sendable, Equatable {

    var reply: String?

    /// Whether the reply asked for anything to move, whatever came of it.
    ///
    /// It travels beside the sentence because `meal` cannot answer it: a `nil`
    /// meal is both a question that never asked for a change and a change that
    /// asked and did not survive, and the screen says something different about
    /// each. `MealAdjustmentIntent.askedForAChange` is where it is read, and
    /// says why it is read from the model's own three arrays rather than from
    /// anything the model wrote about itself.
    var askedForAChange: Bool

    var meal: AdjustedMeal?

    init(reply: String?, askedForAChange: Bool, meal: AdjustedMeal?) {
        self.reply = reply
        self.askedForAChange = askedForAChange
        self.meal = meal
    }

    /// Whether anything about the meal is different because of this turn.
    var changedTheMeal: Bool {
        meal != nil
    }
}

// MARK: - Applying an adjustment

/// Turns the weights a model asked for into the figures the screen draws, by
/// pricing them against the table.
///
/// **This is the half of the contract the device enforces, and it is the half
/// that matters.** `MealChatContract` asks a model not to answer with
/// calories; this makes it impossible for one to, by never reading a figure
/// from a reply and computing every one of them here. A model that ignored
/// every line of that prompt and returned a full nutrition table would change
/// nothing about what the user sees except the weights it also happened to
/// give.
///
/// **Provenance survives a quantity change, and does so by being re-derived
/// rather than carried.** A row grounded against CIQUAL is looked up again, by
/// the same name, in the same table, at the same preparation — a deterministic
/// query that returns the same row — and priced by `PortionCalculator` at the
/// new weight. So a grounded row comes out grounded, with the same per-100 g
/// figures behind it and a new weight in front of them, and the `macros`
/// non-`nil` marker that says "this is a CIQUAL figure" cannot flip to `nil`
/// on a row whose row is still there.
///
/// **The meal's own figures come from the rows the adjustment leaves, and only
/// fall back to a delta where the rows cannot answer.** Kilocalories move by
/// each row's own delta: every row has a real prior kilocalorie figure to
/// subtract, and the meal's total has already been reconciled against those
/// figures by `FoodTableGrounding`, which adjusts it by exactly this kind of
/// delta. Macros go the other way round, through
/// `MealArithmetic.macros(ofRows:)` — once every row carries a complete macro
/// figure the meal's macros are their sum, whatever the meal's figure used to
/// say.
///
/// **That is the fix for a meal whose calories moved and whose macros did
/// not.** A delta needs a real figure on *both* sides of the change, and the
/// commonest thing a message does is give a row its first weight — a typed meal
/// grounding declined for want of one, a photo row the table never matched —
/// so the row arrives with no macros, leaves with CIQUAL's, and had no prior
/// figure to take a delta against. Under the delta rule alone it contributed
/// nothing: the kilocalories moved and the protein, carbohydrate and fat stood
/// still at the old amount's values, on the same screen, describing the same
/// plate. Summing the rows has no such hole, because it never asks what a row
/// used to be.
///
/// **That was half a fix, and the other half is that the rows are priced
/// before any instruction is applied to them.** Summing needs *every* row to
/// carry a figure, so one row without one froze the macros of the whole meal —
/// including when the message was about a different row entirely, and
/// including the commonest case there is, a meal logged before any row carried
/// macros at all, where every row is that row. `pricingMacros(of:in:)` runs
/// first and gives each figureless row CIQUAL's macros for the amount already
/// recorded against it, so a meal from before this shipped reaches the three
/// instructions as a meal whose rows are priced. It fills the macros in and
/// leaves the energy exactly as stored, which is the difference between
/// answering the message and rewriting the meal; see that function.
///
/// Where a row still has no macro figure — a name no CIQUAL row covers, a row
/// with no weight recorded, a row whose table entry has a macro gap of its own
/// — the sum remains impossible and the delta rule is what stands, unchanged:
/// the meal's macro figure is the model's meal-wide estimate, moved by the
/// honest differences on the rows that had a real figure on both sides of the
/// change. What the pricing pass buys such a meal is that a row it priced now
/// *has* a figure on both sides, so a change to it moves the meal instead of
/// contributing nothing to it.
nonisolated enum MealAdjuster {

    // MARK: - Entry point

    /// Applies `intent` to `meal` against the table bundled with the app, or
    /// against no table at all if it cannot be opened.
    ///
    /// A missing or corrupt table is not a reason to fail a message the user
    /// has already paid for. Without it a row can still be re-priced from its
    /// own figures — see `repricing(_:to:in:)` — which for a grounded row is
    /// the same arithmetic the table would have done, off the same numbers.
    static func applyAgainstBundledTable(
        _ intent: MealAdjustmentIntent,
        to meal: AdjustableMeal
    ) -> AdjustedMeal? {
        apply(intent, to: meal, table: try? FoodTable.bundled())
    }

    /// The same application, against a table the caller already has open.
    /// Tests use this so a table is opened once for many cases.
    ///
    /// Returns `nil` when nothing survived — no change named a row that could
    /// be re-priced, and no addition named a food that could be. **That is the
    /// answer, not a failure**: the caller shows the model's sentence and says
    /// the meal is as it was. A `nil` here and an empty reply from the model
    /// are deliberately the same outcome, because to the user they are.
    static func apply(
        _ intent: MealAdjustmentIntent,
        to meal: AdjustableMeal,
        table: FoodTable?
    ) -> AdjustedMeal? {
        var items = meal.items.map { pricingMacros(of: $0, in: table) }
        var kilocalorieDelta = 0
        var macroDelta = MacroTotals.zero
        // The energy that moved on rows carrying no macro figure of their own.
        // It is what the meal's macros are apportioned by where the rows cannot
        // sum — see `MealArithmetic.macros(_:movedBy:andByTheEnergyShareOf:
        // ofAMealOf:)`, which holds the whole of that rule and its cost.
        var unpricedKilocalorieDelta = 0
        var moved = false

        // Later changes to the same row win, which is what reading a list in
        // order means. A model that named row 2 twice has changed its mind
        // inside one reply, and the second number is the one it settled on.
        for change in intent.changes {
            let index = change.itemNumber - 1
            guard items.indices.contains(index) else {
                continue
            }

            let previous = items[index]
            guard
                previous.weightInGrams != change.grams,
                let repriced = repricing(previous, to: change.grams, in: table)
            else {
                continue
            }

            account(previous, repriced, &kilocalorieDelta, &macroDelta, &unpricedKilocalorieDelta)
            items[index] = repriced
            moved = true
        }

        // **After the changes and before the additions**, and the order is the
        // rule rather than an accident. A correction is the more specific
        // statement about a row — it names the food, where a change names only
        // an amount — so where a reply carries both about the same row the
        // correction is what settles it. Running second also means a
        // correction with no weight of its own picks up the weight a change in
        // the same reply just set, which is the reading a user who said "that
        // was apple compote, and there was more of it" would expect.
        for correction in intent.corrections {
            let index = correction.itemNumber - 1
            guard items.indices.contains(index) else {
                continue
            }

            let previous = items[index]
            guard let corrected = reidentifying(previous, as: correction, in: table) else {
                continue
            }

            account(previous, corrected, &kilocalorieDelta, &macroDelta, &unpricedKilocalorieDelta)
            items[index] = corrected
            moved = true
        }

        for addition in intent.additions {
            guard let item = added(addition, in: table) else {
                continue
            }
            kilocalorieDelta += item.kilocalories
            if let macros = item.macros {
                macroDelta = macroDelta + macros
            } else {
                // A row the table priced for energy and not for macros — a
                // CIQUAL entry with a gap of its own. It joins the meal, so the
                // meal's macros owe it its share.
                unpricedKilocalorieDelta += item.kilocalories
            }
            items.append(item)
            moved = true
        }

        guard moved else {
            return nil
        }

        return AdjustedMeal(
            kilocalories: MealArithmetic.kilocalories(meal.kilocalories, movedBy: kilocalorieDelta),
            macros: MealArithmetic.macros(ofRows: items.map(\.macros))
                ?? MealArithmetic.macros(
                    meal.macros,
                    movedBy: macroDelta,
                    andByTheEnergyShareOf: unpricedKilocalorieDelta,
                    ofAMealOf: meal.kilocalories
                ),
            items: items
        )
    }

    // MARK: - Pricing a row that never carried macros

    /// `item` with CIQUAL's protein, carbohydrate and fat filled in, where it
    /// had none and the table can price the amount already recorded against
    /// it. Otherwise `item`, untouched.
    ///
    /// **Every row, and not only the rows the message names — that is the
    /// whole of why it exists.** `MealArithmetic.macros(ofRows:)` is all of
    /// them or none of them, so one figureless row anywhere in the list sends
    /// the meal down the delta rule however many of the others moved, and a row
    /// that had no prior figure contributes nothing to that delta either. A
    /// meal logged before grounding wrote per-row macros carries a list where
    /// *every* row is that row, and that is the meal the owner reported twice:
    /// the message raised the rice, the calories followed it, and the protein,
    /// carbohydrate and fat stood at the values of an amount no longer on the
    /// plate.
    ///
    /// **Only the macros are written; the kilocalorie figure is left exactly as
    /// it stands.** The table answers both — `PortionCalculator` returns all
    /// four numbers from one lookup — and taking the energy as well would move
    /// a row the user never mentioned, and with it the meal's total and the
    /// day's ring, on the strength of a lookup that happens to succeed today
    /// over a meal logged weeks ago. Filling in a figure that was missing is
    /// not a change the user can see; a different number beside a row they did
    /// not ask about is. So the row keeps the energy the meal's own total was
    /// already reconciled against, and gains the table's macros.
    ///
    /// That does split one row's four figures across two sources.
    /// `RecognisedItem.macros` states what still holds and what no longer does:
    /// a non-`nil` value there is a CIQUAL figure, and it says nothing about
    /// where the number above it came from. The cost is the divergence this
    /// file's own header sets out at length — a user multiplying out the macro
    /// bars lands a few per cent under the ring — and it is much the smaller of
    /// the two, because the alternative is a stored calorie figure moving on
    /// its own.
    ///
    /// **Nothing about how the row presents itself changes**: the name is the
    /// model's, the note under it is the model's, and so is the confidence.
    /// That last is `repricing(_:to:in:)`'s reading rather than
    /// `reidentifying(_:as:in:)`'s, and for the sharper version of the same
    /// reason — `ItemConfidence` carries the model's own answers about its own
    /// work, a correction clears it because the *user* has just said the model
    /// read the food wrong, and here nobody has said anything about this row at
    /// all. `groundingPercent` is where a verdict on a table match would go if
    /// one were ever asked for, and nothing writes it.
    ///
    /// A row the table cannot cover comes back untouched, and so do a row with
    /// no weight recorded and a row whose CIQUAL entry has a macro gap of its
    /// own — the polenta case, where writing a zero would print a measurement
    /// nobody made. The meal keeps the delta rule for those, exactly as before.
    ///
    /// **A turn that moves nothing writes nothing.** These rows are discarded
    /// along with everything else when `apply` answers `nil`, so a question
    /// about a meal cannot quietly reprice it.
    private static func pricingMacros(of item: RecognisedItem, in table: FoodTable?) -> RecognisedItem {
        guard
            item.macros == nil,
            let table,
            let grams = item.weightInGrams,
            grams > 0,
            let match = FoodTableGrounding.bestMatch(
                for: item.name,
                preferring: preparation(of: item.name),
                in: table
            )
        else {
            return item
        }

        let portion = PortionCalculator.portion(of: match.per100g, grams: Double(grams))
        guard !portion.incompleteMacros else {
            return item
        }

        var priced = item
        priced.macros = portion.macros
        return priced
    }

    // MARK: - Re-pricing one row

    /// `item` at a new weight, or `nil` if there is no honest way to price it
    /// there.
    ///
    /// **Two routes, and the table comes first.** A name that resolves to a
    /// CIQUAL row is priced from that row at the new weight, which is what
    /// keeps the table the source of truth for what a food is made of and the
    /// model the source of nothing but how much of it there was.
    ///
    /// Behind that, a row scales from its own figures. This is not a weaker
    /// answer for a grounded row — it is the same arithmetic against the same
    /// numbers, since a grounded row's figures *are* a per-100 g row times its
    /// weight — and for a row the table never matched it is the only answer
    /// available: the model's own estimate, moved by the ratio of the two
    /// weights. Either way the figures are the device's arithmetic and not a
    /// model's assertion.
    ///
    /// **`nil` where neither route exists**, which is a row the table does not
    /// know and that has no weight recorded to scale from. Applying the weight
    /// alone would leave the row saying it now holds twice as much food for
    /// exactly the same calories, under a sentence claiming something had been
    /// adjusted. The change is dropped instead, and if it was the only one the
    /// caller says so.
    ///
    /// A row this re-prices may come out grounded that was not grounded
    /// before, and that is correct rather than surprising: grounding declines
    /// a typed meal it cannot attach a weight to, and the whole point of
    /// storing weights is that such a meal now has one.
    ///
    /// **The row keeps the confidence it arrived with**, for the reason
    /// `RecognisedItem.setWeight(_:)` gives about the word beside it: the
    /// model's certainty is about what it was looking at, and a change of
    /// amount does not answer that either way. So a meal whose quantity the
    /// user corrected in the chat carries the same accuracy figure afterwards
    /// — the figure moves when the model's certainty is asked again, which is
    /// what a re-analysis does, and not when a number is edited on the device.
    private static func repricing(
        _ item: RecognisedItem,
        to grams: Int,
        in table: FoodTable?
    ) -> RecognisedItem? {
        var repriced = item
        repriced.setWeight(grams)
        repriced.name = renaming(item.name, toRawAmount: grams)

        if
            let table,
            let match = FoodTableGrounding.bestMatch(for: item.name, preferring: preparation(of: item.name), in: table)
        {
            let portion = PortionCalculator.portion(of: match.per100g, grams: Double(grams))
            repriced.kilocalories = portion.kilocalories
            // A row missing one of its own macros — CIQUAL has no fat figure
            // for cooked polenta — stays `nil` rather than reporting a zero
            // nothing measured, exactly as it did when it was first grounded.
            repriced.macros = portion.incompleteMacros ? nil : portion.macros
            return repriced
        }

        guard let previous = item.weightInGrams, previous > 0 else {
            return nil
        }

        let ratio = Double(grams) / Double(previous)
        repriced.kilocalories = whole(Double(item.kilocalories) * ratio)
        repriced.macros = item.macros.map { macros in
            MacroTotals(
                protein: whole(Double(macros.protein) * ratio),
                carbs: whole(Double(macros.carbs) * ratio),
                fat: whole(Double(macros.fat) * ratio)
            )
        }
        return repriced
    }

    // MARK: - Re-identifying one row

    /// `item` as the food the message says it actually was, or `nil` where
    /// there is no honest way to price it as that food.
    ///
    /// **One route, and it is the table.** Unlike a quantity change there is no
    /// scaling branch behind this, and there must not be: scaling would take
    /// the figures of the food the row was wrongly recorded as and stretch
    /// them, which is the wrong number carried forward under a new name. A
    /// correction the table cannot resolve is dropped, and if it was the only
    /// instruction in the reply the caller says the meal did not move — the
    /// same answer an unpriceable addition gets, for the same reason.
    ///
    /// **Only this row changes.** Every other row keeps its name, its figures,
    /// its provenance and its confidence, which is the rule a spliced
    /// re-analysis already holds to.
    ///
    /// The weight is the message's where it gave one and the row's own
    /// otherwise, and a row with neither cannot be priced at any weight, so it
    /// is declined rather than recorded at an amount nobody stated.
    ///
    /// **The confidence goes with the old name**, which is the one thing here
    /// that differs from a quantity change. `repricing(_:to:in:)` keeps it,
    /// because how sure the model was about what it was looking at is not
    /// answered either way by an amount. A correction answers it directly and
    /// in the negative: the user has just said the model read the food wrong,
    /// so the figure leaves the meal's accuracy average rather than going on
    /// vouching for a row it was never about. `MealResultDraft.editItem(_:to:)`
    /// clears it for the same reason when the user retypes a row by hand.
    ///
    /// The note is left exactly as it was. It says how the amount was arrived
    /// at, which a change of food does not answer, and the shapes it can take
    /// are the two the export draws — there is no drawn form for "the user
    /// named this one", and inventing one is a design question rather than a
    /// gap to fill here.
    private static func reidentifying(
        _ item: RecognisedItem,
        as correction: MealAdjustmentIntent.Correction,
        in table: FoodTable?
    ) -> RecognisedItem? {
        guard
            let table,
            let grams = correction.grams ?? item.weightInGrams,
            grams > 0,
            let match = FoodTableGrounding.bestMatch(for: correction.name, preferring: .prepared, in: table)
        else {
            return nil
        }

        let portion = PortionCalculator.portion(of: match.per100g, grams: Double(grams))

        var corrected = item
        corrected.name = correction.name
        corrected.setWeight(grams)
        corrected.kilocalories = portion.kilocalories
        corrected.macros = portion.incompleteMacros ? nil : portion.macros
        corrected.confidence = nil
        return corrected
    }

    /// The row an addition becomes, or `nil` if the table cannot price it.
    ///
    /// **An addition has no prior figures to scale from**, so unlike a change
    /// it has exactly one route. A food the table does not know would join the
    /// list with a name, a weight and no calories — a row that says the meal
    /// grew and the total did not — so it does not join it at all.
    ///
    /// Its note is `text(amount: .estimated)`, and both halves are meant. The
    /// amount came from a model reading a typed sentence, which is what the
    /// text case describes; and `estimated` rather than `recognised` because
    /// nothing here can tell whether the user named the amount or the model
    /// inferred it, and claiming they stated something they did not is the
    /// worse of the two mistakes — the same reading `EstimateContract` gives
    /// an unreadable `amount` field.
    private static func added(
        _ addition: MealAdjustmentIntent.Addition,
        in table: FoodTable?
    ) -> RecognisedItem? {
        guard
            let table,
            let match = FoodTableGrounding.bestMatch(for: addition.name, preferring: .prepared, in: table)
        else {
            return nil
        }

        let portion = PortionCalculator.portion(of: match.per100g, grams: Double(addition.grams))
        return RecognisedItem(
            name: addition.name,
            kilocalories: portion.kilocalories,
            grams: addition.grams,
            macros: portion.incompleteMacros ? nil : portion.macros,
            // No confidence, because none was asked for: `MealChatContract`
            // asks the model what to change, not how sure it is. The row joins
            // the meal without a figure and is left out of the average rather
            // than borrowing one from the rows that were estimated.
            note: .text(amount: .estimated)
        )
    }

    // MARK: - The raw-weight annotation

    /// Which row of the table a name should be looked up against.
    ///
    /// **Read off the name, because the name is where it was written down.**
    /// `EstimateContract.rawWeightConvention` asks a model that priced a raw
    /// weight to end that item's name with the amount in brackets — `Rice (raw
    /// 300 g)` — and `FoodTableGrounding` prices exactly those items against
    /// the raw row. So a name carrying the annotation is a name that was
    /// priced raw, and one without it was priced as eaten. That saves storing
    /// a preparation alongside the weight to say a thing the row already says.
    private static func preparation(of name: String) -> FoodPreparation {
        let opening = EstimateContract.rawAnnotationOpening
        return name.range(of: opening, options: .caseInsensitive) == nil ? .prepared : .raw
    }

    /// The name with its raw annotation restated at the new weight, or
    /// unchanged where it has none.
    ///
    /// **A row that says `Rice (raw 300 g)` and weighs 450 g is a row lying to
    /// the user in the one place the amount is written in words.** The bracket
    /// is the wire convention's, not the interface's — it is a shape
    /// `EstimateContract` asked a model to write and `FoodTableGrounding`
    /// reads back — so restating it belongs here beside them and not in a
    /// string catalog.
    ///
    /// Everything before the bracket is the model's own text and is untouched.
    private static func renaming(_ name: String, toRawAmount grams: Int) -> String {
        let opening = EstimateContract.rawAnnotationOpening
        guard let range = name.range(of: opening, options: .caseInsensitive) else {
            return name
        }
        return "\(name[..<range.lowerBound])\(opening)\(grams) g)"
    }

    // MARK: - Arithmetic

    /// Books one row's move into the three running figures.
    ///
    /// **The energy always counts; which macro pot it counts into is the whole
    /// of the decision.** Where the row has a real macro figure on both sides
    /// of the change, the difference between them is exact and goes to
    /// `macroDelta`. Where it does not — a name no CIQUAL row covers, a row
    /// whose table entry has a macro gap of its own — nothing on the device
    /// knows what that row is made of, and its energy goes to
    /// `unpricedKilocalories` so the meal's macros can follow it by proportion
    /// instead of standing still.
    ///
    /// A row that had no macros and now has them belongs in neither: the
    /// meal's standing macro figure was estimated over a meal in which this
    /// row's contribution was never stated, so adding the new figure to it
    /// would count the row twice — and its energy has moved by a real
    /// difference the pricing pass did not invent, which is what `macroDelta`
    /// is for. Its share is therefore taken as the energy it moved, exactly as
    /// for a row that is still figureless.
    private static func account(
        _ previous: RecognisedItem,
        _ current: RecognisedItem,
        _ kilocalorieDelta: inout Int,
        _ macroDelta: inout MacroTotals,
        _ unpricedKilocalories: inout Int
    ) {
        let energy = current.kilocalories - previous.kilocalories
        kilocalorieDelta += energy

        guard let before = previous.macros, let after = current.macros else {
            unpricedKilocalories += energy
            return
        }
        macroDelta = macroDelta + (after - before)
    }

    /// Rounded to a whole number, never negative, and never a trap.
    ///
    /// `PortionCalculator.whole` says the same thing for the table's own
    /// arithmetic and is private to it. The inputs here are a stored figure
    /// and a ratio of two model-written weights, which is the same class of
    /// number: `Int(1e300)` is not an overflow, it is a crash nothing above
    /// this line can catch.
    private static func whole(_ value: Double) -> Int {
        guard let rounded = Int(exactly: value.rounded()) else {
            return 0
        }
        return max(0, rounded)
    }
}

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
/// in.** Names and weights are the whole of it. See `MealChatContract` for why
/// that is the architecture rather than a simplification.
nonisolated struct MealAdjustmentIntent: Sendable, Equatable {

    /// The model's own sentence, already bounded. `nil` where it wrote nothing
    /// usable, which is not an error and not rare.
    var reply: String?

    var changes: [Change]
    var additions: [Addition]

    init(reply: String? = nil, changes: [Change] = [], additions: [Addition] = []) {
        self.reply = reply
        self.changes = changes
        self.additions = additions
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

/// One turn's answer: what the model said, and what — if anything — actually
/// moved.
///
/// **The two are separate on purpose, and `meal` being `nil` is the case worth
/// building for.** A model that could not map "it was quite oily" onto a
/// weight, a model that named an item number the list does not have, a model
/// that asked for a food the table cannot price — all of them produce a
/// sentence and no change. The screen has to be able to say that, rather than
/// showing a reply over figures that did not move and letting the user infer
/// that they did.
nonisolated struct MealAdjustmentOutcome: Sendable, Equatable {

    var reply: String?
    var meal: AdjustedMeal?

    init(reply: String?, meal: AdjustedMeal?) {
        self.reply = reply
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
/// **The meal's own figures move by the rows' deltas, and the two halves are
/// not symmetric.** Kilocalories always move: every row has a real prior
/// kilocalorie figure to take a delta against, and the meal's total has
/// already been reconciled against those figures by `FoodTableGrounding`,
/// which adjusts it by exactly this kind of delta. Macros move only for a row
/// that has a real macro figure on *both* sides of the change — which after a
/// grounding pass is any grounded row, and which is precisely the case
/// `FoodTableGrounding` says it does not have: the model is asked for macros
/// once, for the whole meal, so at *estimate* time a row has no prior macro
/// figure to subtract. Here it does. A row without one contributes nothing to
/// the macro total, and the meal's macro figure keeps that row's share exactly
/// as the model estimated it, because nothing on the device knows what that
/// share was.
///
/// The one-item rule that file needs is not needed here and is not written:
/// with one grounded item the meal's macros already *are* that item's, so
/// `meal + (new − old)` is `new` by arithmetic rather than by special case.
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
        var items = meal.items
        var kilocalorieDelta = 0
        var macroDelta = MacroTotals.zero
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

            kilocalorieDelta += repriced.kilocalories - previous.kilocalories
            macroDelta = macroDelta + macroChange(from: previous, to: repriced)
            items[index] = repriced
            moved = true
        }

        for addition in intent.additions {
            guard let item = added(addition, in: table) else {
                continue
            }
            kilocalorieDelta += item.kilocalories
            if let macros = item.macros {
                macroDelta = macroDelta + macros
            }
            items.append(item)
            moved = true
        }

        guard moved else {
            return nil
        }

        return AdjustedMeal(
            // The floor is `PortionCalculator`'s own: a negative meal is not a
            // value that reaches the day's ring, however a delta got there.
            kilocalories: max(0, meal.kilocalories + kilocalorieDelta),
            macros: MacroTotals(
                protein: max(0, meal.macros.protein + macroDelta.protein),
                carbs: max(0, meal.macros.carbs + macroDelta.carbs),
                fat: max(0, meal.macros.fat + macroDelta.fat)
            ),
            items: items
        )
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

    /// The macro delta between two states of one row, and `zero` where there
    /// is no honest one.
    ///
    /// Both sides have to be real figures. A row that had no macros and now
    /// has them has not *changed* by anything the meal's own macro total knows
    /// about — that total was estimated over a meal in which this row's
    /// contribution was never stated — so adding the new figure to it would be
    /// counting the row twice. A row that had them and lost them is the same
    /// story backwards.
    private static func macroChange(from previous: RecognisedItem, to current: RecognisedItem) -> MacroTotals {
        guard let before = previous.macros, let after = current.macros else {
            return .zero
        }
        return MacroTotals(
            protein: after.protein - before.protein,
            carbs: after.carbs - before.carbs,
            fat: after.fat - before.fat
        )
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

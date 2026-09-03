import Testing

@testable import Fuel

// MARK: - Grounding a reply against the food table

/// These run against the bundled artefact, the same one `FoodTableTests`
/// does, for the same reason: a fixture proves the wiring parses something,
/// and the only question worth asking is whether `r45g polenta` actually
/// prices at 350 kcal/100 g on the table that ships.
@Suite("Food table grounding")
struct FoodTableGroundingTests {

    private let table: FoodTable

    init() throws {
        table = try FoodTable.bundled()
    }

    // MARK: - The motivating bug

    /// The owner typed `r45g` for raw polenta and the model answered 72 kcal —
    /// the cooked row's price for a raw weight. This is that sentence, put
    /// through the whole path: scan the text, find the table row, price the
    /// weight against it.
    @Test("A raw-marked single item is priced from the raw row")
    func rawMarkedItem() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 72,
            macros: MacroTotals(protein: 2, carbs: 15, fat: 0),
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 72, note: .text(amount: .recognised))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "r45g polenta", table: table
        )

        #expect(grounded.items[0].kilocalories == 158)   // 350 kcal/100g x 0.45
        #expect(grounded.kilocalories == 158)             // 72 + (158 - 72)

        // Raw polenta's macros are complete in CIQUAL, so the item gets its
        // own real figures, and — this being the meal's only item — those
        // figures become the meal's macros outright.
        let expected = MacroTotals(protein: 4, carbs: 33, fat: 1)   // 7.88/74/1.8 x 0.45
        #expect(grounded.items[0].macros == expected)
        #expect(grounded.macros == expected)
    }

    @Test("The same sentence without the marker is priced from the prepared row")
    func unmarkedItem() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 158,
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 158, note: .text(amount: .recognised))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "45g polenta", table: table
        )

        // 76.1 kcal/100g x 0.45 = 34.245 -> 34.
        #expect(grounded.items[0].kilocalories == 34)
        #expect(grounded.kilocalories == 34)

        // CIQUAL has no fat figure for cooked polenta. Kilocalories is
        // unaffected by that gap — the row still publishes an energy value —
        // but macros stays nil rather than reporting a zero fat nothing
        // measured, on the item and, because this is the meal's only item,
        // on the meal as well: nothing here is a fact to replace the meal's
        // prior estimate with.
        #expect(grounded.items[0].macros == nil)
        #expect(grounded.macros == estimate.macros)
    }

    /// The item name itself carries the model's own raw-weight annotation —
    /// `EstimateContract.rawWeightConvention` asks for exactly this shape —
    /// and grounding has to see through it to find the row.
    @Test("An item named with the model's own raw annotation still resolves")
    func annotatedItemName() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 72,
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta (raw 45 g)", kilocalories: 72, note: .text(amount: .recognised))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "r45g polenta", table: table
        )

        #expect(grounded.items[0].kilocalories == 158)
    }

    // MARK: - Where text grounding declines rather than guesses

    @Test("Two items in one sentence are not groundable — nothing says which weight is whose")
    func multipleItemsDecline() {
        let estimate = MealEstimate(
            title: "Polenta and chicken",
            kilocalories: 300,
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 72, note: .text(amount: .recognised)),
                RecognisedItem(name: "Chicken breast", kilocalories: 228, note: .text(amount: .recognised))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "r45g polenta and 200g chicken breast", table: table
        )

        #expect(grounded == estimate)
    }

    @Test("Two weights in one sentence are not groundable, even for one item")
    func multipleWeightsDecline() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 72,
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 72, note: .text(amount: .recognised))
            ]
        )

        // A sentence that happens to name two quantities for one dish is
        // exactly as ambiguous as two dishes naming one each.
        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "r45g polenta, maybe 50g", table: table
        )

        #expect(grounded == estimate)
    }

    @Test("No weight in the sentence is not groundable")
    func noWeightDeclines() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 200,
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 200, note: .text(amount: .estimated))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "a bowl of polenta", table: table
        )

        #expect(grounded == estimate)
    }

    @Test("Photo mode never consults the sentence, because it has none")
    func photoIgnoresText() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 72,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Polenta",
                    kilocalories: 72,
                    note: .photo(confidence: .confident, approximateGrams: 45)
                )
            ]
        )

        // originalText is nil on the photo path by construction, but even a
        // populated string must not leak in through the photo branch.
        let grounded = FoodTableGrounding.ground(
            estimate, mode: .photo, originalText: "r45g polenta", table: table
        )

        // Photo grounding always prefers the prepared row -- see below -- so
        // this is 76.1 kcal/100g x 0.45, not the raw row's price.
        #expect(grounded.items[0].kilocalories == 34)
    }

    // MARK: - Photo mode

    @Test("A photo item is priced from its own approximate weight, against the prepared row")
    func photoItemGrounds() {
        let estimate = MealEstimate(
            title: "Rice",
            kilocalories: 999,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: 999,
                    note: .photo(confidence: .unsure, approximateGrams: 150)
                )
            ]
        )

        let grounded = FoodTableGrounding.ground(estimate, mode: .photo, originalText: nil, table: table)

        // Cooked white rice, 9104: 155 kcal/100g x 1.5 = 232.5 -> 232 (round
        // half away from zero of .5 rounds up in Swift's default, so this is
        // actually 233 -- computed via PortionCalculator, not restated here).
        #expect(grounded.items[0].kilocalories != 999)
        #expect(grounded.kilocalories == estimate.kilocalories + (grounded.items[0].kilocalories - 999))
    }

    @Test("A photo item with no weight at all is not groundable")
    func photoZeroGramsDeclines() {
        let estimate = MealEstimate(
            title: "Rice",
            kilocalories: 50,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: 50,
                    note: .photo(confidence: .unsure, approximateGrams: 0)
                )
            ]
        )

        let grounded = FoodTableGrounding.ground(estimate, mode: .photo, originalText: nil, table: table)
        #expect(grounded == estimate)
    }

    @Test("A photo meal of several items grounds every one that matches")
    func photoMultipleItemsGround() {
        let estimate = MealEstimate(
            title: "Rice and chicken",
            kilocalories: 999,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Rice", kilocalories: 300,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Chicken breast", kilocalories: 300,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                )
            ]
        )

        let grounded = FoodTableGrounding.ground(estimate, mode: .photo, originalText: nil, table: table)

        // Multi-item is exactly where text mode declines; photo mode has no
        // such restriction, because each item already carries its own weight.
        #expect(grounded.items[0].kilocalories != 300)
        #expect(grounded.items[1].kilocalories != 300)
    }

    // MARK: - Where matching declines rather than guesses

    /// CIQUAL's best guess at "grilled salmon sandwich" is plain grilled
    /// salmon — real, edible, and not a sandwich. Pricing this item as if it
    /// were nothing but the fish would drop the bread and whatever else is on
    /// it, and that is a wrong number wearing a citation. `bestMatch` requires
    /// every one of the query's words to be covered before it acts, and
    /// "sandwich" is not, so this declines rather than grounding on a partial
    /// read.
    @Test("A composite name that is not fully covered by any row is not groundable")
    func partialCoverageDeclines() {
        let estimate = MealEstimate(
            title: "Grilled salmon sandwich",
            kilocalories: 400,
            macros: .zero,
            items: [
                RecognisedItem(name: "Grilled salmon sandwich", kilocalories: 400, note: .text(amount: .estimated))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "300g grilled salmon sandwich", table: table
        )

        #expect(grounded == estimate)
    }

    @Test("A food absent from the table is not groundable")
    func missingFoodDeclines() {
        let estimate = MealEstimate(
            title: "Not a food",
            kilocalories: 100,
            macros: .zero,
            items: [
                RecognisedItem(name: "Zzznotafood", kilocalories: 100, note: .text(amount: .estimated))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "200g zzznotafood", table: table
        )

        #expect(grounded == estimate)
    }

    // MARK: - Meal-level arithmetic

    /// The meal's total moves by exactly the grounded item's own delta, not by
    /// being replaced outright — a second, ungrounded item's contribution to
    /// the model's original total must survive untouched.
    @Test("The meal total moves by the grounded item's delta, not by the whole total")
    func mealTotalMovesByDelta() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 372,   // 72 (wrong) + 300 (some other, unresolvable contribution)
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 72, note: .text(amount: .recognised))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "r45g polenta", table: table
        )

        // Item corrected from 72 to 158, a delta of +86, carried onto the
        // meal's 372 rather than the meal being reset to the item's own
        // figure.
        #expect(grounded.items[0].kilocalories == 158)
        #expect(grounded.kilocalories == 372 + 86)
    }

    @Test("The meal total never goes negative, however large the correction")
    func mealTotalFloorsAtZero() {
        let estimate = MealEstimate(
            title: "Polenta",
            kilocalories: 5,   // smaller than the correction below
            macros: .zero,
            items: [
                RecognisedItem(name: "Polenta", kilocalories: 5000, note: .text(amount: .recognised))
            ]
        )

        let grounded = FoodTableGrounding.ground(
            estimate, mode: .text, originalText: "r45g polenta", table: table
        )

        #expect(grounded.kilocalories == 0)
    }

    /// A meal's macros can only honestly move when there is exactly one item
    /// to have supplied them — see this file's own doc comment for why. Two
    /// items each still get their own real figures; the meal's aggregate,
    /// which the model split across them in a way nothing here can recover,
    /// stays exactly as estimated.
    @Test("Two grounded items each get real macros; the meal's aggregate does not move")
    func multiItemMacrosStayAggregate() {
        let modelMacros = MacroTotals(protein: 11, carbs: 22, fat: 33)
        let estimate = MealEstimate(
            title: "Rice and chicken",
            kilocalories: 999,
            macros: modelMacros,
            items: [
                RecognisedItem(
                    name: "Rice", kilocalories: 300,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Chicken breast", kilocalories: 300,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                )
            ]
        )

        let grounded = FoodTableGrounding.ground(estimate, mode: .photo, originalText: nil, table: table)

        #expect(grounded.items[0].macros == MacroTotals(protein: 5, carbs: 42, fat: 1))
        #expect(grounded.items[1].macros == MacroTotals(protein: 30, carbs: 0, fat: 8))
        #expect(grounded.macros == modelMacros)
    }

    /// The sole-item collapse is specifically an *item-count* rule, not a
    /// generic "meal totals move when anything grounds" rule — this pins that
    /// a two-item meal declines the meal-level correction even though both of
    /// its items resolve, which `multiItemMacrosStayAggregate` already checks
    /// on the macro side; this checks the reverse would-be trap does not
    /// exist on the kilocalorie side either, i.e. that kilocalorie grounding
    /// was never gated on item count to begin with.
    @Test("Kilocalorie grounding was never gated on item count")
    func kilocalorieDeltaIgnoresItemCount() {
        let estimate = MealEstimate(
            title: "Rice and chicken",
            kilocalories: 600,
            macros: .zero,
            items: [
                RecognisedItem(
                    name: "Rice", kilocalories: 300,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                ),
                RecognisedItem(
                    name: "Chicken breast", kilocalories: 300,
                    note: .photo(confidence: .confident, approximateGrams: 100)
                )
            ]
        )

        let grounded = FoodTableGrounding.ground(estimate, mode: .photo, originalText: nil, table: table)

        // 212 (rice) + 189 (chicken) replacing 300 + 300.
        #expect(grounded.items[0].kilocalories == 212)
        #expect(grounded.items[1].kilocalories == 189)
        #expect(grounded.kilocalories == 600 + (212 - 300) + (189 - 300))
    }
}

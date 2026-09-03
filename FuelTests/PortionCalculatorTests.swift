import Testing

@testable import Fuel

// MARK: - Portion arithmetic

/// Every figure the user reads comes out of `PortionCalculator`. Nothing here
/// needs a table, a bundle, a store or a simulator: the input is four `Double`s
/// and a weight, which is the whole reason the arithmetic lives in
/// `Fuel/Nutrition/` rather than beside the code that fetched it.
@Suite("Portion arithmetic")
struct PortionCalculatorTests {

    /// Raw polenta, as CIQUAL publishes it (`alim_code` 9614).
    private let rawPolenta = Per100Grams(kilocalories: 350, protein: 7.88, carbs: 74, fat: 1.8)

    /// The same food cooked (9615). CIQUAL has no fat figure for it, which is
    /// why `fat` is `nil` and not `0`.
    private let cookedPolenta = Per100Grams(kilocalories: 76.1, protein: 1.38, carbs: 16.9, fat: nil)

    @Test("A row times a weight is that row times that weight")
    func rowTimesWeight() {
        let portion = PortionCalculator.portion(of: rawPolenta, grams: 45)

        // 350 x 0.45 = 157.5, which rounds away from zero.
        #expect(portion.kilocalories == 158)
        #expect(portion.macros.protein == 4)      // 7.88 x 0.45 = 3.546
        #expect(portion.macros.carbs == 33)       // 74 x 0.45 = 33.3
        #expect(portion.macros.fat == 1)          // 1.8 x 0.45 = 0.81
        #expect(portion.incompleteMacros == false)
    }

    /// The number that started all of this. `r45g` of polenta came back from
    /// the model as 72 kcal, which is the cooked row's answer to a raw weight.
    /// The two rows are three hundred per cent apart and this test is the
    /// distance between them.
    @Test("Raw and cooked polenta at the same weight are not close")
    func rawAndCookedDiffer() {
        let raw = PortionCalculator.portion(of: rawPolenta, grams: 45)
        let cooked = PortionCalculator.portion(of: cookedPolenta, grams: 45)

        #expect(raw.kilocalories == 158)
        #expect(cooked.kilocalories == 34)
    }

    @Test("A weight of zero is nothing at all")
    func zeroWeight() {
        #expect(PortionCalculator.portion(of: rawPolenta, grams: 0) == .zero)
    }

    @Test("A fractional weight is not truncated on the way in")
    func fractionalWeight() {
        // 350 x 0.125 = 43.75 -> 44. Truncating the weight to 12 g would give
        // 43, and truncating it to 13 would give 46.
        let portion = PortionCalculator.portion(of: rawPolenta, grams: 12.5)
        #expect(portion.kilocalories == 44)
    }

    @Test("A large weight is scaled, not saturated")
    func largeWeight() {
        let portion = PortionCalculator.portion(of: rawPolenta, grams: 2500)
        #expect(portion.kilocalories == 8750)
        #expect(portion.macros.carbs == 1850)
    }

    /// A macro the table is silent about contributes nothing to the sum and
    /// says so. Without the flag the zero below is indistinguishable from a
    /// measured zero, and a day's fat total would be quietly short.
    @Test("A missing macro is a gap, not a zero")
    func missingMacro() {
        let portion = PortionCalculator.portion(of: cookedPolenta, grams: 200)

        #expect(portion.kilocalories == 152)
        #expect(portion.macros.protein == 3)
        #expect(portion.macros.fat == 0)
        #expect(portion.incompleteMacros)
    }

    @Test("A weight that is not a number buys nothing")
    func nonsenseWeight() {
        #expect(PortionCalculator.portion(of: rawPolenta, grams: -50) == .zero)
        #expect(PortionCalculator.portion(of: rawPolenta, grams: .nan) == .zero)
        #expect(PortionCalculator.portion(of: rawPolenta, grams: .infinity) == .zero)
    }

    // MARK: - Where the rounding happens

    /// The meal total is the sum of the **rounded** item figures, not the
    /// rounded sum of the exact ones, so the rows on the result screen add up
    /// to the total printed under them.
    ///
    /// This test is the pin on that decision and is written so that moving the
    /// rounding to the total would fail it. Three items of 33.3 kcal each:
    /// rounded per item they are 33 + 33 + 33 = 99, and the exact sum is 99.9,
    /// which would round to 100.
    @Test("A meal totals its rounded items, so the rows add up to the total")
    func totalsRoundedItems() {
        let food = Per100Grams(kilocalories: 111, protein: 1, carbs: 1, fat: 1)
        let items = (0..<3).map { _ in PortionCalculator.portion(of: food, grams: 30) }

        #expect(items.allSatisfy { $0.kilocalories == 33 })
        #expect(PortionCalculator.meal(of: items).kilocalories == 99)
    }

    @Test("A meal is incomplete if any one item is")
    func incompleteSpreads() {
        let complete = PortionCalculator.portion(of: rawPolenta, grams: 100)
        let incomplete = PortionCalculator.portion(of: cookedPolenta, grams: 100)

        #expect(PortionCalculator.meal(of: [complete, complete]).incompleteMacros == false)
        #expect(PortionCalculator.meal(of: [complete, incomplete]).incompleteMacros)
    }

    @Test("A meal of nothing is zero rather than a crash")
    func emptyMeal() {
        #expect(PortionCalculator.meal(of: []) == .zero)
    }
}

import Foundation
import Testing

@testable import Fuel

// MARK: - The meal from its rows

@Suite("Meal arithmetic")
struct MealArithmeticTests {

    // MARK: - Summing the rows

    @Test("Rows that all carry a figure make the meal's macros between them")
    func everyRowPresent() {
        let rows: [MacroTotals?] = [
            MacroTotals(protein: 5, carbs: 42, fat: 1),
            MacroTotals(protein: 30, carbs: 0, fat: 8),
            MacroTotals(protein: 2, carbs: 11, fat: 3)
        ]

        #expect(MealArithmetic.macros(ofRows: rows) == MacroTotals(protein: 37, carbs: 53, fat: 12))
    }

    /// The refusal is the whole point of the type. Summing what is there would
    /// answer `5/42/1` for a meal whose second row nobody has a figure for, and
    /// that figure would be drawn as the meal's.
    @Test("One row without a figure means the rows cannot answer for the meal")
    func oneRowAbsent() {
        let rows: [MacroTotals?] = [MacroTotals(protein: 5, carbs: 42, fat: 1), nil]

        #expect(MealArithmetic.macros(ofRows: rows) == nil)
    }

    @Test("A row missing at the front is refused as surely as one at the back")
    func absentRowAnywhere() {
        #expect(MealArithmetic.macros(ofRows: [nil, MacroTotals(protein: 5, carbs: 42, fat: 1)]) == nil)
    }

    /// A meal priced without being split is a usable answer, and its macros are
    /// the model's meal-wide figure. Zero would replace that answer with a claim
    /// that the food had no macronutrients in it.
    @Test("A meal with no breakdown is not a meal with no macros")
    func noRowsAtAll() {
        #expect(MealArithmetic.macros(ofRows: []) == nil)
    }

    @Test("One row is the meal, which is what the old sole-item rule said the long way round")
    func oneRowIsTheMeal() {
        let only = MacroTotals(protein: 4, carbs: 33, fat: 1)

        #expect(MealArithmetic.macros(ofRows: [only]) == only)
    }

    // MARK: - Moving a standing figure

    @Test("A meal's energy moves by the delta and floors at zero")
    func energyFloor() {
        #expect(MealArithmetic.kilocalories(372, movedBy: 86) == 458)
        #expect(MealArithmetic.kilocalories(300, movedBy: -120) == 180)
        #expect(MealArithmetic.kilocalories(5, movedBy: -5000) == 0)
    }

    /// Each macro floors on its own. A delta that takes protein below zero must
    /// not be allowed to take the carbohydrate figure with it.
    @Test("Each macro floors on its own")
    func macroFloor() {
        let moved = MealArithmetic.macros(
            MacroTotals(protein: 10, carbs: 40, fat: 5),
            movedBy: MacroTotals(protein: -30, carbs: 12, fat: -1)
        )

        #expect(moved == MacroTotals(protein: 0, carbs: 52, fat: 4))
    }

    // MARK: - The energy rule

    /// **Energy is the table's published figure and is never re-derived from
    /// the three macros**, and this is the assertion that goes red if someone
    /// decides otherwise.
    ///
    /// Boiled lentils are the case that makes the difference visible: CIQUAL
    /// publishes 125 kcal/100 g under EU 1169/2011, which counts the fibre;
    /// `4·P + 4·C + 9·F` over the same row's macros comes to 110. A portion
    /// priced by `PortionCalculator` must carry the first number, and the
    /// second must not be what the arithmetic quietly produces instead.
    @Test("An item's energy is the table's figure, not the Atwater sum of its macros")
    func itemEnergyIsTheTablesFigure() {
        let lentils = Per100Grams(kilocalories: 125, protein: 10.1, carbs: 16.2, fat: 0.57)

        let portion = PortionCalculator.portion(of: lentils, grams: 150)

        // 125 x 1.5, rounded once at the end.
        #expect(portion.kilocalories == 188)

        let atwater = 4 * portion.macros.protein + 4 * portion.macros.carbs + 9 * portion.macros.fat
        #expect(atwater == 165)
        #expect(portion.kilocalories != atwater)
    }

    /// The same rule one level up, and then one more. The gap does not cancel
    /// out over a meal or a day — it accumulates, in the same direction, which
    /// is exactly why it is written down rather than left to be rediscovered.
    @Test("A day of five meals sums to its meals, and its meals to their rows")
    func aDayOfFiveMeals() {
        // Five meals of real CIQUAL rows, priced at plausible weights. The
        // per-100 g figures are the bundled table's; the arithmetic under test
        // is everything after them.
        let meals: [[(Per100Grams, Double)]] = [
            [
                (Per100Grams(kilocalories: 69.1, protein: 2.54, carbs: 10.3, fat: 1.52), 250),   // oat flakes
                (Per100Grams(kilocalories: 32.7, protein: 3.37, carbs: 4.70, fat: 0.08), 200),   // skimmed milk
                (Per100Grams(kilocalories: 54.0, protein: 0.25, carbs: 11.6, fat: 0.25), 150)    // apple
            ],
            [
                (Per100Grams(kilocalories: 615.0, protein: 18.8, carbs: 9.51, fat: 51.3), 30)    // almonds
            ],
            [
                (Per100Grams(kilocalories: 155.0, protein: 3.15, carbs: 33.2, fat: 0.70), 200),  // white rice
                (Per100Grams(kilocalories: 141.0, protein: 30.1, carbs: 0.0, fat: 2.00), 150),   // chicken breast
                (Per100Grams(kilocalories: 471.0, protein: 0.70, carbs: 3.03, fat: 50.5), 15)    // olive oil dressing
            ],
            [
                (Per100Grams(kilocalories: 107.0, protein: 0.25, carbs: 25.8, fat: 0.23), 100),  // apple compote
                (Per100Grams(kilocalories: 50.1, protein: 3.83, carbs: 4.26, fat: 1.68), 125)    // plain yogurt
            ],
            [
                (Per100Grams(kilocalories: 125.0, protein: 10.1, carbs: 16.2, fat: 0.57), 150),  // boiled lentils
                (Per100Grams(kilocalories: 234.0, protein: 8.66, carbs: 41.2, fat: 1.70), 60)    // wholemeal bread
            ]
        ]

        var entries: [NutritionEntry] = []
        for (index, rows) in meals.enumerated() {
            let portions = rows.map { PortionCalculator.portion(of: $0.0, grams: $0.1) }

            // The meal is its rows, in both figures — the rule under test.
            let mealMacros = MealArithmetic.macros(ofRows: portions.map(\.macros))
            let mealKilocalories = portions.reduce(0) { $0 + $1.kilocalories }
            guard let mealMacros else {
                Issue.record("every row here carries a complete figure")
                return
            }
            #expect(mealMacros == portions.reduce(into: MacroTotals.zero) { $0 += $1.macros })

            entries.append(
                NutritionEntry(
                    title: "Meal \(index + 1)",
                    kilocalories: mealKilocalories,
                    macros: mealMacros,
                    loggedAt: .now,
                    source: .photo,
                    label: .snack
                )
            )
        }

        let day = DailyNutrition.totals(of: entries)

        // The day is the sum of the meals, which are the sums of their rows.
        #expect(day.kilocalories == entries.reduce(0) { $0 + $1.kilocalories })
        #expect(day.macros == entries.reduce(into: MacroTotals.zero) { $0 += $1.macros })

        // And the figure the chosen rule costs, stated as a number so that a
        // change of rule cannot pass unnoticed: the day's energy is the table's,
        // and sits above the Atwater sum of the day's own macros rather than
        // equal to it. 1,595 against 1,499 — the fibre, mostly.
        let atwater = 4 * day.macros.protein + 4 * day.macros.carbs + 9 * day.macros.fat
        #expect(day.kilocalories == 1595)
        #expect(atwater == 1499)
        #expect(day.kilocalories > atwater)
    }
}

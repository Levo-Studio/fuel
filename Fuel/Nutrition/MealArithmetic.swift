import Foundation

// MARK: - How a meal's own figures are worked out

/// The one rule for turning a meal's rows into the meal's own four numbers, and
/// the one place a standing figure is moved by a delta.
///
/// Everything that draws a total reaches it through here: the grounding pass
/// that prices an estimate, the chat that re-prices a row, the result screen
/// that throws one out, and — by summing the entries those produce —
/// `DailyNutrition`. A second copy of any of this in a feature file is how the
/// day's ring and the macro bars under it came to describe different meals.
///
/// # Energy is the table's figure and is never derived from the macros
///
/// A food's energy could be printed two ways, and only one of them is honest
/// here.
///
/// The general Atwater factors — 4 kcal per gram of protein, 4 per gram of
/// carbohydrate, 9 per gram of fat, 7 per gram of alcohol — are a *conversion*,
/// not the definition of a food's energy. CIQUAL publishes its own energy
/// column, computed under EU Regulation 1169/2011, which is the calculation a
/// packaged food's label uses; `tools/reduce-ciqual.py` takes that column
/// (constituent 328) for the stated reason that a tracker disagreeing with the
/// packet is a tracker nobody trusts. That regulation counts fibre at 2 kcal/g,
/// polyols at 2.4, organic acids at 3 and alcohol at 7 — four things Fuel does
/// not store, because the design draws three macros.
///
/// So a CIQUAL row's energy is **not** `4·protein + 4·carbs + 9·fat`, and the
/// gap is the data rather than a bug. Measured over the 3,089 bundled rows that
/// carry all four figures and a non-zero energy, the Atwater sum sits a median
/// of 1.2 % and a mean of 3.4 % below the published energy, and disagrees with
/// it by 5.6 % in either direction on average — **the disagreement is not all
/// one way**, and in 617 of those rows, one in five, the Atwater sum comes out
/// *above* the published figure. What is one-way is the accumulation over a
/// realistic day, because the foods a day is mostly made of are the ones with
/// fibre in them: five ordinary meals came out 1,595 kcal by the table against
/// 1,499 kcal by the sum, 96 kcal and 6.0 % apart. High-fibre foods are where
/// it opens up — wheat bran is 270 kcal against 188 for 100 g, boiled lentils
/// 188 against 165 for a 150 g portion — and spirits are where deriving would
/// stop working altogether: gin and vodka carry no protein, no carbohydrate and
/// no fat at all, so a derived figure would print 0 kcal for a measure of
/// spirits.
///
/// **Energy is therefore the published figure, and the cost is stated rather
/// than hidden: a user who multiplies out the macro bars will land a few per
/// cent under the ring.** The alternative fails harder than it gains. Deriving
/// would under-report the great majority of meals and every plausible day of
/// them, would report nothing at all for the 192 bundled rows that have a macro
/// gap — CIQUAL has no fat figure for cooked polenta, and 168 of those 192 are
/// a missing fat figure — and would zero every row the table never matched,
/// because a row the model estimated has kilocalories and no macros at all.
/// That last case is not an edge: grounding needs a weight and full token
/// coverage against a row, so a multi-item typed meal is never grounded at all
/// and any row whose name the table does not cover falls through on any path.
/// Deriving is therefore not a costlier rule; it is an unbuildable one.
///
/// # A meal is its rows whenever its rows can answer for it
///
/// What *does* have to hold, and now does, is that the figures over a
/// breakdown describe the breakdown under them. `macros(ofRows:)` is that rule
/// and `PortionCalculator.portion(of:grams:)` already stated its other half:
/// the meal is the sum of the rows' already-rounded figures, so a user adding
/// up the screen gets the total on it.
nonisolated enum MealArithmetic {

    // MARK: - The meal from its rows

    /// The macros of a meal made of these rows, or `nil` where the rows cannot
    /// answer for the whole meal.
    ///
    /// **All of them or none of them, and the middle is what the `nil` refuses
    /// to guess at.** A row's `macros` is a CIQUAL figure or it is absent;
    /// there is no third state. Summing a list in which one row is absent would
    /// quietly drop that row's protein, carbohydrate and fat from a total drawn
    /// as though it covered the meal — the same mistake
    /// `PortionNutrition.incompleteMacros` exists to stop one row from making,
    /// said at the level above it.
    ///
    /// An empty list is `nil` for the same reason and not zero: a meal priced
    /// without being split is a usable answer, and its macros are the model's
    /// meal-wide figure. Zero would replace that answer with a claim that the
    /// food had no macronutrients in it.
    ///
    /// The caller supplies what stands when this answers `nil`. That is always
    /// the figure the meal already had, never a figure invented to fill the
    /// gap.
    static func macros(ofRows rows: [MacroTotals?]) -> MacroTotals? {
        guard !rows.isEmpty else {
            return nil
        }
        var total = MacroTotals.zero
        for row in rows {
            guard let row else {
                return nil
            }
            total += row
        }
        return total
    }

    // MARK: - Moving a standing figure

    /// A meal's energy after its rows moved by `delta`.
    ///
    /// **The floor is `PortionCalculator`'s own**: a negative meal is not a
    /// value that reaches the day's ring, however a delta got there. The three
    /// callers used to carry a copy of that floor and a copy of the sentence
    /// explaining it.
    static func kilocalories(_ standing: Int, movedBy delta: Int) -> Int {
        max(0, standing + delta)
    }

    /// A meal's macros after its rows moved by `delta`, floored the same way.
    ///
    /// Only reached where `macros(ofRows:)` declined — a meal in which some row
    /// has no macro figure of its own. Then the meal's standing figure is the
    /// model's meal-wide estimate, and the only honest correction to it is the
    /// difference on a row that had a real figure on both sides of the change.
    static func macros(_ standing: MacroTotals, movedBy delta: MacroTotals) -> MacroTotals {
        MacroTotals(
            protein: max(0, standing.protein + delta.protein),
            carbs: max(0, standing.carbs + delta.carbs),
            fat: max(0, standing.fat + delta.fat)
        )
    }
}

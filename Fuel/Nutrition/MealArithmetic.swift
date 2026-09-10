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

    /// A meal's macros after its rows moved by `delta`, and after the rows that
    /// have no macro figure of their own gained or lost
    /// `unpricedKilocalories` of energy out of a meal that stood at
    /// `standingKilocalories`. Floored the same way.
    ///
    /// Only reached where `macros(ofRows:)` declined — a meal in which some row
    /// has no macro figure of its own. Then the meal's standing figure is the
    /// model's meal-wide estimate, and it is corrected from two directions.
    ///
    /// **`delta` is the exact half**: the difference on a row that had a real
    /// figure on both sides of the change. Nothing is assumed about it.
    ///
    /// **The energy share is the half that stops a meal freezing, and it is an
    /// apportioning rather than a measurement.** A row CIQUAL cannot cover —
    /// `Chicken curry with rice` matches no published row, and the table asks
    /// for full coverage or nothing — has no macro figure before a change and
    /// none after it, so `delta` has nothing to say about it. Leaving it at
    /// that was the bug the owner reported: halving such a meal halved its
    /// calories and left its protein, carbohydrate and fat at the values of a
    /// portion no longer on the plate, on the same screen, describing the same
    /// food. Standing still is not the neutral answer there. It is a figure
    /// that is known to be wrong, drawn beside one that has just been corrected.
    ///
    /// So a row nothing can price moves the meal's macros in the proportion it
    /// moved the meal's energy. That is the one thing the standing figure does
    /// say about such a row: it is a whole-meal estimate over a meal of
    /// `standingKilocalories`, and a row that is now half again as much food is
    /// not described by it any more. A meal made entirely of rows the table
    /// cannot cover therefore scales exactly — double the amount, double both
    /// numbers — which is the answer a user would arrive at with a pencil.
    ///
    /// **The cost, stated rather than hidden**: where a meal holds priced rows
    /// as well, the share is taken against the whole meal's energy, so an
    /// unpriced row is credited with a little of what the priced rows already
    /// account for. It is an estimate applied to an estimate, and it is bounded
    /// by the size of the row that moved. The alternative was a number known to
    /// describe a portion nobody ate.
    ///
    /// A meal with no standing energy has no share to take, and the delta is
    /// then all there is.
    static func macros(
        _ standing: MacroTotals,
        movedBy delta: MacroTotals,
        andByTheEnergyShareOf unpricedKilocalories: Int,
        ofAMealOf standingKilocalories: Int
    ) -> MacroTotals {
        MacroTotals(
            protein: moved(standing.protein, by: delta.protein, andBy: unpricedKilocalories, of: standingKilocalories),
            carbs: moved(standing.carbs, by: delta.carbs, andBy: unpricedKilocalories, of: standingKilocalories),
            fat: moved(standing.fat, by: delta.fat, andBy: unpricedKilocalories, of: standingKilocalories)
        )
    }

    /// One macro, moved by an exact difference and by its share of an energy
    /// change nothing could price.
    private static func moved(
        _ standing: Int,
        by delta: Int,
        andBy unpricedKilocalories: Int,
        of standingKilocalories: Int
    ) -> Int {
        guard standingKilocalories > 0, unpricedKilocalories != 0 else {
            return max(0, standing + delta)
        }
        let share = Double(standing) * Double(unpricedKilocalories) / Double(standingKilocalories)
        return max(0, standing + delta + whole(share))
    }

    /// Rounded to a whole number, and never a trap.
    ///
    /// **Signed, unlike `PortionCalculator`'s own `whole`**: a row that got
    /// smaller carries a negative share, and flooring it here would drop
    /// exactly the direction this rule exists to follow. The floor is applied
    /// once, to the figure the share lands on.
    private static func whole(_ value: Double) -> Int {
        guard let rounded = Int(exactly: value.rounded()) else {
            return 0
        }
        return rounded
    }
}

import Foundation

// MARK: - Per 100 g

/// What a food composition table says about a food, per 100 g.
///
/// The four numbers Fuel needs and no others. They are `Double` because that is
/// how a table publishes them — 76.1 kcal, 7.88 g of protein — and the rounding
/// to the whole numbers the design draws happens once, in `portion(of:grams:)`,
/// at the end.
///
/// **The three macros are optional and the energy is not.** A table with no
/// energy figure for a food has nothing to offer a calorie tracker, so that
/// case is filtered out before a value of this type exists. A missing *macro*
/// is a different statement: CIQUAL genuinely has no fat figure for cooked
/// polenta, and `nil` says so. Reading it as zero would print a number nobody
/// measured, and the table's terms of reuse forbid presenting an altered value
/// as theirs.
nonisolated struct Per100Grams: Hashable, Sendable {

    var kilocalories: Double
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    init(kilocalories: Double, protein: Double?, carbs: Double?, fat: Double?) {
        self.kilocalories = kilocalories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }
}

// MARK: - A portion

/// One item's figures, worked out from a table row and a weight.
///
/// `incompleteMacros` is not decoration. It is the flag that keeps a `0` in
/// `macros` from being read as a measurement: the item's fat is zero in the sum
/// because the table is silent, not because the food has none, and anything
/// totalling a day needs to be able to tell those apart.
nonisolated struct PortionNutrition: Hashable, Sendable {

    var kilocalories: Int
    var macros: MacroTotals
    var incompleteMacros: Bool

    static let zero = PortionNutrition(kilocalories: 0, macros: .zero, incompleteMacros: false)
}

// MARK: - The arithmetic

/// `per100g × grams / 100`, and nothing else.
///
/// **This is the whole reason the table exists.** The model names the food and
/// says how much of it there was; every number the user reads is produced
/// here, from a published figure and a weight, by multiplication. A language
/// model is not asked to multiply, because it is not reliably able to and
/// because a wrong product would arrive looking exactly like a right one.
///
/// Pure, `nonisolated`, and free of any table, bundle or store — the type it
/// works on is four `Double`s. That is what lets every case below be a test
/// that runs in microseconds without a simulator and without a network.
nonisolated enum PortionCalculator {

    /// Where the rounding happens, and it happens exactly once.
    ///
    /// Four values are derived from one weight, and each is rounded on its own
    /// to the whole numbers the design draws. That is a decision with a
    /// visible consequence, so it is stated rather than left to fall out:
    ///
    /// - **Per item, per value, at the end.** The multiplication runs in
    ///   `Double` and the result is rounded once. Rounding the per-100 g figure
    ///   first, or rounding a running subtotal, compounds an error that has no
    ///   need to exist.
    /// - **A meal's total is the sum of its items' rounded figures**, not the
    ///   rounded sum of their exact ones. The design prints the item rows and
    ///   the total on the same screen, and a user who adds up the rows must
    ///   get the total. Being right against a calculator matters less than
    ///   being consistent with the screen. The cost is real and bounded: with
    ///   `n` items the total can sit up to `n/2` kcal away from the exact
    ///   figure, which for any meal anyone eats is a rounding error smaller
    ///   than the estimate of the weight it came from.
    /// - **Half away from zero**, which is `rounded()`'s default and what a
    ///   person means by rounding. All the inputs here are non-negative, so
    ///   the tie case is 0.5 going up.
    ///
    /// A negative or non-finite weight yields zero rather than a negative
    /// meal. Weights arrive from a model's reply, so "impossible" is not a
    /// guarantee available here.
    static func portion(of per100g: Per100Grams, grams: Double) -> PortionNutrition {
        guard grams.isFinite, grams > 0, per100g.kilocalories.isFinite else {
            return .zero
        }

        let fraction = grams / 100

        let protein = scaled(per100g.protein, by: fraction)
        let carbs = scaled(per100g.carbs, by: fraction)
        let fat = scaled(per100g.fat, by: fraction)

        return PortionNutrition(
            kilocalories: whole(per100g.kilocalories * fraction),
            macros: MacroTotals(
                protein: protein ?? 0,
                carbs: carbs ?? 0,
                fat: fat ?? 0
            ),
            incompleteMacros: protein == nil || carbs == nil || fat == nil
        )
    }

    /// The totals of a meal made of `portions`.
    ///
    /// A plain sum of the already-rounded parts — see above for why that is the
    /// order and not the other one. The meal counts as incomplete if any single
    /// item does, because a macro total with one item's contribution silently
    /// missing is exactly as wrong as the item was.
    static func meal(of portions: [PortionNutrition]) -> PortionNutrition {
        portions.reduce(into: PortionNutrition.zero) { total, portion in
            total.kilocalories += portion.kilocalories
            total.macros += portion.macros
            total.incompleteMacros = total.incompleteMacros || portion.incompleteMacros
        }
    }

    // MARK: - Scaling

    private static func scaled(_ value: Double?, by fraction: Double) -> Int? {
        guard let value, value.isFinite else {
            return nil
        }
        return whole(value * fraction)
    }

    /// Rounded to a whole number, never negative, and never a trap.
    ///
    /// `Int(exactly:)` rather than `Int(_:)`: the inputs are a table value and
    /// a weight a model wrote, and `Int(1e300)` is not an overflow, it is a
    /// crash that nothing above this line can catch.
    private static func whole(_ value: Double) -> Int {
        guard let rounded = Int(exactly: value.rounded()) else {
            return 0
        }
        return max(0, rounded)
    }
}

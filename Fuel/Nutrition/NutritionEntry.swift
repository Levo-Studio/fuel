import Foundation

// MARK: - Macros

/// Protein, carbohydrate and fat in whole grams.
///
/// Whole grams, not a floating-point value: every figure the design draws is a
/// whole number (`118/160`, `48 g`), and integers sum without drift, so a day's
/// total is the same number however the entries are ordered.
nonisolated struct MacroTotals: Hashable, Sendable {

    var protein: Int
    var carbs: Int
    var fat: Int

    static let zero = MacroTotals(protein: 0, carbs: 0, fat: 0)

    static func + (lhs: MacroTotals, rhs: MacroTotals) -> MacroTotals {
        MacroTotals(
            protein: lhs.protein + rhs.protein,
            carbs: lhs.carbs + rhs.carbs,
            fat: lhs.fat + rhs.fat
        )
    }

    static func += (lhs: inout MacroTotals, rhs: MacroTotals) {
        lhs = lhs + rhs
    }
}

// MARK: - Daily totals

/// What a day adds up to. Count-only mode shows exactly this and nothing else.
nonisolated struct DailyTotals: Hashable, Sendable {

    var kilocalories: Int
    var macros: MacroTotals

    static let zero = DailyTotals(kilocalories: 0, macros: .zero)
}

// MARK: - Hand-off

/// The value the nutrition core works on.
///
/// This is the boundary type: `Core/Data` builds one of these out of a
/// `FoodEntry`, and nothing from SwiftData travels deeper. That is what lets
/// the whole core be tested in milliseconds without a `ModelContainer` and
/// without a simulator.
nonisolated struct NutritionEntry: Hashable, Sendable, Identifiable {

    let id: UUID
    var title: String
    var kilocalories: Int
    var macros: MacroTotals
    var loggedAt: Date
    var source: EntrySource
    var label: MealLabel

    /// `true` once the user has picked the label by hand on the result screen.
    ///
    /// Re-deriving the day's labels must leave such an entry alone: the
    /// correction is the user's, and quietly overwriting it would make the
    /// control on the result screen a lie.
    var isLabelUserSet: Bool

    init(
        id: UUID = UUID(),
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        loggedAt: Date,
        source: EntrySource,
        label: MealLabel,
        isLabelUserSet: Bool = false
    ) {
        self.id = id
        self.title = title
        self.kilocalories = kilocalories
        self.macros = macros
        self.loggedAt = loggedAt
        self.source = source
        self.label = label
        self.isLabelUserSet = isLabelUserSet
    }

    func withLabel(_ label: MealLabel, userSet: Bool) -> NutritionEntry {
        var copy = self
        copy.label = label
        copy.isLabelUserSet = userSet
        return copy
    }
}

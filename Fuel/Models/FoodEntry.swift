import Foundation
import SwiftData

// MARK: - Food entry

/// One logged meal.
///
/// The store is local and stays local: no `ModelConfiguration` here names a
/// CloudKit container, no property is marked for cloud encryption, and nothing
/// in Fuel syncs. There is no account to sync to, and that is the product
/// rather than a feature that has not happened yet.
@Model
final class FoodEntry {

    /// A stable identity that survives the boundary into the nutrition core.
    ///
    /// `persistentModelID` cannot: it is a SwiftData type, and nothing from
    /// SwiftData travels deeper than the hand-off value.
    var entryID: UUID

    var title: String
    var kilocalories: Int

    var proteinGrams: Int
    var carbGrams: Int
    var fatGrams: Int

    var loggedAt: Date

    /// Source and label are persisted as their raw strings rather than as
    /// enums, so the stored shape stays readable and stable when a case is
    /// added or renamed in code.
    var sourceRawValue: String
    var labelRawValue: String

    /// Set once the user picks the label by hand on the result screen. From
    /// then on the label is theirs and re-deriving the day leaves it alone.
    var isLabelUserSet: Bool

    /// Drawn as the ☆ / ★ control on the result screen; the Recent list reads
    /// it back.
    var isFavourite: Bool

    /// The breakdown shown under `Recognised` / `Broken down`. Empty for an
    /// entry logged straight from the Recent list, which repeats a meal rather
    /// than analysing one.
    var items: [RecognisedItem]

    init(
        entryID: UUID = UUID(),
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        loggedAt: Date,
        source: EntrySource,
        label: MealLabel = .snack,
        isLabelUserSet: Bool = false,
        isFavourite: Bool = false,
        items: [RecognisedItem] = []
    ) {
        self.entryID = entryID
        self.title = title
        self.kilocalories = kilocalories
        self.proteinGrams = macros.protein
        self.carbGrams = macros.carbs
        self.fatGrams = macros.fat
        self.loggedAt = loggedAt
        self.sourceRawValue = source.rawValue
        self.labelRawValue = label.rawValue
        self.isLabelUserSet = isLabelUserSet
        self.isFavourite = isFavourite
        self.items = items
    }

    // MARK: - Typed accessors

    var macros: MacroTotals {
        get { MacroTotals(protein: proteinGrams, carbs: carbGrams, fat: fatGrams) }
        set {
            proteinGrams = newValue.protein
            carbGrams = newValue.carbs
            fatGrams = newValue.fat
        }
    }

    /// A row written by an older build with a case this one no longer knows
    /// still has to appear in the list, so an unreadable value falls back
    /// rather than crashing.
    var source: EntrySource {
        get { EntrySource(rawValue: sourceRawValue) ?? .text }
        set { sourceRawValue = newValue.rawValue }
    }

    /// Snack is the safe fallback for the same reason, and the same reason it
    /// is what a new entry starts as before the day is derived: it is the
    /// label that claims nothing.
    var label: MealLabel {
        get { MealLabel(rawValue: labelRawValue) ?? .snack }
        set { labelRawValue = newValue.rawValue }
    }
}

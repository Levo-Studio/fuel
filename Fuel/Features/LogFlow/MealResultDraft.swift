import Foundation

// MARK: - Result draft

/// The estimate as the result screen holds it: still editable, not yet an
/// entry.
///
/// A value rather than a `FoodEntry`, because screen 14 is a decision. The
/// user can move the calories, cycle the label and mark it a favourite, and
/// none of that should exist in the database until they tap `Add` — a scan
/// they walk away from must leave nothing behind.
nonisolated struct PhotoResultDraft: Equatable, Sendable {

    /// Model-written text. Already capped at 120 characters at the parse
    /// boundary in `Core/AI`, so it is not capped again here — but it is not
    /// assumed short either, and it is rendered as plain text with no markup
    /// path.
    var title: String

    var kilocalories: Int
    var macros: MacroTotals
    var items: [RecognisedItem]

    /// What the meal-label rule gives this moment, until the user says
    /// otherwise.
    var label: MealLabel

    /// `true` once the pill has been tapped. It decides whether the commit
    /// writes the label back over the store's own derivation.
    var isLabelUserSet: Bool

    var isFavourite: Bool
}

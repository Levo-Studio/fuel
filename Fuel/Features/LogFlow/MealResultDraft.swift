import Foundation

// MARK: - Result draft

/// The estimate as the result screen holds it: still editable, not yet an
/// entry.
///
/// A value rather than a `FoodEntry`, because screens 14 and 15 are a
/// decision. The user can move the calories, cycle the label and mark it a
/// favourite, and none of that should exist in the database until they tap
/// `Add` — an estimate they walk away from must leave nothing behind.
///
/// One type for both AI log modes. A photo and a typed sentence produce the
/// same thing — a priced meal with a breakdown — and the only difference the
/// two result screens draw is what sits above the label pill, which is the
/// screen's business and not the draft's.
nonisolated struct MealResultDraft: Equatable, Sendable {

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

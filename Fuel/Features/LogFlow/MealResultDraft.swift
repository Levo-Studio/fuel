import Foundation

// MARK: - Result draft

/// The estimate as the result screen holds it: still editable, not yet an
/// entry.
///
/// A value rather than a `FoodEntry`, because screens 14 and 15 are a
/// decision. The user can cycle the label, mark it a favourite and rewrite the
/// list of items it was made from, and none of that should exist in the
/// database until they tap `Add` — an estimate they walk away from must leave
/// nothing behind.
///
/// One type for both AI log modes. A photo and a typed sentence produce the
/// same thing — a priced meal with a breakdown — and the only difference the
/// two result screens draw is what sits above the label pill, which is the
/// screen's business and not the draft's.
///
/// **It says nothing about where it came from.** There is no photo here, no
/// typed sentence and no flag for whether it has been written down yet: a draft
/// is a meal and its breakdown, and the caller holds the rest. That is what
/// lets one screen serve a scan, a typed entry and — when it is built — a meal
/// that is already in the store.
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

    /// Items whose text is the user's rather than the model's — one they
    /// retyped, or one they added that the model never saw.
    ///
    /// It is here so the screen can leave their calorie column empty. A figure
    /// beside a line the model has not read yet would be a number Fuel made up:
    /// nothing on the device re-prices a meal, and the only thing that can is
    /// the next estimate.
    var userWrittenItems: Set<RecognisedItem.ID> = []

    /// Whether the item list has been changed since the estimate produced it.
    ///
    /// The footer reads this: while it is `true` the primary action is
    /// `Re-analyse` rather than the caller's own, because the figures above the
    /// list belong to a breakdown that no longer exists. It lives on the draft
    /// and not on a log model so that every caller of the result screen —
    /// including one that starts from a stored entry — gets the same rule
    /// without a second copy of it.
    var hasItemEdits: Bool = false

    // MARK: - Editing the breakdown

    /// Throws out a line the model got wrong.
    ///
    /// **Nothing is recalculated.** The total and the macros above the list are
    /// what the model said about the meal it was shown, and subtracting a row's
    /// calories from them would invent the macro split that no row carries. The
    /// figures stand, wrong, until the user asks for them again — which is
    /// exactly what `hasItemEdits` puts in front of them.
    mutating func removeItem(_ id: RecognisedItem.ID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        userWrittenItems.remove(id)
        hasItemEdits = true
    }

    /// Rewrites a line as the user's own words — `Polenta r50g` for something
    /// the photo could not weigh.
    ///
    /// An empty field changes nothing. Emptying a row is what the remove
    /// control is for, and a blank line in the list would be a line the next
    /// estimate is asked about and cannot read.
    mutating func editItem(_ id: RecognisedItem.ID, to text: String) {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].name != written else { return }

        items[index].name = written
        userWrittenItems.insert(id)
        hasItemEdits = true
    }

    /// Adds a line the model missed, at the end of the list where the `Add
    /// item` row sits.
    ///
    /// The new row keeps `kilocalories` at zero and its note at `unknown`, and
    /// neither is drawn: an item the user wrote has no confidence, no weight
    /// the model estimated and no price yet. Both are replaced wholesale by the
    /// re-analysis, which is the only way this draft can be logged.
    mutating func addItem(_ text: String) {
        let written = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !written.isEmpty else { return }

        let item = RecognisedItem(name: written, kilocalories: 0, note: .unknown)
        items.append(item)
        userWrittenItems.insert(item.id)
        hasItemEdits = true
    }

    /// Whether the figure beside a row is the model's to show.
    func isPriced(_ id: RecognisedItem.ID) -> Bool {
        !userWrittenItems.contains(id)
    }

    /// The edited list as one line of text, which is what a re-analysis is
    /// asked about.
    ///
    /// Names only. The calories beside them are the previous estimate's, and
    /// handing the model its own last answer back would invite it to agree with
    /// itself rather than to price what the user has written.
    var itemSentence: String {
        items.map(\.name).joined(separator: ", ")
    }
}

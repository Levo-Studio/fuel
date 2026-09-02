import Foundation

// MARK: - Estimate

/// What the model came back with: one meal, priced.
///
/// A plain `Sendable` value, deliberately shaped so it drops straight into
/// `FuelStore.log(title:kilocalories:macros:loggedAt:source:items:)` without a
/// translation step. `MacroTotals` and `RecognisedItem` are the types the store
/// and the nutrition core already speak; re-declaring parallel ones here would
/// mean a mapping layer that exists only to be kept in sync.
///
/// It carries no date and no meal label. The time an entry is logged at is the
/// store's to decide, and the label is the meal-label rule's — a value the
/// network produced must not get a vote on either.
nonisolated struct MealEstimate: Sendable, Equatable {

    /// The meal's name, as the model read or saw it. Drawn as the result
    /// screen's heading.
    var title: String

    var kilocalories: Int

    var macros: MacroTotals

    /// The breakdown under `Recognised` (photo) or `Broken down` (text).
    /// May be empty: a model that priced a meal without splitting it is a
    /// usable answer, and the result screen simply has no rows to draw.
    var items: [RecognisedItem]

    init(
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        items: [RecognisedItem]
    ) {
        self.title = title
        self.kilocalories = kilocalories
        self.macros = macros
        self.items = items
    }
}

// MARK: - Log mode

/// Which of the two AI log modes a request belongs to.
///
/// It is not `EntrySource`: that type has a third case, `recent`, which never
/// reaches a provider — logging from the Recent list repeats a stored meal and
/// makes no request at all. Modelling the two modes separately keeps a case
/// that cannot happen here out of every `switch` in this folder.
///
/// The mode decides the shape of a `RecognisedItem.Note`, which is why it is
/// carried into parsing: a photo yields a confidence and an approximate
/// weight, typed text yields only whether an amount was given.
nonisolated enum AILogMode: Sendable, Equatable {

    case photo
    case text

    var entrySource: EntrySource {
        switch self {
        case .photo: .photo
        case .text: .text
        }
    }
}

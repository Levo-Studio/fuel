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

    /// One or two sentences on what is good about the meal or what it is light
    /// on, in the model's own words. Drawn under the macros.
    ///
    /// **Optional end to end, and the absent case is the ordinary one.** A
    /// model that left the field out, wrote nothing but whitespace, or ran past
    /// the bound `EstimateContract.boundedAdvice` holds it to arrives here as
    /// `nil`, and every screen that draws a meal has to be as correct without
    /// it as with it — nothing about the estimate depends on it and nothing
    /// waits for it.
    ///
    /// It is model-written text like `title` and an item's `name`, and carries
    /// the same rules: bounded at the parse boundary, rendered as plain text
    /// with no markup path, and never a provider's words about a failure. See
    /// `EstimateContract.boundedAdvice`.
    var advice: String?

    /// The breakdown under `Recognised` (photo) or `Broken down` (text).
    /// May be empty: a model that priced a meal without splitting it is a
    /// usable answer, and the result screen simply has no rows to draw.
    var items: [RecognisedItem]

    init(
        title: String,
        kilocalories: Int,
        macros: MacroTotals,
        advice: String? = nil,
        items: [RecognisedItem]
    ) {
        self.title = title
        self.kilocalories = kilocalories
        self.macros = macros
        self.advice = advice
        self.items = items
    }

    // MARK: - How sure the model is

    /// How sure the model is of this estimate, as a whole percent, or `nil`
    /// where no row of it carries an answer.
    ///
    /// A view onto `items` rather than a field of its own, because the model is
    /// asked per row and never once for the meal — the same shape the export
    /// already draws, which puts a confidence under each recognised item and
    /// none over the total. Deriving the meal's figure from the rows is what
    /// makes it survive a re-analysis: the rows that change bring their own
    /// answers with them and the average follows, where a single meal-wide
    /// figure would go stale the moment one line was corrected.
    ///
    /// `EstimateConfidence.percent(of:)` holds the rule. This is only the one
    /// place that hands it a meal's rows, so the two log models and
    /// `MealResultDraft` cannot each derive it slightly differently.
    var confidencePercent: Int? {
        EstimateConfidence.percent(of: items.map(\.confidence))
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

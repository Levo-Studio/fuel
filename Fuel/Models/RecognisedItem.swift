import Foundation

// MARK: - Recognised item

/// One line of the breakdown on the result screen: what the model thinks it
/// saw or read, and what it costs.
///
/// The list is heavier than the entry itself and lighter than a table: items
/// are never queried on their own, never shared between entries, never edited
/// apart from their entry and never outlive it. A `Codable` value stored on the
/// entry says exactly that, and spares the schema a second model, a
/// relationship, an inverse and a cascade rule that could only ever be
/// `.cascade`.
///
/// The cost, stated plainly: an item is an opaque blob to the database. No
/// `#Predicate` can ever filter or sort on one, so anything that wants to
/// search line items would have to load every entry and sift in memory. Fuel
/// has no screen that does — the Recent list repeats whole meals, not
/// ingredients — and there is no search screen to add one.
nonisolated struct RecognisedItem: Codable, Hashable, Sendable, Identifiable {

    var id: UUID
    var name: String
    var kilocalories: Int

    /// How much of this food the figures beside it were worked out for, in
    /// grams.
    ///
    /// **A field of its own rather than a number read back out of `note`, and
    /// the difference is what makes a quantity changeable.** The weight was
    /// always known — the model is asked for it, and `FoodTableGrounding`
    /// multiplies a CIQUAL row by it to price the row — but until this existed
    /// the only place it was written down was the sentence under a photo item's
    /// name, in a `case` that a typed item does not even have. Anything wanting
    /// to say "one and a half times this" had to pattern-match a display note
    /// for a number, and had nothing at all to match on for a text meal.
    ///
    /// `nil` where nothing ever supplied one: a text item whose model left the
    /// field out, a row the user typed themselves, a meal repeated from the
    /// Recent list, and any entry stored before this property existed. Read it
    /// through `weightInGrams`, which also finds an older photo row's weight in
    /// the note that used to be its only home.
    var grams: Int?

    /// This item's own protein, carbohydrate and fat, when they are known.
    ///
    /// **`nil` far more often than not, and that is not a gap to fill.** The
    /// model is never asked for a per-item macro breakdown — `EstimateContract`
    /// itemises `kilocalories` but only `protein_g`/`carbs_g`/`fat_g` at the
    /// meal level — so this is empty for every item until something else
    /// supplies it. Today, the one supplier is `FoodTableGrounding`: a food
    /// resolved to a CIQUAL row with complete macro data gets its real
    /// protein, carbs and fat here, priced from that row and the item's own
    /// weight. A resolved row with a gap in its own data — CIQUAL has no fat
    /// figure for cooked polenta — leaves this `nil` rather than writing a
    /// zero no measurement backs; see `PortionNutrition.incompleteMacros`.
    ///
    /// **This doubles as the only marker this type needs.** A non-`nil` value
    /// is a CIQUAL figure and is shown silently; a `nil` value is the model's
    /// own estimate and whatever `note` already says about it —
    /// `.unsure`/`.estimated` where the model said so — still applies exactly
    /// as before. There is deliberately no second flag: `kilocalories` and
    /// `macros` are always resolved together, from the same table row and the
    /// same weight, so a reader never has to reconcile a kilocalorie figure
    /// that came from one place with a macro figure that came from another.
    var macros: MacroTotals?

    var note: Note

    init(
        id: UUID = UUID(),
        name: String,
        kilocalories: Int,
        grams: Int? = nil,
        macros: MacroTotals? = nil,
        note: Note
    ) {
        self.id = id
        self.name = name
        self.kilocalories = kilocalories
        self.grams = grams
        self.macros = macros
        self.note = note
    }

    // MARK: - Weight

    /// The weight this row's figures were worked out for, from wherever it was
    /// written down.
    ///
    /// **One reader for two homes, so nothing has to know there were ever
    /// two.** `grams` is the first-class field and wins. Behind it is the place
    /// a photo item's weight lived before that field existed — the
    /// `approximateGrams` inside `.photo` — which is what an entry stored by an
    /// older build still carries, and what every in-memory item built from a
    /// note alone carries too.
    ///
    /// A zero in the note is not a weight. `EstimateContract` floors that field
    /// at zero rather than dropping it, so a photo row whose weight could not
    /// be read arrives here with a `0` that no measurement backs; pricing a
    /// portion against it would be pricing nothing. `grams` is never written as
    /// zero — see `setWeight(_:)`.
    var weightInGrams: Int? {
        if let grams {
            return grams
        }
        if case .photo(_, let approximateGrams) = note, approximateGrams > 0 {
            return approximateGrams
        }
        return nil
    }

    /// Records a new weight for this row.
    ///
    /// **Both homes are written, so the older one can never go stale.** A photo
    /// row keeps a copy of its weight inside `note`, and a row whose quantity
    /// has been changed since it was scanned would otherwise hold two different
    /// numbers with only the reading order deciding which is true.
    ///
    /// The confidence in that note is left exactly as the model set it: it says
    /// how sure the model was about *what it was looking at*, which a change of
    /// amount does not answer either way.
    ///
    /// **Refuses anything that is not a real amount.** Zero and below is not a
    /// smaller portion, it is the absence of one, and a row that is not part of
    /// the meal is a row the user removes rather than one this quietly empties.
    mutating func setWeight(_ newGrams: Int) {
        guard newGrams > 0 else { return }
        grams = newGrams
        if case .photo(let confidence, _) = note {
            note = .photo(confidence: confidence, approximateGrams: newGrams)
        }
    }

    // MARK: - The note under the name

    /// The second line of a row, and the reason it is stored structured rather
    /// than as a finished sentence: the words belong in the string catalog, and
    /// the two log modes say different things.
    ///
    /// A photo gives a confidence and an approximate weight — the model is
    /// guessing at both what it is and how much of it there is. Typed text gives
    /// neither: an amount was either written down or it was not.
    ///
    /// The coding is written out rather than synthesised, for the same reason
    /// `FoodEntry` keeps its source and its label as raw strings: a row written
    /// by another build must still open. A shape this build does not know reads
    /// as `unknown` and the row survives; the synthesised decoder would throw
    /// and take the whole entry's item list with it.
    enum Note: Codable, Hashable, Sendable {

        case photo(confidence: Confidence, approximateGrams: Int)
        case text(amount: AmountOrigin)

        /// A note this build cannot read. The row still lists its name and its
        /// calories, which is the part the user is looking at.
        case unknown

        private enum Kind: String, Codable {
            case photo
            case text
        }

        private enum CodingKeys: String, CodingKey {
            case kind
            case confidence
            case approximateGrams
            case amount
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try? container.decode(Kind.self, forKey: .kind) {
            case .photo:
                self = .photo(
                    // An unreadable confidence reads as the less certain of the
                    // two: overstating what the model was sure of is the worse
                    // of the two failures.
                    confidence: (try? container.decode(Confidence.self, forKey: .confidence)) ?? .unsure,
                    approximateGrams: (try? container.decode(Int.self, forKey: .approximateGrams)) ?? 0
                )
            case .text:
                self = .text(
                    amount: (try? container.decode(AmountOrigin.self, forKey: .amount)) ?? .estimated
                )
            case nil:
                self = .unknown
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .photo(let confidence, let approximateGrams):
                try container.encode(Kind.photo, forKey: .kind)
                try container.encode(confidence, forKey: .confidence)
                try container.encode(approximateGrams, forKey: .approximateGrams)
            case .text(let amount):
                try container.encode(Kind.text, forKey: .kind)
                try container.encode(amount, forKey: .amount)
            case .unknown:
                // Nothing to write down, and writing a kind back would claim
                // knowledge this build does not have.
                break
            }
        }
    }

    enum Confidence: String, Codable, Hashable, Sendable {

        case confident
        case unsure
    }

    enum AmountOrigin: String, Codable, Hashable, Sendable {

        case recognised
        case estimated
    }
}

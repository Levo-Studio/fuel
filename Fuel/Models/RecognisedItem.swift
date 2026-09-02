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
nonisolated struct RecognisedItem: Codable, Hashable, Sendable, Identifiable {

    var id: UUID
    var name: String
    var kilocalories: Int
    var note: Note

    init(id: UUID = UUID(), name: String, kilocalories: Int, note: Note) {
        self.id = id
        self.name = name
        self.kilocalories = kilocalories
        self.note = note
    }

    // MARK: - The note under the name

    /// The second line of a row, and the reason it is stored structured rather
    /// than as a finished sentence: the words belong in the string catalog, and
    /// the two log modes say different things.
    ///
    /// A photo gives a confidence and an approximate weight — the model is
    /// guessing at both what it is and how much of it there is. Typed text gives
    /// neither: an amount was either written down or it was not.
    enum Note: Codable, Hashable, Sendable {

        case photo(confidence: Confidence, approximateGrams: Int)
        case text(amount: AmountOrigin)
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

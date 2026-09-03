import Foundation

// MARK: - Notation

/// The shorthand a typed meal may use to say a weight was measured before
/// cooking: **a leading `r` on a weight means the amount was weighed raw or
/// dry. A bare weight means as eaten.**
///
/// `300 g rice` is a plate of rice; `r300 g rice` is the dry rice that went
/// into it, and the two are not close — dry rice is roughly three times the
/// calories per gram of cooked. Nothing in a photo can carry that distinction
/// and no model can guess it reliably, so the user states it, and the estimate
/// contract teaches both providers to read it.
///
/// This type does not interpret the notation and does not convert anything.
/// It answers one question — *does this sentence use the shorthand at all* —
/// and the answer decides whether `EstimateContract` spends the tokens to
/// explain the convention. That is the whole reason it is a scanner on the
/// device rather than a sentence permanently glued to every request: a meal
/// that never mentions a raw weight should not be handed a paragraph about
/// raw weights, because the surest way to get a model to invent a raw-versus-
/// cooked difference is to talk to it about one when the user did not.
///
/// **The two errors are not symmetrical, and the rule below is loose on
/// purpose.** A false positive costs a few dozen tokens of instruction on a
/// request that had no marker in it, and the instruction itself is written so
/// that a model finding no marker does nothing differently. A false negative
/// costs the user the feature silently — they typed `r300 g`, the model was
/// never told what the `r` meant, and the estimate is wrong by a factor of
/// three with nothing on screen to say so. Where a shape is arguable, it is
/// accepted.
nonisolated enum RawWeightNotation {

    // MARK: - Units

    /// The units a raw marker may be attached to.
    ///
    /// **Mass only, and that is the rule rather than an omission.** Raw versus
    /// cooked is a question about weight: the same dry rice weighed before and
    /// after cooking is two different numbers, whereas two eggs are two eggs
    /// and a raw one is not a different count. Millilitres are left out for the
    /// same reason — a volume of a liquid does not change by being warmed —
    /// and so is a bare number, which would make `r2 eggs` a raw weight and it
    /// is not one.
    ///
    /// Both the abbreviation and the written word, because a person types
    /// either. Ordered longest first so `r50 grams` matches `grams` rather than
    /// stopping at the `g`.
    private static let units = [
        "kilograms", "kilogram", "ounces", "pounds", "grams", "ounce",
        "pound", "gram", "lbs", "kg", "oz", "lb", "g"
    ]

    // MARK: - Reading

    /// Whether `text` uses the raw-weight shorthand anywhere in it.
    ///
    /// The marker is recognised **immediately before a quantity**, not as a
    /// word standing on its own. `r` is a letter that turns up everywhere; a
    /// rule that fired on any lone `r` would fire on half the shopping lists
    /// anyone has ever typed. Tied to a number and a unit it is a shape nobody
    /// writes by accident.
    static func isUsed(in text: String) -> Bool {
        let characters = Array(text)

        for index in characters.indices where isMarker(characters, at: index) {
            if quantityFollows(characters, from: index + 1) {
                return true
            }
        }

        return false
    }

    // MARK: - Scanning

    /// Whether the character at `index` is the marker itself.
    ///
    /// Case is ignored — a sentence typed with autocapitalisation on begins
    /// `R50 g` and means the same thing — and the marker must start a word, so
    /// the `r` in `burger 200 g` or `Sugar 5 g` is not one.
    private static func isMarker(_ characters: [Character], at index: Int) -> Bool {
        let character = characters[index]
        guard character == "r" || character == "R" else {
            return false
        }
        return isBoundary(characters, at: index - 1)
    }

    /// Whether a number and a mass unit follow, starting at `index`.
    ///
    /// A single space is allowed on either side of the number, so `r50g`,
    /// `r 50g`, `r50 g` and `r 50 g` are all the same amount written by
    /// somebody with a different habit. More than one space is not: at that
    /// point the `r` and the number are two separate things on the line rather
    /// than one amount.
    private static func quantityFollows(_ characters: [Character], from index: Int) -> Bool {
        var cursor = skippingSpace(characters, from: index)

        guard cursor < characters.count, isDigit(characters[cursor]) else {
            return false
        }
        while cursor < characters.count, isDigit(characters[cursor]) {
            cursor += 1
        }

        // A fraction, written either way round: `r1.5 kg` and `r1,5 kg` are
        // both typed, and the separator is a keyboard habit rather than a
        // different value. A separator with no digit after it ends the match
        // rather than falling back to the digits before it — `r1.kg` is a
        // typo, and reading half of it would be guessing at which half.
        if cursor < characters.count, characters[cursor] == "." || characters[cursor] == "," {
            let afterSeparator = cursor + 1
            guard afterSeparator < characters.count, isDigit(characters[afterSeparator]) else {
                return false
            }
            cursor = afterSeparator
            while cursor < characters.count, isDigit(characters[cursor]) {
                cursor += 1
            }
        }

        return unitFollows(characters, from: skippingSpace(characters, from: cursor))
    }

    /// Whether one of `units` sits at `index` and ends there.
    ///
    /// The unit has to end at a boundary, so `r50 grammar` is not fifty grams
    /// of anything.
    private static func unitFollows(_ characters: [Character], from index: Int) -> Bool {
        guard index < characters.count else {
            return false
        }

        for unit in units {
            let end = index + unit.count
            guard end <= characters.count else {
                continue
            }
            guard String(characters[index..<end]).lowercased() == unit else {
                continue
            }
            if isBoundary(characters, at: end) {
                return true
            }
        }

        return false
    }

    /// `index` advanced past one space, if there is one there.
    private static func skippingSpace(_ characters: [Character], from index: Int) -> Int {
        guard index < characters.count, characters[index] == " " else {
            return index
        }
        return index + 1
    }

    /// Whether the position at `index` ends a word.
    ///
    /// Off either end of the string counts, so a sentence that is nothing but
    /// `r50g` has a boundary at both ends of it.
    private static func isBoundary(_ characters: [Character], at index: Int) -> Bool {
        guard index >= 0, index < characters.count else {
            return true
        }
        let character = characters[index]
        return !character.isLetter && !character.isNumber
    }

    /// Whether `character` is one of the ten digits.
    ///
    /// ASCII only. `Character.isNumber` is true of `½` and of the digits of
    /// every script, and neither is a weight anybody typed into this app on an
    /// English keyboard; accepting them would mean `String(...)` conversions
    /// downstream that have no defined answer.
    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }
}

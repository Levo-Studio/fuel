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
    /// is not one. Volume stays out even where a dry measure would be
    /// meaningful, as a cup of rice is: `ml`, `l`, `cup`, `tbsp` and their
    /// neighbours would widen the same rule into liquids, which have no raw
    /// form at all. A count in any language — `st`, `Stück`, `slices` — is out
    /// for the reason the eggs are.
    ///
    /// A word that merely starts like a unit is still not one. `r300gg` and
    /// `r50 grammar` match nothing here, because a unit has to end where the
    /// word does.
    ///
    /// **The list is not English-only, because the sentence is not.** The
    /// contract's own comment says the user's typed meal may be in any
    /// language, and a table of English abbreviations quietly excludes the
    /// people most likely to weigh their rice: `r300 Gramm Reis` and the very
    /// common German short form `r300gr` both used to fall straight through.
    /// The asymmetry that governs the rest of this type governs the table too
    /// — an unfamiliar word here costs the user a threefold error with nothing
    /// on screen to say so, and an over-familiar one costs a few dozen tokens
    /// of instruction that then does nothing.
    ///
    /// So: the abbreviation and the written word, in English, German and
    /// French, plus `Pfund`, which a German speaker uses for 500 g the way an
    /// English speaker uses a pound.
    ///
    /// **Order does not matter, and still does not now that the loop returns a
    /// value rather than a yes.** An earlier version claimed the array was
    /// sorted longest first so `r50 grams` would not stop at the `g`, and that
    /// was never what did it — `unit(_:from:)` requires the unit to end at a
    /// word boundary, so `g` followed by `r` is rejected on its own and the
    /// loop simply carries on to `grams`. `r1 kilogram` is a kilogram for the
    /// same reason and not a `kilo`. The array is alphabetical because a list
    /// somebody has to add a word to is easier to read that way.
    ///
    /// Each entry carries what one of it weighs in grams.
    ///
    /// The gram figure was added when the scanner stopped answering only "is
    /// there a marker" and started answering "how much" — see `weights(in:)`.
    /// A pound is the international avoirdupois pound and an ounce is a
    /// sixteenth of it; `Pfund` is the German half-kilo, which is what a German
    /// speaker means by the word and is not a pound. `Unze` is grouped with
    /// the ounce rather than with the historical German Unze of 31.25 g,
    /// because nobody weighing their dinner in 2026 means the older one.
    private static let units: [(name: String, grams: Double)] = [
        ("g", 1), ("gr", 1), ("gram", 1), ("gramm", 1), ("gramme", 1),
        ("grammes", 1), ("grams", 1), ("grs", 1),
        ("kg", 1000), ("kgs", 1000), ("kilo", 1000), ("kilogram", 1000),
        ("kilogramm", 1000), ("kilogramme", 1000), ("kilogrammes", 1000),
        ("kilograms", 1000), ("kilos", 1000),
        ("lb", 453.592_37), ("lbs", 453.592_37),
        ("ounce", 28.349_523_125), ("ounces", 28.349_523_125),
        ("oz", 28.349_523_125),
        ("pfund", 500), ("pound", 453.592_37), ("pounds", 453.592_37),
        ("unze", 28.349_523_125), ("unzen", 28.349_523_125)
    ]

    // MARK: - A weight

    /// One mass quantity found in a sentence, in grams, and whether the marker
    /// was on it.
    nonisolated struct Weight: Sendable, Hashable {

        var grams: Double

        /// `true` when the quantity carried the leading `r`.
        var isRaw: Bool
    }

    // MARK: - Reading

    /// Whether `text` uses the raw-weight shorthand anywhere in it.
    ///
    /// The marker is recognised **immediately before a quantity**, not as a
    /// word standing on its own. `r` is a letter that turns up everywhere; a
    /// rule that fired on any lone `r` would fire on half the shopping lists
    /// anyone has ever typed. Tied to a number and a unit it is a shape nobody
    /// writes by accident.
    static func isUsed(in text: String) -> Bool {
        weights(in: text).contains { $0.isRaw }
    }

    /// Every mass quantity in `text`, in the order it was written, each saying
    /// whether it carried the marker.
    ///
    /// **One scanner, two answers.** The rule for what counts as a quantity —
    /// the unit table, the single space, the fraction written either way round,
    /// the word boundary that keeps `r50 grammar` out — is the same rule
    /// whether the question is "did the user use the shorthand" or "how much
    /// did they say". A second scanner beside this one would be two copies of a
    /// dozen decisions that have to stay identical, and the day they diverge is
    /// the day a sentence is read as raw by one and priced by the other.
    ///
    /// Unmarked quantities are returned too, which the earlier version had no
    /// use for. They are what lets a typed `45 g polenta` keep the user's own
    /// number instead of the model's guess at it: the person who put the food
    /// on a scale is a better source for its weight than a model reading their
    /// sentence about it.
    static func weights(in text: String) -> [Weight] {
        let characters = Array(text)
        var found: [Weight] = []
        var cursor = 0

        while cursor < characters.count {
            if isMarker(characters, at: cursor),
               let weight = quantity(characters, from: cursor + 1) {
                found.append(Weight(grams: weight.grams, isRaw: true))
                cursor = weight.end
                continue
            }

            // An unmarked quantity has to start a word too. Without that,
            // the `50` of `r50 g` would be read a second time as a weight of
            // its own the moment the marked reading did not consume it.
            if isBoundary(characters, at: cursor - 1),
               let weight = quantity(characters, from: cursor) {
                found.append(Weight(grams: weight.grams, isRaw: false))
                cursor = weight.end
                continue
            }

            cursor += 1
        }

        return found
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

    /// The mass quantity starting at `index`, in grams, and where it ends —
    /// or `nil` if there is not one there.
    ///
    /// A single space is allowed on either side of the number, so `r50g`,
    /// `r 50g`, `r50 g` and `r 50 g` are all the same amount written by
    /// somebody with a different habit. More than one space is not: at that
    /// point the `r` and the number are two separate things on the line rather
    /// than one amount.
    ///
    /// "Space" means any one whitespace character and not the space bar. A
    /// non-breaking space is a keystroke away on an iOS keyboard and arrives
    /// with almost anything pasted, and a tab arrives with anything pasted out
    /// of a spreadsheet — which is exactly where somebody keeps weights. All
    /// of them look like one space on screen, and a rule that can only see
    /// U+0020 rejects a sentence the user cannot tell apart from one it
    /// accepts.
    private static func quantity(
        _ characters: [Character],
        from index: Int
    ) -> (grams: Double, end: Int)? {
        var cursor = skippingSpace(characters, from: index)
        let numberStart = cursor

        guard cursor < characters.count, isDigit(characters[cursor]) else {
            return nil
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
                return nil
            }
            cursor = afterSeparator
            while cursor < characters.count, isDigit(characters[cursor]) {
                cursor += 1
            }
        }

        let numberText = String(characters[numberStart..<cursor]).replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(numberText) else {
            return nil
        }

        guard let unit = unit(characters, from: skippingSpace(characters, from: cursor)) else {
            return nil
        }

        return (grams: amount * unit.grams, end: unit.end)
    }

    /// The unit sitting at `index` and ending there, or `nil`.
    ///
    /// The unit has to end at a boundary, so `r50 grammar` is not fifty grams
    /// of anything.
    private static func unit(
        _ characters: [Character],
        from index: Int
    ) -> (grams: Double, end: Int)? {
        guard index < characters.count else {
            return nil
        }

        for unit in units {
            let end = index + unit.name.count
            guard end <= characters.count else {
                continue
            }
            guard String(characters[index..<end]).lowercased() == unit.name else {
                continue
            }
            if isBoundary(characters, at: end) {
                return (grams: unit.grams, end: end)
            }
        }

        return nil
    }

    /// `index` advanced past one whitespace character, if there is one there.
    private static func skippingSpace(_ characters: [Character], from index: Int) -> Int {
        guard index < characters.count, characters[index].isWhitespace else {
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

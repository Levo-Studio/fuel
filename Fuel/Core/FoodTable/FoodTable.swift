import Foundation

// MARK: - Preparation

/// Whether a table row is the food before cooking or after it.
///
/// The distinction the whole table was brought in for. ANSES-CIQUAL holds raw
/// and cooked as **separate foods with separate rows** — `Polenta or maize/corn
/// semolina, pre-cooked, raw` at 350 kcal and `Polenta or maize/corn semolina,
/// cooked, no added salt` at 76 — which is what makes the error that started
/// this structurally impossible rather than a prompt that has to keep winning.
///
/// The value is computed when the table is built, not here. CIQUAL has no
/// column for it, only two names, and the rule that reads them is fiddly enough
/// to want reviewing as data rather than re-deriving on a phone. See
/// `tools/reduce-ciqual.py`.
///
/// `unspecified` is the common case and is not a failure: most foods have no
/// raw form worth a separate row. An apple is an apple.
nonisolated enum FoodPreparation: UInt8, Sendable, Hashable {

    case unspecified = 0
    case raw = 1
    case prepared = 2
}

// MARK: - A row

/// One food out of the table.
nonisolated struct FoodTableEntry: Sendable, Hashable, Identifiable {

    /// CIQUAL's own `alim_code`. Kept as the identifier rather than a row
    /// index so a number Fuel showed can be traced back to the published
    /// table, and so a rebuilt artefact does not renumber everything.
    let id: Int

    /// The English name, as published. Not shortened and not tidied: it is
    /// what the reduction copied out of `alim_nom_eng`, and altering it is
    /// something ANSES's terms of reuse specifically ask reusers not to do.
    let name: String

    let preparation: FoodPreparation

    let per100g: Per100Grams
}

// MARK: - The table

/// The bundled food composition table, searched by name on the device.
///
/// **No request is made to look up a number.** That is the point of shipping
/// 430 KB rather than calling an API: an online lookup would tell a third party
/// what the user ate, one meal at a time, which is the one thing Fuel is built
/// not to do. There is no network path in this type and there is no cache that
/// could grow one.
///
/// The file is memory-mapped and nothing in it is decoded until it is read, so
/// opening the table costs a `mmap` and a header check rather than a parse. A
/// JSON of the same data would have to be walked in full before the first
/// search; SQLite would bring a query engine and a link-time change for a table
/// of three thousand rows that is never written to.
///
/// The layout is a sorted token index over two flat arrays. Every multi-byte
/// field is little-endian and read with `loadUnaligned`, so no section needs
/// padding and the offsets in `tools/reduce-ciqual.py` are the offsets here.
nonisolated struct FoodTable: Sendable {

    // MARK: - Layout

    private static let magic: UInt32 = 0x4C42_5446    // "FTBL", little-endian
    private static let version: UInt32 = 1
    private static let headerLength = 32
    private static let foodRecordLength = 28
    private static let tokenRecordLength = 12

    private let data: Data
    private let foodCount: Int
    private let tokenCount: Int
    private let foodsAt: Int
    private let tokensAt: Int
    private let postingsAt: Int
    private let namesAt: Int
    private let tokenTextAt: Int

    // MARK: - Opening

    enum Failure: Error {
        case missing
        case unreadable
    }

    /// The table that ships in the app bundle.
    ///
    /// Mapped rather than read: `.mappedIfSafe` leaves the pages on disk until
    /// a search touches them, so a launch that never logs a meal never pays for
    /// the table at all.
    static func bundled(in bundle: Bundle = .main) throws -> FoodTable {
        guard let url = bundle.url(forResource: "ciqual", withExtension: "fueltable") else {
            throw Failure.missing
        }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            throw Failure.unreadable
        }
        return try FoodTable(data: data)
    }

    /// Opens a table held in memory. The bundle path goes through this too, so
    /// the validation below is the same validation in tests and on a device.
    init(data: Data) throws {
        self.data = data

        guard data.count >= Self.headerLength else {
            throw Failure.unreadable
        }

        guard
            Self.word(data, at: 0) == Self.magic,
            Self.word(data, at: 4) == Self.version
        else {
            throw Failure.unreadable
        }

        foodCount = Int(Self.word(data, at: 8))
        tokenCount = Int(Self.word(data, at: 12))
        let postingCount = Int(Self.word(data, at: 16))
        let namesLength = Int(Self.word(data, at: 20))

        foodsAt = Self.headerLength
        tokensAt = foodsAt + foodCount * Self.foodRecordLength
        postingsAt = tokensAt + tokenCount * Self.tokenRecordLength
        namesAt = postingsAt + postingCount * 4
        tokenTextAt = namesAt + namesLength

        // Every offset used below is derived from the header, so a header that
        // disagrees with the file has to be caught once, here, rather than
        // guarded at each of a dozen reads.
        guard tokenTextAt <= data.count else {
            throw Failure.unreadable
        }
    }

    var count: Int { foodCount }

    // MARK: - Searching

    /// The rows that could be `term`, best first.
    ///
    /// **`preferring` is a preference and never a filter**, and that is the
    /// rule rather than an implementation detail. A food that has only a cooked
    /// row still answers a raw query with that row: returning nothing would
    /// turn "CIQUAL does not distinguish this food" into "CIQUAL has never
    /// heard of it", and the second is a miss with a very different remedy. The
    /// caller sees the `preparation` it got and can say so.
    ///
    /// Ordering, in this order:
    ///
    /// 1. **How much of the query the name matched.** A row matching two of the
    ///    user's words beats one matching one, whatever else is true of it.
    ///    Nothing below this line can promote a row that is about a different
    ///    food.
    /// 2. **The preferred preparation.** This is where `r45g polenta` becomes
    ///    350 kcal and `45g polenta` becomes 76.
    /// 3. **The shorter name**, measured in bytes because that is what the
    ///    row already stores. Among rows that matched equally, the one that
    ///    says least about itself is the more nearly exact answer: `Rice,
    ///    white, raw` is a better answer to "rice" than `Rice, mix of species
    ///    (white, wholegrain, wild, red, etc.), raw`. It is a tie-break and
    ///    nothing more — CIQUAL holds seven raw rices and any of them is a
    ///    defensible reading of the bare word, which is why all five reach the
    ///    model rather than one being chosen here.
    /// 4. **The lower CIQUAL code**, so the order is total and a rebuild of the
    ///    artefact does not silently reshuffle the shortlist.
    func search(
        _ term: String,
        preferring preparation: FoodPreparation = .unspecified,
        limit: Int = 5
    ) -> [FoodTableEntry] {
        let queryTokens = Self.tokenise(term)
        guard !queryTokens.isEmpty, limit > 0 else {
            return []
        }

        var matches: [Int: Int] = [:]
        for token in queryTokens {
            for index in postings(matching: token) {
                matches[index, default: 0] += 1
            }
        }
        guard !matches.isEmpty else {
            return []
        }

        let ranked = matches.keys.sorted { left, right in
            let leftMatched = matches[left] ?? 0
            let rightMatched = matches[right] ?? 0
            if leftMatched != rightMatched {
                return leftMatched > rightMatched
            }

            let leftPreferred = state(of: left) == preparation
            let rightPreferred = state(of: right) == preparation
            if leftPreferred != rightPreferred {
                return leftPreferred
            }

            let leftWords = nameLength(of: left)
            let rightWords = nameLength(of: right)
            if leftWords != rightWords {
                return leftWords < rightWords
            }

            return code(of: left) < code(of: right)
        }

        return ranked.prefix(limit).map(entry(atIndex:))
    }

    /// The row with this CIQUAL code, or `nil`.
    ///
    /// A linear walk of a 28-byte-per-row array of three thousand entries,
    /// which is a few microseconds and no index to keep sorted. It is called
    /// once per item of one meal.
    func entry(id: Int) -> FoodTableEntry? {
        for index in 0..<foodCount where code(of: index) == id {
            return entry(atIndex: index)
        }
        return nil
    }

    // MARK: - Token index

    /// The food indices for every indexed token that begins with `token`.
    ///
    /// Prefix rather than equality, so "tomatoes" finds "tomato" — the model
    /// writes a plural as readily as a singular, and an English plural is a
    /// suffix in the great majority of cases. It is deliberately one-directional
    /// and deliberately not a stemmer: a stemmer is a table of rules that would
    /// have to be right in a second language too, and the shortlist is read by
    /// a model that can discard a wrong candidate. Missing the row entirely is
    /// the expensive failure here; an extra candidate costs a line of a prompt.
    private func postings(matching token: String) -> [Int] {
        var low = 0
        var high = tokenCount
        while low < high {
            let middle = (low + high) / 2
            if text(ofToken: middle) < token {
                low = middle + 1
            } else {
                high = middle
            }
        }

        var indices: [Int] = []
        var cursor = low
        while cursor < tokenCount, text(ofToken: cursor).hasPrefix(token) {
            let start = Int(Self.word(data, at: tokensAt + cursor * Self.tokenRecordLength + 6))
            let count = Int(Self.half(data, at: tokensAt + cursor * Self.tokenRecordLength + 10))
            for offset in 0..<count {
                indices.append(Int(Self.word(data, at: postingsAt + (start + offset) * 4)))
            }
            cursor += 1
        }
        return indices
    }

    private func text(ofToken index: Int) -> String {
        let record = tokensAt + index * Self.tokenRecordLength
        let offset = Int(Self.word(data, at: record))
        let length = Int(Self.half(data, at: record + 4))
        return Self.string(data, at: tokenTextAt + offset, length: length)
    }

    // MARK: - Reading a row

    private func entry(atIndex index: Int) -> FoodTableEntry {
        let record = foodsAt + index * Self.foodRecordLength
        return FoodTableEntry(
            id: Int(Self.word(data, at: record)),
            name: Self.string(
                data,
                at: namesAt + Int(Self.word(data, at: record + 20)),
                length: Int(Self.half(data, at: record + 24))
            ),
            preparation: state(of: index),
            per100g: Per100Grams(
                kilocalories: Double(Self.float(data, at: record + 4)),
                protein: Self.optionalValue(data, at: record + 8),
                carbs: Self.optionalValue(data, at: record + 12),
                fat: Self.optionalValue(data, at: record + 16)
            )
        )
    }

    private func code(of index: Int) -> Int {
        Int(Self.word(data, at: foodsAt + index * Self.foodRecordLength))
    }

    private func nameLength(of index: Int) -> Int {
        Int(Self.half(data, at: foodsAt + index * Self.foodRecordLength + 24))
    }

    private func state(of index: Int) -> FoodPreparation {
        let raw = data[data.startIndex + foodsAt + index * Self.foodRecordLength + 26]
        return FoodPreparation(rawValue: raw) ?? .unspecified
    }

    // MARK: - Primitives

    /// A gap in the table, written as NaN and read back as `nil`.
    ///
    /// Not zero. CIQUAL has no fat figure for cooked polenta, and "no figure"
    /// and "no fat" are different statements about a food.
    private static func optionalValue(_ data: Data, at offset: Int) -> Double? {
        let value = Double(float(data, at: offset))
        return value.isFinite ? value : nil
    }

    private static func word(_ data: Data, at offset: Int) -> UInt32 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
    }

    private static func half(_ data: Data, at offset: Int) -> UInt16 {
        data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self) }
    }

    private static func float(_ data: Data, at offset: Int) -> Float {
        Float(bitPattern: word(data, at: offset))
    }

    private static func string(_ data: Data, at offset: Int, length: Int) -> String {
        let start = data.startIndex + offset
        return String(decoding: data[start..<(start + length)], as: UTF8.self)
    }

    // MARK: - Query text

    /// The words of a query, folded the way the artefact's index was folded.
    ///
    /// Lowercased, stripped of accents and split on anything that is not a
    /// letter or a digit, and single letters are dropped. It has to agree
    /// exactly with `fold`/`tokenise` in `tools/reduce-ciqual.py`, because a
    /// query token that is folded differently from the index simply never
    /// matches and there is nothing on screen to say why.
    static func tokenise(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return folded
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 1 }
    }
}

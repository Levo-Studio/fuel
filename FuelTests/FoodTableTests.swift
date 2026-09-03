import Foundation
import Testing

@testable import Fuel

// MARK: - The bundled table

/// These run against the artefact that actually ships, not a fixture. A
/// fixture would prove the reader parses something and nothing about whether
/// `r45g polenta` finds 350 kcal on a phone, which is the only question worth
/// asking here.
@Suite("Food table")
struct FoodTableTests {

    private let table: FoodTable

    init() throws {
        table = try FoodTable.bundled()
    }

    @Test("The table ships in the bundle and opens")
    func opens() {
        #expect(table.count > 3_000)
    }

    // MARK: - The raw-versus-cooked rule

    /// The bug this whole feature replaces. The owner typed `r45g` for raw
    /// polenta and the model answered 72 kcal — roughly 160 per 100 g, which
    /// is cooked polenta. CIQUAL holds the two as separate rows, so asking for
    /// the raw one is a lookup rather than an argument with a prompt.
    @Test("Polenta with the raw marker is the raw row")
    func polentaRaw() throws {
        let entry = try #require(table.search("polenta", preferring: .raw).first)

        #expect(entry.id == 9614)
        #expect(entry.preparation == .raw)
        #expect(entry.per100g.kilocalories == 350)
    }

    @Test("Polenta without the marker is the cooked row")
    func polentaPrepared() throws {
        let entry = try #require(table.search("polenta", preferring: .prepared).first)

        #expect(entry.id == 9615)
        #expect(entry.preparation == .prepared)
        #expect(entry.per100g.kilocalories < 100)
    }

    /// Rice and pasta have the same two-row shape and are the two foods most
    /// likely to be weighed dry by somebody who weighs anything at all.
    ///
    /// The assertion is on the **state** of the top row and on the canonical
    /// row being in the shortlist, not on which of nine raw rices comes first.
    /// CIQUAL holds seven raw rices and eight cooked ones, all of them a
    /// defensible answer to the bare word "rice", and the model picks between
    /// them in the second call with the user's own sentence in front of it.
    /// Pinning "Rice, white, raw" to position one would be pinning a tie-break,
    /// and a tie-break is not what this branch is about.
    @Test("Rice and pasta follow the same rule", arguments: [
        ("rice", 9100, 9104),
        ("pasta", 9810, 9811),
    ])
    func twoRowFoods(term: String, rawCode: Int, preparedCode: Int) throws {
        let rawShortlist = table.search(term, preferring: .raw)
        let preparedShortlist = table.search(term, preferring: .prepared)

        let raw = try #require(rawShortlist.first)
        let prepared = try #require(preparedShortlist.first)

        #expect(raw.preparation == .raw)
        #expect(prepared.preparation == .prepared)
        #expect(rawShortlist.map(\.id).contains(rawCode))
        #expect(preparedShortlist.map(\.id).contains(preparedCode))

        // Not a detail: a dry starch is roughly twice its cooked row and the
        // whole point of choosing between them is that the numbers are far
        // apart.
        let rawRow = try #require(table.entry(id: rawCode))
        let preparedRow = try #require(table.entry(id: preparedCode))
        #expect(rawRow.per100g.kilocalories > preparedRow.per100g.kilocalories * 1.5)
    }

    /// The preference is a preference. A food CIQUAL holds only one way still
    /// answers, because "this food has no raw row" and "this food is not in
    /// the table" are different findings with different remedies.
    ///
    /// An omelette is the case: CIQUAL has seven of them and not one is
    /// labelled raw or cooked, because an omelette has no other state to be
    /// in.
    @Test("A food with one state answers either question with that row")
    func singleStateFood() throws {
        let raw = try #require(table.search("omelette", preferring: .raw).first)
        let prepared = try #require(table.search("omelette", preferring: .prepared).first)

        #expect(raw.id == prepared.id)
        #expect(raw.preparation == .unspecified)
    }

    @Test("A food that is not there is a miss, not a wrong row")
    func miss() {
        #expect(table.search("zzzznotafood").isEmpty)
        #expect(table.search("").isEmpty)
        #expect(table.search("   ").isEmpty)
    }

    // MARK: - Searching

    @Test("A shortlist is short")
    func shortlist() {
        #expect(table.search("rice", limit: 5).count == 5)
        #expect(table.search("rice", limit: 1).count == 1)
        #expect(table.search("rice", limit: 0).isEmpty)
    }

    @Test("More of the query matched beats the preferred preparation")
    func matchQualityWins() throws {
        // "wild rice" matches two words of the wild-rice rows and one of every
        // other rice. Asking for the prepared one must not promote plain
        // cooked white rice over cooked wild rice.
        let entry = try #require(table.search("wild rice", preferring: .prepared).first)

        #expect(entry.name.lowercased().contains("wild"))
        #expect(entry.preparation == .prepared)
    }

    @Test("A plural finds the singular the table indexed")
    func pluralFindsSingular() throws {
        let entry = try #require(table.search("carrots").first)
        #expect(entry.name.lowercased().contains("carrot"))
    }

    @Test("Accents and case are not a different word")
    func folding() {
        let plain = table.search("sauteed potato").map(\.id)
        let accented = table.search("Sautéed Potato").map(\.id)
        #expect(!plain.isEmpty)
        #expect(plain == accented)
    }

    @Test("A row can be fetched back by the code it was shortlisted under")
    func lookupByIdentifier() throws {
        let entry = try #require(table.entry(id: 9614))
        #expect(entry.per100g.kilocalories == 350)
        #expect(table.entry(id: 999_999) == nil)
    }

    // MARK: - The file itself

    @Test("A file that is not a food table is refused rather than misread")
    func rejectsRubbish() {
        #expect(throws: (any Error).self) {
            try FoodTable(data: Data(repeating: 0, count: 64))
        }
        #expect(throws: (any Error).self) {
            try FoodTable(data: Data())
        }
    }

    /// CIQUAL is silent about some macros — cooked polenta has no fat figure —
    /// and the reader has to give that back as "no figure" rather than as a
    /// zero somebody could add up.
    @Test("A gap in the source data survives as a gap")
    func gapSurvives() throws {
        let entry = try #require(table.entry(id: 9615))
        #expect(entry.per100g.fat == nil)
        #expect(entry.per100g.protein != nil)
    }
}

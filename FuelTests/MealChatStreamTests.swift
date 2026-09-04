import Foundation
import Testing

@testable import Fuel

// MARK: - Reading a half-written object

/// What an adjustment object says before it has finished arriving.
///
/// **Nothing here decides anything about a meal**, which is the property the
/// whole type is built around: the complete reply is parsed by
/// `MealChatContract.intent(from:)` exactly as it was before any of this
/// streamed, and every case below is about what the screen may say while it
/// waits.
@Suite("Reading a reply as it arrives")
struct MealChatStreamReaderTests {

    private func progress(_ raw: String) -> MealChatStreamProgress {
        MealChatStreamReader.progress(in: raw)
    }

    // MARK: - Before there is anything

    @Test("nothing at all says nothing at all", arguments: ["", "  ", "Here you go:"])
    func nothingYet(raw: String) {
        #expect(progress(raw) == MealChatStreamProgress())
    }

    @Test("an object that has only opened says nothing yet")
    func justOpened() {
        #expect(progress("{") == MealChatStreamProgress())
        #expect(progress(#"{"cha"#) == MealChatStreamProgress())
    }

    // MARK: - Whether anything is moving

    /// The shape a question comes back as, and the reason the analysis states
    /// are not raised for one.
    @Test("empty arrays are a turn that moves nothing")
    func emptyArrays() {
        #expect(!progress(#"{"changes":[],"additions":[],"reply":"Poi"#).movesSomething)
    }

    @Test("an array that has only opened has not committed to anything")
    func openArray() {
        #expect(!progress(#"{"changes":["#).movesSomething)
        #expect(!progress(#"{"changes":[ "#).movesSomething)
    }

    @Test("an array with an object begun in it is a turn that is moving something")
    func openElement() {
        #expect(progress(#"{"changes":[{"#).movesSomething)
        #expect(progress(#"{"changes":[{"item":1,"gra"#).movesSomething)
    }

    @Test("an addition counts as much as a change")
    func additionCounts() {
        #expect(progress(#"{"changes":[],"additions":[{"name":"Ol"#).movesSomething)
    }

    /// The prompt asks for the arrays first and the reader does not require it.
    @Test("the arrays are read wherever in the object they were written")
    func orderDoesNotMatter() {
        let raw = #"{"reply":"Raised the rice.","changes":[{"item":1,"grams":300}]}"#
        #expect(progress(raw).movesSomething)
    }

    /// The scan tracks strings, so a sentence that quotes the shape does not
    /// look like the shape.
    @Test("a sentence that mentions the wire shape is still just a sentence")
    func stringsAreNotStructure() {
        let raw = #"{"changes":[],"additions":[],"reply":"I would write \"changes\":[{ if I could."}"#
        #expect(!progress(raw).movesSomething)
    }

    /// The fields inside an element are not outer keys and must not be read as
    /// any.
    @Test("a nested key is not read as an outer one")
    func nestedKeysAreIgnored() {
        let raw = #"{"changes":[{"item":1,"reply":"not this","grams":300}],"reply":"This one."}"#
        #expect(progress(raw).sentence == "This one.")
    }

    // MARK: - The sentence

    @Test("the sentence is readable from its first word")
    func partialSentence() {
        #expect(progress(#"{"changes":[],"additions":[],"reply":"Polenta is"#).sentence == "Polenta is")
    }

    @Test("a finished sentence reads as itself")
    func wholeSentence() {
        let raw = #"{"changes":[],"additions":[],"reply":"Polenta is boiled maize meal."}"#
        #expect(progress(raw).sentence == "Polenta is boiled maize meal.")
    }

    @Test("escapes are resolved rather than shown")
    func escapes() {
        #expect(progress(#"{"reply":"He said \"about half\""#).sentence == #"He said "about half""#)
        #expect(progress(#"{"reply":"one\ntwo"#).sentence == "one two")
        #expect(progress(#"{"reply":"café"#).sentence == "café")
    }

    /// A stream can stop between the backslash and what it escapes, and
    /// between any two of a `\u`'s four digits.
    @Test("a sentence cut inside an escape is the sentence without it")
    func partialEscape() {
        #expect(progress(#"{"reply":"He said \"#).sentence == "He said")
        #expect(progress(#"{"reply":"caf\u00"#).sentence == "caf")
    }

    /// The same rule the finished sentence is held to, applied one word at a
    /// time: past the bound there is no sentence to draw.
    @Test("a sentence past the bound is dropped rather than shown short")
    func pastTheBound() {
        let long = String(repeating: "a", count: MealChatContract.maximumReplyLength + 1)
        #expect(progress(#"{"reply":"\#(long)"#).sentence == nil)
    }

    @Test("whitespace inside the object does not confuse the scan")
    func prettyPrinted() {
        let raw = """
            {
              "changes" : [ { "item" : 1, "grams" : 300 } ],
              "reply" : "Raised the rice."
            }
            """
        #expect(progress(raw).movesSomething)
        #expect(progress(raw).sentence == "Raised the rice.")
    }

    /// The same tolerance the finished parse has: a model that wrote a fence
    /// or a word first has still answered.
    @Test("a code fence before the object is stepped over")
    func codeFence() {
        let raw = "```json\n{\"changes\":[],\"reply\":\"Boiled maize meal.\"}"
        #expect(progress(raw).sentence == "Boiled maize meal.")
    }
}

// MARK: - Assembling a turn

/// What each delta produces, and what the finished turn is parsed from.
@Suite("Assembling a streamed turn")
struct MealChatStreamAssemblerTests {

    private static func meal() -> AdjustableMeal {
        AdjustableMeal(
            title: "Rice and something",
            kilocalories: 460,
            macros: MacroTotals(protein: 20, carbs: 60, fat: 12),
            items: [
                RecognisedItem(
                    name: "Rice",
                    kilocalories: 232,
                    grams: 150,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            ]
        )
    }

    /// Feeds a reply one character at a time, which is the worst split a real
    /// stream could produce and therefore the one worth testing.
    private func events(feeding reply: String) -> [MealChatEvent] {
        var assembler = MealChatStreamAssembler()
        var produced: [MealChatEvent] = []
        for character in reply {
            produced += assembler.append(String(character))
        }
        if let finished = try? assembler.finish(over: Self.meal()) {
            produced.append(finished)
        }
        return produced
    }

    @Test("a turn announces that it is adjusting exactly once")
    func announcedOnce() {
        let reply = #"{"changes":[{"item":1,"grams":300}],"additions":[{"name":"Olive oil","grams":14}],"reply":"Done."}"#
        #expect(events(feeding: reply).filter { $0 == .adjusting }.count == 1)
    }

    @Test("a sentence that has not grown produces no event")
    func noRepeats() {
        var assembler = MealChatStreamAssembler()
        _ = assembler.append(#"{"changes":[],"reply":"Yes"#)
        // A delta that adds nothing to the sentence — the closing quote and the
        // brace — must not redraw it.
        #expect(assembler.append(#""}"#).isEmpty)
    }

    @Test("an empty delta is not an event")
    func emptyDelta() {
        var assembler = MealChatStreamAssembler()
        #expect(assembler.append("").isEmpty)
    }

    /// A reply cut off at the request's own ceiling is reported as that rather
    /// than as prose Fuel could not read, so a truncation rate is visible.
    @Test("an unreadable reply that ran out of tokens is named as one")
    func truncated() {
        var assembler = MealChatStreamAssembler()
        _ = assembler.append(#"{"changes":[{"item":1,"gra"#)
        assembler.noteRanOutOfTokens()

        #expect(throws: AIError.truncatedReply) {
            _ = try assembler.finish(over: Self.meal())
        }
    }

    /// A model that answered in sentences has answered. The turn lands with
    /// what it said and with the meal untouched, which is what a reply carrying
    /// no change means however it was written.
    @Test("a reply written as prose finishes as the answer it is")
    func prose() throws {
        var assembler = MealChatStreamAssembler()
        _ = assembler.append("Polenta is boiled maize meal.")

        let finished = try assembler.finish(over: Self.meal())

        #expect(finished == .finished(MealAdjustmentOutcome(reply: "Polenta is boiled maize meal.", meal: nil)))
    }

    @Test("a reply with nothing readable in it at all is a malformed one")
    func malformed() {
        var assembler = MealChatStreamAssembler()
        _ = assembler.append("   ")

        #expect(throws: AIError.malformedResponse) {
            _ = try assembler.finish(over: Self.meal())
        }
    }

    /// A stream that ended inside the object it was writing, with nothing from
    /// the provider to say it hit the ceiling. It is not prose and is not shown
    /// as any.
    @Test("a half-written object is a malformed reply rather than a sentence")
    func fragment() {
        var assembler = MealChatStreamAssembler()
        _ = assembler.append(#"{"changes":[{"item":1,"gra"#)

        #expect(throws: AIError.malformedResponse) {
            _ = try assembler.finish(over: Self.meal())
        }
    }
}

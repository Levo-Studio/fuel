import Foundation
import Testing

@testable import Fuel

// MARK: - Text entry placeholder

/// The example under screen 12's empty field: when it is drawn, when it is
/// not, and what advancing does.
///
/// The examples are handed in rather than read from the catalog, so these are
/// about the rules and not about English wording — with one exception, which
/// says so.
@Suite("Text entry placeholder")
struct TextPlaceholderTests {

    private static let examples = ["one", "two", "three"]

    private func makePlaceholder() -> TextEntryPlaceholder {
        TextEntryPlaceholder(examples: Self.examples)
    }

    // MARK: - When it is drawn

    @Test("an empty field shows the example it is on")
    func emptyFieldShowsAnExample() {
        #expect(makePlaceholder().example(whileTyped: "") == "one")
    }

    @Test("typing clears it, and it comes back when the field is emptied again")
    func typingClearsIt() {
        var placeholder = makePlaceholder()

        #expect(placeholder.example(whileTyped: "") == "one")
        #expect(placeholder.example(whileTyped: "2 eggs") == nil)

        // A field holding a space has been typed into. The model still refuses
        // that sentence — `TextLogTests` pins that separately — but an example
        // drawn under the user's own cursor is the one thing this must not do.
        #expect(placeholder.example(whileTyped: " ") == nil)

        placeholder.advance()
        #expect(placeholder.example(whileTyped: "") == "two")
    }

    // MARK: - Advancing

    @Test("advancing walks the examples in order and wraps")
    func advancingWraps() {
        var placeholder = makePlaceholder()

        #expect(placeholder.example(whileTyped: "") == "one")
        placeholder.advance()
        #expect(placeholder.example(whileTyped: "") == "two")
        placeholder.advance()
        #expect(placeholder.example(whileTyped: "") == "three")
        placeholder.advance()
        #expect(placeholder.example(whileTyped: "") == "one")
    }

    @Test("a placeholder with no examples draws nothing and survives advancing")
    func noExamples() {
        var placeholder = TextEntryPlaceholder(examples: [])

        #expect(placeholder.example(whileTyped: "") == nil)
        placeholder.advance()
        #expect(placeholder.example(whileTyped: "") == nil)
    }

    // MARK: - The line as it is drawn

    @Test("the drawn line is the example, trailing off")
    func theLineTrailsOff() {
        // The glyph and the spacing are the catalog's, so what is pinned here
        // is that the example arrives whole and something follows it — not the
        // wording, which a translator may move.
        let line = TextLogCopy.placeholderLine("2 eggs")

        #expect(line.hasPrefix("2 eggs"))
        #expect(line != "2 eggs")
    }

    @Test("every example names an amount")
    func everyExampleNamesAnAmount() {
        // The line above the field says the estimate is only as exact as the
        // amounts are. An example without a figure in it would teach the
        // opposite of the screen's own instruction, so this is a rule about the
        // copy rather than about the type that shows it.
        #expect(!TextLogCopy.placeholderExamples.isEmpty)
        for example in TextLogCopy.placeholderExamples {
            // Read out before the expectation: `contains(where:)` is
            // `rethrows`, and the macro cannot expand a call it must decide
            // about throwing for.
            let namesAnAmount = example.contains(where: \.isNumber)
            #expect(namesAnAmount)
        }
    }
}

import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Text entry placeholder

/// The example under screen 12's empty field: when it is drawn, when it is
/// not, and what advancing does.
///
/// The examples are handed in rather than read from the catalog, so these are
/// about the rules and not about English wording — except for the two that are
/// rules about the copy itself, and say so: every example names an amount, and
/// every example fits the drawn line at the largest text size.
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

    @Test("every example fits the drawn line at the largest text size")
    @MainActor
    func examplesFitTheDrawnLine() {
        // A prompt is one line. The typed text under it wraps and grows the
        // field downward; the placeholder does not, so an example that outruns
        // the line loses its trailing ellipsis to a truncating one — the export's
        // own mark replaced by the system's.
        //
        // The line is the export's frame less the inset the log flow heads its
        // screens at. The size is the widest the field can ever draw: the
        // drawn 19pt taken to `FuelTypography.maximumScale`, which is where a
        // scaling style stops growing. Asking the style for its font instead
        // would measure whatever content size this process happens to run at,
        // which is the default one — and a test that measures the easy case is
        // decoration.
        let lineWidth = 390 - 2 * FuelMetrics.Screen.logFlowHorizontalPadding
        let drawnSize = FuelTypography.textEntry.uiFont.pointSize
        let font = FuelTypography.textEntry.uiFont.withSize(drawnSize * FuelTypography.maximumScale)

        for example in TextLogCopy.placeholderExamples {
            let drawn = TextLogCopy.placeholderLine(example) as NSString
            let width = drawn.size(withAttributes: [.font: font]).width
            #expect(width <= lineWidth, "\(drawn) needs \(width)pt of \(lineWidth)pt")
        }
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

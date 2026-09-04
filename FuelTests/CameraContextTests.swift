import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Camera context line

/// The copy of the optional line under screen 07's viewfinder.
///
/// The field itself is `MealTextField`, whose rules are pinned once in
/// `TextPlaceholderTests` and are not repeated here. What is here is what only
/// this screen can answer: whether its own examples fit the line they are drawn
/// on, and whether they are about the thing the field is for.
@Suite("Camera context line")
struct CameraContextTests {

    @Test("every example fits the drawn line at the largest text size")
    @MainActor
    func examplesFitTheDrawnLine() {
        // A prompt is one line. The typed text under it wraps and grows the
        // field downward; the placeholder does not, so an example that outruns
        // the line loses its trailing ellipsis to a truncating one — the
        // export's own mark replaced by the system's.
        //
        // Measured against the export's own 390pt frame, less the inset the log
        // flow heads its screens at, and at the widest the field can ever draw:
        // the drawn 19pt taken to `FuelTypography.maximumScale`. The same
        // arithmetic screen 12's examples are held to, because the two fields
        // are the same control at the same inset.
        let lineWidth = 390 - 2 * FuelMetrics.Screen.logFlowHorizontalPadding
        let drawnSize = FuelTypography.textEntry.uiFont.pointSize
        let font = FuelTypography.textEntry.uiFont.withSize(drawnSize * FuelTypography.maximumScale)

        for example in CameraCopy.contextExamples {
            let drawn = CameraCopy.contextLine(example) as NSString
            let width = drawn.size(withAttributes: [.font: font]).width
            #expect(width <= lineWidth, "\(drawn) needs \(width)pt of \(lineWidth)pt")
        }
    }

    @Test("the drawn line is the example, trailing off")
    func theLineTrailsOff() {
        // The glyph and the spacing are the catalog's, so what is pinned here
        // is that the example arrives whole and something follows it — not the
        // wording, which a translator may move.
        let line = CameraCopy.contextLine("Fried in olive oil")

        #expect(line.hasPrefix("Fried in olive oil"))
        #expect(line != "Fried in olive oil")
    }

    /// Deliberately **not** screen 12's rule.
    ///
    /// Every one of the text tab's examples names an amount, because the line
    /// above that field asks for amounts. This field sits under a photograph
    /// that already shows the meal, so an example naming a quantity would teach
    /// the user to type what the picture is for. What each one has to name
    /// instead is something the frame cannot carry, which is not a shape a test
    /// can assert — so what is held here is only that there are examples, that
    /// none is blank, and that none of them repeats another.
    @Test("the examples are four distinct, non-empty lines")
    func examplesAreDistinct() {
        let examples = CameraCopy.contextExamples

        #expect(examples.count == 4)
        #expect(Set(examples).count == examples.count)
        for example in examples {
            #expect(!example.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}

// MARK: - Camera context in the instruction

/// What the typed line becomes on its way into a request.
///
/// Pure functions on `EstimateContract`, so none of this needs a transport, a
/// key or a simulated provider — the wire-level half, that the string this
/// builds actually reaches a body and that an overlong one never does, is in
/// `AIClientTests`.
@Suite("Camera context in the instruction")
struct CameraContextInstructionTests {

    @Test("a note reaches the instruction, framed and labelled")
    func noteReachesTheInstruction() {
        let instruction = EstimateContract.photoInstruction(with: "Fried in olive oil")

        #expect(instruction.hasPrefix(EstimateContract.photoInstruction))
        #expect(instruction.contains(EstimateContract.photoContextPreamble))
        #expect(instruction.contains("Note: Fried in olive oil"))
    }

    /// The rule `textInstruction(for:)` already keeps for the typed sentence:
    /// everything Fuel has to say is said before the user's own words begin, so
    /// a note that reads like an instruction is described rather than obeyed.
    @Test("the note comes after everything Fuel has to say")
    func theNoteComesLast() throws {
        let instruction = EstimateContract.photoInstruction(with: "Fried in olive oil")

        let preamble = try #require(instruction.range(of: EstimateContract.photoContextPreamble))
        let note = try #require(instruction.range(of: "Note: "))

        #expect(preamble.upperBound <= note.lowerBound)
    }

    /// The field is optional, and optional has to mean the request is the one
    /// it would have been — not a similar one with an empty note in it.
    @Test("nothing typed is the instruction as it was before the field existed")
    func noNoteIsTheOldInstruction() {
        #expect(EstimateContract.photoInstruction(with: nil) == EstimateContract.photoInstruction)
        #expect(EstimateContract.photoInstruction(with: "") == EstimateContract.photoInstruction)
        #expect(EstimateContract.photoInstruction(with: " \n\t ") == EstimateContract.photoInstruction)
    }

    @Test("a note is collapsed onto one line")
    func whitespaceIsCollapsed() {
        let instruction = EstimateContract.photoInstruction(with: "  Fried in\n\n   olive oil  ")

        #expect(instruction.contains("Note: Fried in olive oil"))
        #expect(!instruction.contains("olive oil  "))
    }

    @Test("a note at the bound is carried")
    func aNoteAtTheBoundIsCarried() {
        let note = String(repeating: "a", count: EstimateContract.maximumContextLength)

        #expect(EstimateContract.boundedContext(note) == note)
        #expect(EstimateContract.photoInstruction(with: note).contains("Note: \(note)"))
    }

    /// Dropped rather than truncated, and dropped *here* — before a body
    /// exists — so an overlong note is never a thing a provider was sent.
    @Test("a note past the bound is dropped, not truncated")
    func anOverlongNoteIsDropped() {
        let note = String(repeating: "a", count: EstimateContract.maximumContextLength + 1)

        #expect(EstimateContract.boundedContext(note) == nil)
        #expect(EstimateContract.photoInstruction(with: note) == EstimateContract.photoInstruction)
    }

    /// The bound is on what is sent, not on what was typed, so a note that is
    /// only long because the user hit return forty times still travels.
    @Test("the bound is counted after the whitespace is collapsed")
    func theBoundIsCountedOnWhatIsSent() {
        let words = String(repeating: "a", count: 20)
        let padded = words + String(repeating: "\n", count: EstimateContract.maximumContextLength)

        #expect(EstimateContract.boundedContext(padded) == words)
    }

    /// The text tab is a different method with a different prompt, and it was
    /// not part of this. A photo's framing arriving in a typed request would
    /// tell the model to weigh a photograph that is not there.
    @Test("the typed sentence's instruction is untouched by any of this")
    func theTextInstructionIsUntouched() {
        for sentence in ["two eggs and toast", "r300g rice"] {
            let instruction = EstimateContract.textInstruction(for: sentence)

            #expect(!instruction.contains(EstimateContract.photoContextPreamble))
            #expect(!instruction.contains(EstimateContract.photoInstruction))
            #expect(instruction.contains("Description: \(sentence)"))
        }
    }
}

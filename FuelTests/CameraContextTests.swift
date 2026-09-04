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

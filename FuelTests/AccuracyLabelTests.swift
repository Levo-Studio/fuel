import Foundation
import SwiftUI
import Testing

@testable import Fuel

// MARK: - The drawn element

/// The accuracy figure is not in the export, so every value it uses has to be
/// one the export does draw. These hold it to the four that were cited.
@Suite("Accuracy label")
struct AccuracyLabelTests {

    /// `Screens2c.dc.html` line 316, on screen 14 itself:
    /// `font:400 10.5px 'DM Mono',monospace;letter-spacing:.1em`.
    @Test("The figure is set in the export's own small tracked mono")
    func drawnStyle() {
        let style = FuelAccuracyLabel.style

        #expect(style == FuelTypography.overlayCaption)
        #expect(style.family == .mono)
        #expect(style.weight == 400)
        #expect(style.size == 10.5)
        #expect(style.trackingEm == 0.1)
    }

    /// Drawn already uppercase, like `CAPTURED PHOTO` and `CANCEL`, so the
    /// style must not transform on top of the value.
    @Test("The style does not uppercase what the catalog already did")
    func doesNotTransform() {
        #expect(FuelAccuracyLabel.style.isUppercased == false)
        #expect(FuelAccuracyCopy.figure(80) == "80% ACC")
    }

    /// A tracked uppercase eyebrow is pinned by `FuelTypography`'s own rule.
    /// Here it also keeps the day-list row's trailing group a fixed width, so
    /// the meal name's share of the row does not shrink as text size grows.
    @Test("The figure does not grow with Dynamic Type")
    func pinnedAgainstDynamicType() {
        #expect(FuelAccuracyLabel.style.scalesRelativeTo == nil)
    }

    /// Smaller than the kilocalorie figure it sits beside, at both sites.
    @Test("The figure is smaller than the number it qualifies")
    func smallerThanTheNumber() {
        #expect(FuelAccuracyLabel.style.size < FuelTypography.listValue.size)
        #expect(FuelAccuracyLabel.style.size < FuelTypography.resultCalories.size)
    }

    /// `muted` is derived from the theme's ink and never from the accent, so
    /// the element draws identically under all five.
    @Test("The figure's colour does not move with the accent")
    func accentIndependent() {
        let colours = FuelAccent.allCases.map { accent in
            FuelPalette(theme: .dark, accent: accent).muted
        }

        #expect(Set(colours).count == 1)
    }

    @Test("Both ends of the scale format")
    func formatsWholeScale() {
        #expect(FuelAccuracyCopy.figure(0) == "0% ACC")
        #expect(FuelAccuracyCopy.figure(100) == "100% ACC")
    }

    /// `80% ACC` spoken letter by letter is not a word, and an abbreviation
    /// that saves room on a row saves none in speech.
    @Test("VoiceOver is given the word, not the abbreviation")
    func spokenFormIsAWord() {
        #expect(FuelAccuracyCopy.spoken(80) == "80% accuracy")
    }
}

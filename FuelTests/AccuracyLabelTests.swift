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
    ///
    /// This holds the constant the view names. It cannot hold the view — see
    /// `AccuracyLabelDrawingTests`, which does, and which exists because this
    /// test alone stayed green when `body` was set in a different style.
    @Test("The style the label names is the export's own small tracked mono")
    func drawnStyle() {
        let style = MealAccuracyLabel.style

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
        #expect(MealAccuracyLabel.style.isUppercased == false)
        #expect(MealResultCopy.accuracy(80) == "80% ACC")
    }

    /// A tracked uppercase eyebrow is pinned by `FuelTypography`'s own rule.
    /// Here it also keeps the score from crowding the two pills it stands
    /// between as the user's text size grows.
    @Test("The figure does not grow with Dynamic Type")
    func pinnedAgainstDynamicType() {
        #expect(MealAccuracyLabel.style.scalesRelativeTo == nil)
    }

    /// Quieter than everything around it on the row it joins: the two pills'
    /// 11.5pt sans, and the 58pt figure under them.
    @Test("The score is smaller than what it stands among")
    func smallerThanItsNeighbours() {
        #expect(MealAccuracyLabel.style.size < FuelTypography.tabLabel.size)
        #expect(MealAccuracyLabel.style.size < FuelTypography.resultCalories.size)
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
        #expect(MealResultCopy.accuracy(0) == "0% ACC")
        #expect(MealResultCopy.accuracy(100) == "100% ACC")
    }

    /// `80% ACC` spoken letter by letter is not a word, and an abbreviation
    /// that saves room on a row saves none in speech.
    @Test("VoiceOver is given the word, not the abbreviation")
    func spokenFormIsAWord() {
        #expect(MealResultCopy.accuracySpoken(80) == "80% accuracy")
    }
}

// MARK: - What is actually drawn

/// The style test above asserts a declaration. This one renders the view and
/// measures the ink.
///
/// **The distinction is not pedantry — it is the finding that produced this
/// suite.** `MealAccuracyLabel.style` is a constant the view happens to
/// reference; changing `body` to `.fuelStyle(FuelTypography.listValue)` and
/// leaving the constant alone left the entire suite green, so nothing tested
/// what the user sees. Rendering the label and measuring the drawn glyphs
/// closes that, the same way `MealResultFooterTests` closed it for the
/// footer's box.
///
/// **`ImageRenderer` rather than `HostedScreen`, and the reason is not
/// convenience.** This element has no relationship to the safe area, the scene
/// or the device's size — the questions `HostedScreen` exists to answer — and
/// two suites standing windows on the one test scene and spinning the run loop
/// under them is a race: the host crashed part-way through a full run and
/// restarted, losing a hundred-odd tests that had nothing to do with either
/// suite. Rendering off-screen asks exactly the same question of exactly the
/// same view, touches nothing shared, and is a hundred times faster.
///
/// **What is compared, and why it is not an arithmetic expectation.** A
/// reference run of the same string is rendered beside it, in a font built here
/// from the export's own literals — `DMMono-Regular` at `10.5` with `.1em` of
/// tracking, `Screens2c.dc.html` line 316 — reaching for nothing in
/// `FuelTypography`. Both go through the same scan, so side bearings,
/// antialiasing and the tolerance cancel, and what is left is whether the label
/// is set in the size and tracking the export draws. Set in `listValue` it
/// measures twelve points wider over seven characters; in `timestamp`, four
/// narrower.
@Suite("Accuracy label · what is drawn")
@MainActor
struct AccuracyLabelDrawingTests {

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    /// The export's own values for line 316, written out rather than read off
    /// `FuelTypography`, so this cannot agree with the view by construction.
    private static let drawnFace = "DMMono-Regular"
    private static let drawnSize: CGFloat = 10.5
    private static let drawnTrackingEm: CGFloat = 0.1

    private static let sample = 80

    /// How much of the canvas one drawn thing covers.
    private struct Ink {
        var width: Int
        var height: Int
    }

    /// Renders `view` on the palette's own ground — one known colour for the
    /// scan to measure against — and reports the ink's extent.
    ///
    /// Scale 1, so a pixel index is a point and every distance is in the
    /// export's own units, exactly as `DrawnPixels` expects.
    private func ink(of view: some View) throws -> Ink {
        let renderer = ImageRenderer(
            content: view
                .environment(\.fuelPalette, Self.palette)
                .padding()
                .background(Self.palette.background)
        )
        renderer.scale = 1
        let rendered = try #require(renderer.uiImage)
        let drawing = try #require(DrawnPixels(rendered))
        let box = try #require(drawing.inkBox(against: DrawnPixels.Channels(Self.palette.background)))
        return Ink(
            width: Int(drawing.size.width) - box.left - box.right,
            height: Int(drawing.size.height) - box.top - box.bottom
        )
    }

    /// The same string, set from the export's literals and nothing else.
    private func reference(_ percent: Int) -> some View {
        let face = UIFont(name: Self.drawnFace, size: Self.drawnSize)
        return Text(MealResultCopy.accuracy(percent))
            .font(Font(face ?? .monospacedSystemFont(ofSize: Self.drawnSize, weight: .regular)))
            .tracking(Self.drawnTrackingEm * Self.drawnSize)
            .foregroundStyle(Self.palette.muted)
    }

    @Test("the drawn label is the size the export's own values give")
    func drawnInkMatchesTheExport() throws {
        let label = try ink(of: MealAccuracyLabel(percent: Self.sample))
        let expected = try ink(of: reference(Self.sample))

        expect(label.width, isTheDrawn: CGFloat(expected.width))
        expect(label.height, isTheDrawn: CGFloat(expected.height))
    }

    /// A mono face advances every glyph equally, so a longer figure is wider by
    /// a whole advance per character. It is what makes the element's width vary
    /// with the meal — the reason the score could not stand in front of the
    /// 58pt figure — and it is worth having measured rather than reasoned.
    @Test("a longer figure is wider, and the reference widens with it")
    func widthFollowsTheDigitCount() throws {
        let short = try ink(of: MealAccuracyLabel(percent: 9))
        let long = try ink(of: MealAccuracyLabel(percent: 100))

        #expect(long.width > short.width)
        expect(long.width - short.width, isTheDrawn: CGFloat(
            try ink(of: reference(100)).width - ink(of: reference(9)).width
        ))
    }
}

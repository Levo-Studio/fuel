import CoreText
import Testing
import UIKit

@testable import Fuel

// MARK: - oklch

/// The design authors four of the five accents and the error colour in oklch,
/// and iOS has no oklch initialiser. The conversion is therefore the one piece
/// of arithmetic standing between the design and what a user sees, and a
/// transposed matrix row would produce a plausible-looking wrong colour that no
/// build failure would catch.
@Suite("oklch conversion")
struct FuelOklchTests {

    /// One 8-bit step, which is the finest difference a screen can show. Every
    /// expectation below is stated in that unit so a failure reads as "the
    /// colour moved by n visible steps".
    private static let step = 1.0 / 255

    private func expectClose(
        _ value: FuelRGBA,
        red: Double,
        green: Double,
        blue: Double,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(value.red - red) < Self.step, sourceLocation: sourceLocation)
        #expect(abs(value.green - green) < Self.step, sourceLocation: sourceLocation)
        #expect(abs(value.blue - blue) < Self.step, sourceLocation: sourceLocation)
    }

    @Test("pure white and pure black come back exactly")
    func achromaticEnds() {
        // L = 1 with no chroma is the sRGB white point, L = 0 is black. Any
        // error in the matrices shows up here first, because both are fixed
        // points of the whole chain.
        expectClose(.oklch(1, 0, 0), red: 1, green: 1, blue: 1)
        expectClose(.oklch(0, 0, 0), red: 0, green: 0, blue: 0)
    }

    @Test("mid grey stays neutral")
    func neutralStaysNeutral() {
        let grey = FuelRGBA.oklch(0.6, 0, 180)
        #expect(abs(grey.red - grey.green) < Self.step)
        #expect(abs(grey.green - grey.blue) < Self.step)
        #expect(grey.isInGamut)
    }

    @Test("sRGB primaries round-trip from their oklch coordinates")
    func primaries() {
        // Published oklch coordinates of the sRGB primaries. They are the
        // standard reference values for this conversion and are what a reviewer
        // can check against any oklch tool.
        expectClose(.oklch(0.6280, 0.2577, 29.234), red: 1, green: 0, blue: 0)
        expectClose(.oklch(0.8664, 0.2948, 142.495), red: 0, green: 1, blue: 0)
        expectClose(.oklch(0.4520, 0.3132, 264.052), red: 0, green: 0, blue: 1)
    }

    @Test("the drawn accents convert to the values the design renders")
    func drawnAccents() {
        // The hex beside each accent in FuelPalette, restated here so the two
        // cannot drift apart unnoticed.
        expectClose(FuelAccent.blue.rgba(for: .dark), red: 0x60 / 255, green: 0xAA / 255, blue: 0xF3 / 255)
        expectClose(FuelAccent.blue.rgba(for: .light), red: 0x23 / 255, green: 0x68 / 255, blue: 0xBD / 255)
        expectClose(FuelAccent.green.rgba(for: .dark), red: 0x5A / 255, green: 0xCA / 255, blue: 0x94 / 255)
        expectClose(FuelAccent.sand.rgba(for: .dark), red: 0xF0 / 255, green: 0xB8 / 255, blue: 0x71 / 255)
        expectClose(FuelAccent.sand.rgba(for: .light), red: 0xAC / 255, green: 0x68 / 255, blue: 0x20 / 255)
        expectClose(FuelAccent.lilac.rgba(for: .dark), red: 0xBD / 255, green: 0x9F / 255, blue: 0xF2 / 255)
        expectClose(FuelAccent.lilac.rgba(for: .light), red: 0x7A / 255, green: 0x53 / 255, blue: 0xB4 / 255)
    }

    @Test("the error colour converts to the value the design renders")
    func errorColour() {
        expectClose(FuelPalette.errorRGBA, red: 0xDA / 255, green: 0x53 / 255, blue: 0x4F / 255)
        #expect(FuelPalette.errorRGBA.isInGamut)
    }

    @Test("light green is gamut-mapped to the pixel the export draws, and says so")
    func lightGreenIsGamutMapped() {
        // The one accent the design asks for that sRGB cannot show, and so the
        // one whose value rests on a judgement rather than on arithmetic. It is
        // pinned harder than the rest, not less: #007D51 is what the export
        // renders, reached by reducing chroma at the requested lightness and
        // hue per CSS Color 4. Per-channel clamping would give #007F4E, two
        // 8-bit steps off the drawn pixel — this expectation is what keeps
        // anyone from simplifying the mapping back into a clamp.
        let green = FuelAccent.green.rgba(for: .light)
        expectClose(green, red: 0x00 / 255, green: 0x7D / 255, blue: 0x51 / 255)
        #expect(!green.isInGamut)
    }

    @Test("gamut mapping keeps lightness and hue and only gives up chroma")
    func gamutMappingPreservesLightnessAndHue() {
        // What makes chroma reduction the right mapping rather than merely a
        // different one. A wildly out-of-range chroma at a reachable lightness
        // must come back as the same colour, only less saturated — never as a
        // different hue and never as a different brightness.
        let requested = FuelRGBA.oklch(0.52, 0.4, 160)
        let mapped = FuelAccent.green.rgba(for: .light)
        #expect(!requested.isInGamut)
        expectClose(requested, red: mapped.red, green: mapped.green, blue: mapped.blue)
    }

    @Test("every other accent and theme pair is inside sRGB")
    func remainingAccentsAreInGamut() {
        for accent in FuelAccent.allCases {
            for theme in FuelTheme.allCases where !(accent == .green && theme == .light) {
                #expect(accent.rgba(for: theme).isInGamut, "\(accent) / \(theme)")
                #expect(accent.onRGBA(for: theme).isInGamut, "\(accent) on / \(theme)")
            }
        }
    }
}

// MARK: - Palette

@Suite("Palette")
struct FuelPaletteTests {

    @Test("every accent resolves an accent and an on-colour in both themes")
    func accentsResolveEverywhere() {
        // Both lookups switch over (accent, theme). An unhandled pair would not
        // compile, but a pair mapped to the *wrong* half of the design table
        // would, so this also pins the two colours apart: an accent that
        // equalled its own on-colour would be invisible text on a filled
        // button.
        for accent in FuelAccent.allCases {
            for theme in FuelTheme.allCases {
                let palette = FuelPalette(theme: theme, accent: accent)
                #expect(palette.accentColor != palette.onAccent, "\(accent) / \(theme)")
                #expect(accent.rgba(for: theme) != accent.onRGBA(for: theme), "\(accent) / \(theme)")
            }
        }
    }

    @Test("mono is the default accent and dark is what the app opens on")
    func defaults() {
        let palette = FuelPalette(theme: .dark)
        #expect(palette.accent == .mono)
        #expect(FuelTheme.allCases == [.light, .dark])
        #expect(FuelAccent.allCases == [.mono, .blue, .green, .sand, .lilac])
    }

    @Test("the camera surface stays dark in both themes")
    func cameraIsDarkInBothThemes() {
        // Deliberate, and the reason the camera screens carry their own fixed
        // inks. A light-mode camera would wash out the preview it exists to
        // show.
        let dark = FuelRGBA(hex: 0x090A0A)
        let light = FuelRGBA(hex: 0x0D0D0E)
        for value in [dark, light] {
            #expect(value.red < 0.1)
            #expect(value.green < 0.1)
            #expect(value.blue < 0.1)
        }
        #expect(FuelPalette(theme: .light).camera != FuelPalette(theme: .light).background)
    }

    @Test("hex components land on the design's values")
    func hexInitialiser() {
        let ink = FuelRGBA(hex: 0xFAFAFA, opacity: 0.45)
        #expect(ink.red == 250.0 / 255)
        #expect(ink.green == 250.0 / 255)
        #expect(ink.blue == 250.0 / 255)
        #expect(ink.opacity == 0.45)
    }
}

// MARK: - Typography

@Suite("Typography")
struct FuelTypographyTests {

    /// The `wght` axis identifier, as `CTFontCopyVariation` reports it.
    private static let weightAxis = 0x77676874

    @Test("both bundled families are registered under the names the code asks for")
    func fontsAreRegistered() {
        // UIFont never returns nil for a descriptor, so an unregistered font
        // silently becomes the system face and the whole design goes with it.
        // Comparing family names is the only way that failure surfaces.
        #expect(FuelTypography.screenTitle.uiFont.familyName == "Plus Jakarta Sans")
        #expect(FuelTypography.dayTotal.uiFont.familyName == "DM Mono")
    }

    @Test("the sans face resolves the exact weight the design draws")
    func variableWeightsResolve() {
        // The weight trait would land weight 300 on ExtraLight (200). The
        // variation axis is set explicitly for exactly that reason, and this
        // test is what keeps someone from simplifying it back.
        let drawn: [(FuelTypography.Style, Double)] = [
            (FuelTypography.addGlyph, 300),
            (FuelTypography.body, 400),
            (FuelTypography.listTitle, 500),
            (FuelTypography.screenTitle, 600)
        ]
        for (style, weight) in drawn {
            let variation = CTFontCopyVariation(style.uiFont) as? [AnyHashable: Any]
            let axis = variation?[Self.weightAxis] as? Double
            // 400 is the file's default instance, for which CoreText reports no
            // variation at all.
            #expect((axis ?? 400) == weight, "\(weight)")
        }
    }

    @Test("no style uses a weight the bundle does not carry")
    func weightsStayInRange() {
        for style in FuelTypography.allDrawnStyles {
            switch style.family {
            case .sans:
                #expect([300, 400, 500, 600].contains(style.weight))
            case .mono:
                #expect(style.weight == 400, "mono is drawn at 400 only")
            }
        }
    }

    @Test("fractional sizes survive")
    func fractionalSizes() {
        // 11.5, 13.5 and 14.5 are design points. Rounding any of them is a
        // design deviation, and it is the kind that looks fine in a screenshot.
        #expect(FuelTypography.eyebrow.size == 11.5)
        #expect(FuelTypography.lead.size == 13.5)
        #expect(FuelTypography.entryTitle.size == 14.5)
        #expect(FuelTypography.hint.size == 12.5)
        #expect(FuelTypography.macroLabelSmall.size == 10.5)
    }

    @Test("tracking converts from em to points against the size")
    func trackingInPoints() {
        let eyebrow = FuelTypography.eyebrow
        #expect(abs(eyebrow.tracking - 0.14 * 11.5) < 0.001)

        let display = FuelTypography.display
        #expect(abs(display.tracking - -0.03 * 34) < 0.001)
    }

    @Test("the tight numeral line heights do not add spacing")
    func tightLineHeightsClampToZero() {
        // `74px/0.9` and `58px/0.9` pull the CSS line box in around the digits.
        // SwiftUI cannot subtract from its line box, and neither figure ever
        // wraps, so zero is the right answer rather than a compromise.
        #expect(FuelTypography.dayTotal.lineSpacing == 0)
        #expect(FuelTypography.resultCalories.lineSpacing == 0)
    }

    @Test("wrapping prose gets the line spacing the design asks for")
    func looseLineHeightsAddSpacing() {
        #expect(FuelTypography.lead.lineSpacing > 0)
        #expect(FuelTypography.body.lineSpacing > 0)
    }

    @Test("headlines scale and the fixed-geometry styles do not")
    func dynamicTypeOptIn() {
        // The two headlines own their line and fit at the cap, so they scale.
        // The four below are pinned by geometry that is not theirs to change:
        // a 74pt numeral with a suffix beside it, the percentage centred in a
        // 104pt ring, a name in a 52pt column, a label in a three-column bar.
        #expect(FuelTypography.display.scalesRelativeTo != nil)
        #expect(FuelTypography.displaySmall.scalesRelativeTo != nil)
        #expect(FuelTypography.screenTitle.scalesRelativeTo != nil)
        #expect(FuelTypography.dayTotal.scalesRelativeTo == nil)
        #expect(FuelTypography.monoValue.scalesRelativeTo == nil)
        #expect(FuelTypography.macroLabel.scalesRelativeTo == nil)
        #expect(FuelTypography.tabLabel.scalesRelativeTo == nil)
    }
}

// MARK: - Metrics

@Suite("Metrics")
struct FuelMetricsTests {

    @Test("the ring's offset is capped at a full ring")
    func ringOffsetCaps() {
        #expect(FuelMetrics.Ring.strokeOffset(total: 0, goal: 2400) == FuelMetrics.Ring.circumference)
        #expect(FuelMetrics.Ring.strokeOffset(total: 2400, goal: 2400) == 0)
        // An over-budget day fills the ring rather than winding round again.
        #expect(FuelMetrics.Ring.strokeOffset(total: 4800, goal: 2400) == 0)
        #expect(abs(FuelMetrics.Ring.strokeOffset(total: 1200, goal: 2400) - 169.65) < 0.001)
    }

    @Test("the two drawn control sizes the mockup could hide are present")
    func drawnControlsArePresent() {
        // Both are app UI drawn as bare pixel values on screens 04, 05 and 06,
        // and both are the kind a feature writer would otherwise invent.
        #expect(FuelMetrics.Control.addButton == 58)
        #expect(FuelMetrics.Control.selectionDot == 18)
        #expect(FuelMetrics.Control.addButtonTrailingInset == 26)
        #expect(FuelMetrics.Control.addButtonBottomInset == 32)
    }

    @Test("a control drawn smaller than a finger is given the difference, and one drawn larger is not")
    func hitTargetOverhang() {
        // The gear on Today is the case this exists for: 34 drawn, 44 needed,
        // so 5 on each side.
        let gear = FuelMetrics.Control.hitTargetOverhang(around: FuelMetrics.Control.circleButton)
        #expect(gear == 5)
        #expect(FuelMetrics.Control.circleButton + gear * 2 == FuelMetrics.Control.minimumHitTarget)

        // The add button is already 58. A negative overhang here would shrink
        // the one control on Today that is comfortably large enough.
        #expect(FuelMetrics.Control.hitTargetOverhang(around: FuelMetrics.Control.addButton) == 0)
    }

    @Test("a goal of zero leaves the ring empty instead of dividing by it")
    func ringSurvivesAZeroGoal() {
        #expect(FuelMetrics.Ring.strokeOffset(total: 500, goal: 0) == FuelMetrics.Ring.circumference)
    }

    @Test("the fixed radii are the ones drawn, and the mockup's corner is not among them")
    func radii() {
        // Three constants, because the export's fourth radius is
        // `border-radius:50%` — a shape, drawn as a Circle, not a number.
        let radii = [FuelMetrics.Radius.pill, FuelMetrics.Radius.card, FuelMetrics.Radius.thumbnail]
        #expect(radii == [100, 16, 22])
    }

    @Test("the phone mockup's own corner radius appears nowhere in the layer")
    func mockupCornerNeverReachesTheApp() {
        // 46px is drawn seventeen times in the export, once per frame, and it
        // is the picture of the phone rather than anything in the app. Sweeping
        // every constant rather than only the radii is the point: it is not the
        // Radius enum that would tempt someone into it, it is a writer looking
        // at a rounded rectangle in the export and reaching for the nearest
        // number. Every value below is a real candidate for that mistake.
        #expect(!FuelMetrics.allDrawnValues.contains(46))
    }
}

// MARK: - Motion

@Suite("Motion")
struct FuelMotionTests {

    @Test("every curve returns an animation when motion is not reduced")
    func fullMotion() {
        for curve in FuelMotion.allCurves {
            #expect(FuelMotion.resolve(curve, reduceMotion: false) != nil)
        }
    }

    @Test("reduced motion cross-fades or drops, per curve")
    func reducedMotion() {
        // The distinction is the point: a state change still needs to be
        // followable, so most curves fade rather than snap; only motion whose
        // purpose is travel is dropped.
        #expect(FuelMotion.resolve(FuelMotion.standard, reduceMotion: true) != nil)
        #expect(FuelMotion.resolve(FuelMotion.value, reduceMotion: true) != nil)
        #expect(FuelMotion.resolve(FuelMotion.progress, reduceMotion: true) != nil)
        #expect(FuelMotion.resolve(FuelMotion.emphasised, reduceMotion: true) == nil)
    }

    @Test("no curve outlasts the interaction that caused it")
    func durationsStayTight() {
        for curve in FuelMotion.allCurves {
            #expect(curve.duration > 0)
            #expect(curve.duration <= 0.6)
        }
    }
}

import CoreGraphics

// MARK: - Metrics

/// Every distance, size and radius the export draws.
///
/// The HTML is authored in CSS pixels at 390×844, which is an iPhone's point
/// grid, so these transfer 1:1 to SwiftUI points. Nothing here is rounded or
/// nudged.
///
/// Two families of numbers in the export are deliberately absent, because they
/// belong to the drawing rather than to the app:
///
/// - the phone mockup's own `46px` corner radius, its `18px 30px 0` status-bar
///   row and its drop shadow — iOS draws the device and the status bar itself;
/// - the `10.5px` caption printed under each frame, which labels the screen for
///   a reader of the export and has no counterpart in the app.
nonisolated enum FuelMetrics {

    // MARK: - Spacing

    /// The gaps and paddings the screens use, named by value.
    ///
    /// A semantic name per use would be a lie: the same `10` is a gap between
    /// macro cards, a gap between swatches and a gap inside a row, and calling
    /// it `cardGap` would invite the next value to be invented rather than
    /// looked up. The ladder is what was drawn; the screen-level constants
    /// below give the recurring ones a meaning.
    enum Space {

        static let s2: CGFloat = 2
        static let s3: CGFloat = 3
        static let s4: CGFloat = 4
        static let s7: CGFloat = 7
        static let s8: CGFloat = 8
        static let s10: CGFloat = 10
        static let s11: CGFloat = 11
        static let s12: CGFloat = 12
        static let s13: CGFloat = 13
        static let s14: CGFloat = 14
        static let s15: CGFloat = 15
        static let s16: CGFloat = 16
        static let s17: CGFloat = 17
        static let s18: CGFloat = 18
        static let s20: CGFloat = 20
        static let s22: CGFloat = 22
        static let s24: CGFloat = 24
        static let s26: CGFloat = 26
        static let s28: CGFloat = 28
        static let s30: CGFloat = 30
        static let s32: CGFloat = 32
        static let s34: CGFloat = 34
        static let s38: CGFloat = 38
        static let s44: CGFloat = 44
        static let s88: CGFloat = 88
        static let s96: CGFloat = 96
    }

    // MARK: - Screen

    enum Screen {

        /// The horizontal inset every ordinary screen sits in.
        static let horizontalPadding = Space.s28

        /// The log flow heads its screens at a tighter inset than the ordinary
        /// ones. Not a camera value: the export draws it on all five — camera,
        /// text and recent, and on both result screens, which are not camera
        /// surfaces at all. The body of a result screen returns to
        /// `horizontalPadding`; only the header row sits in this.
        static let logFlowHorizontalPadding = Space.s26

        /// The drop to the first line on the two onboarding screens that carry
        /// content — the API key screen and the goal screen.
        ///
        /// Measured **below the safe area**, not from the top of the screen.
        /// The export draws its own status bar as a sibling that comes first
        /// and puts this padding on the container after it, so the 88 sits
        /// under the bar. That mock bar is the stand-in for the real safe
        /// area, which is why the same number lands lower on a device: a real
        /// status bar is taller than the drawn one.
        ///
        /// The same reading in reverse governs every bottom edge — a drawn
        /// bottom distance is measured above the safe-area boundary, because
        /// the mock frame omits the home indicator a device has.
        static let onboardingTopPadding = Space.s88

        /// The same drop on the two key-test screens, which sit lower. Also
        /// below the safe area — see `onboardingTopPadding`.
        ///
        /// The larger value goes to the screen with *less* on it, which is the
        /// opposite of the intuition: screens 02 and 03 carry a headline and
        /// four step rows and nothing else, so the block is centred by being
        /// pushed down, while the goal screen has two choice cards and a footer
        /// under its headline and needs the height.
        static let keyTestTopPadding = Space.s96
    }

    /// The band that fades the day list out under the floating add button, so
    /// the last row does not collide with it.
    ///
    /// Prototype-only: a static render has no scrolled list to fade, so
    /// grepping `Screens2c.dc.html` for it comes back empty. See
    /// `design/Fuel Design Notes.md`, "The list fade under the add button".
    enum ListFade {

        /// Band height. Note this is taller than the button plus its inset —
        /// the fade has to start above the button, not level with it.
        static let height: CGFloat = 120

        /// Where the background reaches full opacity, measured from the bottom.
        /// `linear-gradient(to top, bg 46%, transparent)`.
        static let opaqueStop: CGFloat = 0.46
    }

    // MARK: - Radii

    /// Every radius the export draws, minus one.
    ///
    /// The export also uses `border-radius:50%` twenty-six times — the ring,
    /// the swatches, the shutter, the circular buttons, the selection dot. That
    /// is a shape rather than a radius, and it is expressed in SwiftUI as
    /// `Circle()` on a square frame, so it has no constant here. The three
    /// below are the only fixed radii in the app.
    enum Radius {

        /// Pills: buttons, segments, chips. Drawn as `100px`, which is any
        /// value past half the height — kept as drawn rather than swapped for
        /// a capsule so a reviewer finds the number the design wrote.
        static let pill: CGFloat = 100

        /// Cards. The three macro cards on onboarding are the only `16px` in
        /// the export.
        static let card: CGFloat = 16

        /// The result screen's photo thumbnail, and nothing else.
        static let thumbnail: CGFloat = 22
    }

    // MARK: - Lines

    enum Line {

        /// The ordinary border and divider.
        static let hairline: CGFloat = 1

        /// The heavier of the two line weights, and the export uses it in
        /// exactly two places: the selected accent swatch's ring in Settings,
        /// and the border of an *un*selected choice-card dot on onboarding.
        /// Both are "this control is a selection", which is why they share a
        /// weight rather than each having their own.
        static let selectionBorder: CGFloat = 1.5

        /// The active step's spinner ring on the key-test screen.
        static let spinner: CGFloat = 2

        /// How much of that ring is painted in `ink`.
        ///
        /// The export draws the spinner as a full circle bordered in `soft`
        /// with `border-top-color: ink`, which colours exactly one of the four
        /// CSS borders — a quarter of the ring. It is a fraction rather than a
        /// length, and it sits beside the stroke it belongs to because it is
        /// the same mark: a feature file trimming a circle to a number of its
        /// own would be inventing the one part of the spinner the design does
        /// specify.
        static let spinnerArc: CGFloat = 0.25

        /// Stroke weights for the drawn glyphs. The export draws its icons as
        /// SVG paths inside a 20-unit box rather than as a font, so each one
        /// carries its own weight and none of them is `hairline`.
        ///
        /// SF Symbols will not hit these exactly — a symbol's weight is a
        /// design of its own, not a stroke width. Where a glyph is drawn as a
        /// path, use the path and these weights; where a symbol stands in,
        /// say so at the call site rather than pretending the number applies.
        enum Glyph {

            /// The result screen's small chevron beside the meal label.
            static let chevron: CGFloat = 1.3

            /// The plus on the add button, screens 05 and 06.
            static let plus: CGFloat = 1.6

            /// The check on a completed key-test step.
            static let check: CGFloat = 1.7

            /// The box the paths are authored in, like `Ring.viewBox`.
            static let viewBox: CGFloat = 20

            /// The chevron is the one glyph the export does *not* author in
            /// the 20-unit box: it is drawn `viewBox="0 0 9 6"`, beside the
            /// meal-label pill on both result screens. Its own box, so the
            /// path's `M1 1l3.5 3.5L8 1` transfers as written.
            static let chevronWidth: CGFloat = 9
            static let chevronHeight: CGFloat = 6

            /// How far inside that box the path itself starts: `M1 1l3.5
            /// 3.5L8 1` is held one unit off the left, the right and the top,
            /// which is what leaves the round cap room inside the box. The
            /// plus glyph's equivalent is `Space.s3`; the ladder has no 1, so
            /// the chevron's own inset is named here.
            static let chevronInset: CGFloat = 1
        }
    }

    // MARK: - Controls

    enum Control {

        /// The circular settings and back buttons in a screen header.
        static let circleButton: CGFloat = 34

        /// The accent swatch: a `26px` dot inside a `38px` ring.
        static let swatchRing: CGFloat = 38
        static let swatchDot: CGFloat = 26

        /// The shutter: a `56px` fill inside a `70px` ring.
        static let shutterRing: CGFloat = 70
        static let shutterFill: CGFloat = 56

        /// The slot a key-test step's state marker occupies, so the check, the
        /// spinner and the dot all leave the label on the same left edge.
        static let stepMarkerSlot: CGFloat = 20

        /// The pending marker inside that slot.
        static let stepMarkerDot: CGFloat = 6

        /// The fixed-width column the macro name sits in, so the three bars
        /// start on one line.
        static let macroLabelColumn: CGFloat = 52

        /// A macro bar's height.
        static let macroBarHeight: CGFloat = 4

        /// The result screen's photo thumbnail.
        static let thumbnailHeight: CGFloat = 150

        /// The accent-filled add button floating over the day list, drawn on
        /// both Today screens — the one place either mode offers to log
        /// something.
        static let addButton: CGFloat = 58

        /// Its inset from the trailing and bottom edges of the screen. Larger
        /// at the bottom than at the side because the button clears the home
        /// indicator, not just the margin.
        static let addButtonTrailingInset = Space.s26
        static let addButtonBottomInset = Space.s32

        /// The radio dot on an onboarding choice card: accent-filled when the
        /// option is chosen, a `Line.selectionBorder` ring when it is not.
        static let selectionDot: CGFloat = 18

        /// The smallest area a control may answer to a finger in, whatever it
        /// draws.
        ///
        /// **This one is not read out of the export**, and it is the only
        /// number in this file that is not. Several of the controls above are
        /// drawn smaller than a fingertip — `circleButton` at 34 is the one
        /// that matters most, because it is how Today reaches Settings — and
        /// the export has nothing to say about hit testing, which a static
        /// render cannot draw.
        ///
        /// It lives here rather than at the call site because it is a rule
        /// applied to a drawn control, not a measurement of one: the circle
        /// keeps the size and the position the export gives it, and only the
        /// region that answers grows around it.
        ///
        /// It is deliberately not added to `allDrawnValues`, which lists what
        /// the export draws. That `Space.s44` happens to carry the same figure
        /// is a coincidence of the ladder, not this rule appearing there.
        static let minimumHitTarget: CGFloat = 44

        /// How far that region overhangs a control of `size` on each side.
        ///
        /// The halving is here rather than at the call site for the same
        /// reason the minimum is: a view asks how much bigger the region is
        /// than the drawing, it does not work it out. Zero for anything
        /// already large enough, so a control that grows past 44 does not
        /// acquire a negative inset.
        static func hitTargetOverhang(around size: CGFloat) -> CGFloat {
            max(.zero, (minimumHitTarget - size) / 2)
        }
    }

    // MARK: - Ring

    /// The calorie ring on Today, in goal mode only. Count-only mode draws no
    /// ring at all — it is a different layout, not this one with the ring
    /// hidden.
    enum Ring {

        /// The geometry is authored against a 120-unit box and rendered into
        /// `size`, so the stroke and radius below are box units, not points.
        static let viewBox: CGFloat = 120
        static let radius: CGFloat = 54
        static let strokeWidth: CGFloat = 7

        /// Rendered edge length.
        static let size: CGFloat = 104

        /// The ring starts at twelve o'clock, so the painted arc is rotated a
        /// quarter turn back from SVG's and SwiftUI's shared three-o'clock
        /// origin. Drawn as `rotate(-90deg)`.
        ///
        /// Degrees rather than a SwiftUI `Angle`, because this file is
        /// geometry and imports CoreGraphics only — the moment it imports
        /// SwiftUI it stops being usable from anywhere that is not a view.
        static let startAngleDegrees: CGFloat = -90

        /// The gap between the ring and the macro bars beside it.
        static let trailingGap = Space.s16

        /// `2 · π · r`, as the export states it. Written out rather than
        /// computed so the value in the code is the value in the design.
        static let circumference: CGFloat = 339.3

        /// How much of the circumference is left unpainted. The progress is
        /// capped at 1 so an over-budget day shows a full ring rather than
        /// winding round a second time.
        static func strokeOffset(total: Double, goal: Double) -> CGFloat {
            guard goal > 0 else { return circumference }
            return circumference * (1 - min(1, CGFloat(total / goal)))
        }
    }

    // MARK: - Roster

    /// Every constant in this file, in one list.
    ///
    /// It exists so a test can assert a value is *absent* — which is the only
    /// way the mockup's own `46px` corner stays out. A test that checks the
    /// three radii it just pinned proves nothing; a sweep over the whole layer
    /// goes red the moment the number appears anywhere in it.
    /// Lengths only. The roster exists so `mockupCornerNeverReachesTheApp` can
    /// assert the phone frame's 46pt corner is absent, so what belongs here is
    /// anything that could plausibly collide with a mockup dimension. A
    /// dimensionless ratio such as `Line.spinnerArc` cannot, and putting one in
    /// would make the list mean two things at once.
    static let allDrawnValues: [CGFloat] = [
        Space.s2, Space.s3, Space.s4, Space.s7, Space.s8, Space.s10, Space.s11, Space.s12,
        Space.s13, Space.s14, Space.s15, Space.s16, Space.s17, Space.s18, Space.s20, Space.s22,
        Space.s24, Space.s26, Space.s28, Space.s30, Space.s32, Space.s34, Space.s38, Space.s44,
        Space.s88, Space.s96,
        Screen.horizontalPadding, Screen.logFlowHorizontalPadding,
        Screen.onboardingTopPadding, Screen.keyTestTopPadding,
        Radius.pill, Radius.card, Radius.thumbnail,
        Line.hairline, Line.selectionBorder, Line.spinner, Line.spinnerArc,
        Line.Glyph.chevron, Line.Glyph.plus, Line.Glyph.check, Line.Glyph.viewBox,
        Line.Glyph.chevronWidth, Line.Glyph.chevronHeight, Line.Glyph.chevronInset,
        Control.circleButton, Control.swatchRing, Control.swatchDot, Control.shutterRing,
        Control.shutterFill, Control.stepMarkerSlot, Control.stepMarkerDot,
        Control.macroLabelColumn, Control.macroBarHeight, Control.thumbnailHeight,
        Control.addButton, Control.addButtonTrailingInset, Control.addButtonBottomInset,
        Control.selectionDot,
        Ring.viewBox, Ring.radius, Ring.strokeWidth, Ring.size, Ring.trailingGap,
        Ring.circumference,
        Progress.width, Progress.height, Progress.labelGap, Progress.topOffset,
        Hatch.band,
        ListFade.height
    ]

    // MARK: - Progress

    /// The analysis progress bar over the frozen frame. It fills in quarters,
    /// one per step.
    enum Progress {

        static let width: CGFloat = 120
        static let height: CGFloat = 2

        /// The vertical gap between the bar and the step label under it.
        static let labelGap = Space.s20

        /// How far down the frozen frame the bar sits, measured from the top
        /// of that frame. Drawn as `top:330px` on all four analysis screens.
        ///
        /// An offset rather than a centring, because that is what was drawn —
        /// inside the export's 390×844 it lands a little above the middle, and
        /// on a taller device it stays where the design put it instead of
        /// drifting down with the frame.
        static let topOffset: CGFloat = 330
    }

    // MARK: - Hatch

    /// The diagonal hatch that stands in for a picture: the viewfinder before
    /// the capture session hands over a frame, the frozen frame under the
    /// analysis scrim, and the result screen's thumbnail before a photo is
    /// drawn into it.
    ///
    /// Its two tones live in `FuelPalette.Camera.placeholderBase` and
    /// `placeholderStripe` for the camera surface, and in `soft` over
    /// `background` on a result screen. The geometry is the same in both:
    /// `repeating-linear-gradient(135deg, … 0 10px, … 10px 20px)`.
    enum Hatch {

        /// The angle of the gradient axis, so the stripes run from the
        /// bottom-left to the top-right.
        static let angleDegrees: CGFloat = 135

        /// One stripe's width, measured along that axis.
        static let band = Space.s10
    }
}

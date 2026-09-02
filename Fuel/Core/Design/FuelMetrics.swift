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

        /// The drop from the top of the frame to the first line on the two
        /// onboarding screens that carry content — the API key screen and the
        /// goal screen.
        static let onboardingTopPadding = Space.s88

        /// The same drop on the two key-test screens, which sit lower.
        ///
        /// The larger value goes to the screen with *less* on it, which is the
        /// opposite of the intuition: screens 02 and 03 carry a headline and
        /// four step rows and nothing else, so the block is centred by being
        /// pushed down, while the goal screen has two choice cards and a footer
        /// under its headline and needs the height.
        static let keyTestTopPadding = Space.s96
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

    // MARK: - Progress

    /// The analysis progress bar over the frozen frame. It fills in quarters,
    /// one per step.
    enum Progress {

        static let width: CGFloat = 120
        static let height: CGFloat = 2

        /// The vertical gap between the bar and the step label under it.
        static let labelGap = Space.s20
    }
}

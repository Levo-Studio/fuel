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

        /// The camera surface runs its content at a slightly tighter inset than
        /// the ordinary screens, so the viewfinder gets the width.
        static let cameraHorizontalPadding = Space.s26

        /// The drop from the top of the safe area to the first line on an
        /// onboarding screen — `88px` on the key screen, `96px` on the goal
        /// screen, which carries less below it.
        static let onboardingTopPadding = Space.s88
        static let onboardingTopPaddingTall = Space.s96
    }

    // MARK: - Radii

    /// Four radii, and there are no others in the export.
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

        /// The selected accent swatch's ring.
        static let swatchSelected: CGFloat = 1.5

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

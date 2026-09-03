import SwiftUI
import UIKit

// MARK: - Typography

/// Every text style drawn in the export, and the machinery that turns one into
/// a usable `Font`.
///
/// Two families, and the split is not decorative: anything whose value changes
/// as the user logs — a total, a macro figure, a timestamp, a percentage — is
/// set in the mono face so the row does not shift width underneath it. Prose,
/// labels and buttons are the sans face.
///
/// The export's own Google Fonts import is wrong in both directions: it asks
/// for weight 700, which nothing uses, and omits 300, which is drawn five
/// times. The bundled range is 300–600 for the sans and 400 only for the mono,
/// which is what the screens actually contain.
nonisolated enum FuelTypography {

    // MARK: - Family

    enum Family: Sendable {

        /// All prose, labels and buttons. Bundled as a variable font, so the
        /// weight is set through the `wght` axis rather than by picking a
        /// separate file.
        case sans

        /// Every number, timestamp and letter-spaced uppercase eyebrow.
        /// Shipped as a single static weight, because 400 is the only one
        /// drawn.
        case mono

        /// The PostScript name, which is what `UIFontDescriptor` matches on.
        /// The `Info.plist` `UIAppFonts` entries carry no directory component
        /// because a synchronized resource folder flattens into the bundle
        /// root, but the name here is the font's own and unaffected by that.
        var postScriptName: String {
            switch self {
            case .sans: "PlusJakartaSans-Regular"
            case .mono: "DMMono-Regular"
            }
        }

        /// Only the sans face carries a `wght` axis. Asking the mono face to
        /// vary would silently do nothing, so the distinction is explicit.
        var isVariable: Bool {
            switch self {
            case .sans: true
            case .mono: false
            }
        }
    }

    // MARK: - Style

    /// One drawn text style: family, weight, size, tracking and line height,
    /// exactly as the export writes them.
    ///
    /// Sizes carry halves — 11.5, 13.5, 14.5 — because the design was drawn in
    /// CSS pixels that map 1:1 onto SwiftUI points. They are not rounding
    /// artefacts and are transferred as written.
    struct Style: Equatable, Sendable {

        let family: Family

        /// The `wght` axis value: 300, 400, 500 or 600. There is no 700
        /// anywhere in the screens.
        let weight: Double

        /// Design points.
        let size: CGFloat

        /// CSS `letter-spacing` in `em`. Converted to points against `size` by
        /// `tracking`, which is what SwiftUI's modifier expects.
        let trackingEm: CGFloat

        /// CSS `line-height` as a multiple of `size`, or `nil` where the export
        /// sets none and the font's natural leading stands.
        let lineHeightMultiple: CGFloat?

        /// `true` for the styles the export puts in `text-transform: uppercase`.
        /// Uppercasing belongs to the style rather than to the string catalog
        /// entry, so the same key can be reused elsewhere in its natural case.
        let isUppercased: Bool

        /// The Dynamic Type ramp this style scales along, or `nil` where it is
        /// pinned. See `font` for why some styles are pinned.
        let scalesRelativeTo: UIFont.TextStyle?

        init(
            _ family: Family,
            weight: Double,
            size: CGFloat,
            trackingEm: CGFloat = 0,
            lineHeightMultiple: CGFloat? = nil,
            uppercased: Bool = false,
            scalesRelativeTo: UIFont.TextStyle? = nil
        ) {
            self.family = family
            self.weight = weight
            self.size = size
            self.trackingEm = trackingEm
            self.lineHeightMultiple = lineHeightMultiple
            self.isUppercased = uppercased
            self.scalesRelativeTo = scalesRelativeTo
        }

        // MARK: Resolution

        /// The style as a `UIFont`, scaled if the style opts into Dynamic Type.
        ///
        /// Scaling is capped. The drawn layout is a fixed 390×844 frame with
        /// rows sized to their content, and letting a label grow without limit
        /// turns a two-column settings row into a wrapped mess. A cap keeps the
        /// larger accessibility sizes usable without breaking the drawing.
        var uiFont: UIFont {
            let base = FuelTypography.uiFont(family, weight: weight, size: size)
            guard let textStyle = scalesRelativeTo else { return base }
            return UIFontMetrics(forTextStyle: textStyle)
                .scaledFont(for: base, maximumPointSize: size * FuelTypography.maximumScale)
        }

        var font: Font { Font(uiFont) }

        /// Tracking in points. CSS `em` is relative to the font size, so the
        /// conversion has to happen against the *scaled* size, otherwise an
        /// eyebrow at an accessibility size keeps the tracking of the small one.
        var tracking: CGFloat { trackingEm * uiFont.pointSize }

        /// Extra space between lines, in points.
        ///
        /// SwiftUI's `lineSpacing` is additive on top of the font's own line
        /// box and cannot go below it, so the two tight multiples in the export
        /// — `74px/0.9` and `58px/0.9` — resolve to zero here. That is correct
        /// rather than a compromise: both are single-line numerals where the
        /// multiple exists to pull the CSS line box in around the digits, and
        /// SwiftUI's text layout already sits tight to the glyphs.
        var lineSpacing: CGFloat {
            guard let multiple = lineHeightMultiple else { return 0 }
            let font = uiFont
            return max(0, multiple * font.pointSize - font.lineHeight)
        }
    }

    // MARK: - Dynamic Type

    // A style carries `scalesRelativeTo` when it may grow with the user's text
    // size, and omits it when it may not. The pinned ones fall into three
    // groups, and the reason is the same each time — the export draws a fixed
    // 390×844 frame, and these particular numbers have nowhere to grow into:
    //
    // - **Large numerals.** `dayTotal` is 74pt; at the 1.4× cap it is 103.6pt
    //   and no longer fits on one line beside its `/ 2400 kcal` suffix on a
    //   390pt screen. The same holds for the result figure and the goal value.
    // - **Text inside fixed geometry.** The ring's percentage sits centred in a
    //   104pt circle, the macro names sit in a 52pt column so the three bars
    //   start on one line, and the tab labels sit in a three-column bar. All of
    //   them are sized by something other than their own text.
    // - **Tracked uppercase eyebrows and glyphs.** An eyebrow is 11.5pt with
    //   `.14em` of tracking on a single line above a headline; growing it wraps
    //   the line rather than making it more readable. The `+`, `−` and `⚙`
    //   glyphs are sized to the controls they sit in.
    //
    // Everything else — prose, list rows, buttons, captions, field labels and
    // both headline sizes — scales. A pin that is not covered by one of the
    // three groups above is a bug, not a default.

    // MARK: - Mono styles

    /// `400 74px/0.9`, tracking `-.06em`. Today's total, both modes.
    static let dayTotal = Style(.mono, weight: 400, size: 74, trackingEm: -0.06, lineHeightMultiple: 0.9)

    /// `400 58px/0.9`, tracking `-.06em`. The calorie figure on a result screen.
    static let resultCalories = Style(.mono, weight: 400, size: 58, trackingEm: -0.06, lineHeightMultiple: 0.9)

    /// `400 50px`, tracking `-.055em`. The goal value on onboarding.
    static let goalValue = Style(.mono, weight: 400, size: 50, trackingEm: -0.055)

    /// `400 22px`. The macro figures in count-only mode, which has no bars.
    static let macroValueLarge = Style(.mono, weight: 400, size: 22)

    /// `400 21px`. The macro figures on the onboarding goal cards.
    static let macroValueCard = Style(.mono, weight: 400, size: 21)

    /// `400 20px`. The macro figures on a result screen.
    static let macroValue = Style(.mono, weight: 400, size: 20)

    /// `400 18px`. The right-hand value on a Settings row.
    static let settingsValue = Style(.mono, weight: 400, size: 18)

    /// `400 17px`. The stored API key, and the percentage inside the ring.
    static let monoValue = Style(.mono, weight: 400, size: 17)

    /// `400 15px`. The calorie figure on a Recent row.
    static let listValue = Style(.mono, weight: 400, size: 15)

    /// `400 14px`. Small figures in a row.
    static let listValueSmall = Style(.mono, weight: 400, size: 14)

    /// `400 13px`. The `/ 2400 kcal` suffix beside the day total, and the
    /// `kcal logged` that replaces it in count-only mode.
    static let totalSuffix = Style(.mono, weight: 400, size: 13)

    /// `400 12px`. The `kcal` unit beside a large figure.
    static let unit = Style(.mono, weight: 400, size: 12)

    /// `400 12px`. The time range on a Settings label row — the same drawn
    /// size as `unit`, named separately because it is a line of prose the user
    /// reads rather than a unit pinned beside a large figure, and so it scales.
    static let settingsRowTime = Style(.mono, weight: 400, size: 12, scalesRelativeTo: .footnote)

    /// `400 11.5px`, tracking `.14em`, uppercase. `Step 1 of 2`, the model
    /// name above a headline, the camera sheet's cancel row.
    static let eyebrow = Style(.mono, weight: 400, size: 11.5, trackingEm: 0.14, uppercased: true)

    /// `400 11.5px`, tracking `.12em`, uppercase. The flow label at the top of
    /// a result screen — `Photo entry`, `Text entry`, `Done`.
    static let flowLabel = Style(.mono, weight: 400, size: 11.5, trackingEm: 0.12, uppercased: true)

    /// `400 11.5px`. The date above `Today`, and the model line under the key
    /// field on the first onboarding screen.
    static let meta = Style(.mono, weight: 400, size: 11.5)

    /// `400 11.5px`. The `used/goal` figure at the end of a macro bar.
    static let macroRatio = Style(.mono, weight: 400, size: 11.5)

    /// `400 11.5px/1.6`. The privacy note at the foot of Settings.
    static let monoNote = Style(
        .mono,
        weight: 400,
        size: 11.5,
        lineHeightMultiple: 1.6,
        scalesRelativeTo: .footnote
    )

    /// `400 11px`. `08:14 · Photo` under an entry name.
    static let timestamp = Style(.mono, weight: 400, size: 11)

    /// `400 11px`. The `P 32 · C 48 · F 9` line on a Recent row.
    static let macroSummary = Style(.mono, weight: 400, size: 11)

    /// `400 11px`, tracking `.1em`. The `CANCEL` row under the analysis
    /// progress bar. Drawn already uppercase, so the style does not transform.
    static let overlayAction = Style(.mono, weight: 400, size: 11, trackingEm: 0.1)

    /// `400 10.5px`, tracking `.1em`. The `CAPTURED PHOTO` label over the
    /// result thumbnail. Drawn already uppercase.
    static let overlayCaption = Style(.mono, weight: 400, size: 10.5, trackingEm: 0.1)

    // MARK: - Sans styles

    /// `600 34px/1.14`, tracking `-.03em`. The headline on an onboarding step.
    ///
    /// Scales despite being the largest sans size: it owns its line, already
    /// wraps in the design, and 34 × 1.4 = 47.6pt still sits inside the 334pt
    /// the screen's 28pt margins leave.
    static let display = Style(
        .sans,
        weight: 600,
        size: 34,
        trackingEm: -0.03,
        lineHeightMultiple: 1.14,
        scalesRelativeTo: .largeTitle
    )

    /// `600 30px/1.16`, tracking `-.03em`. The headline on a key-test screen,
    /// one step down because that screen carries a step list underneath it.
    ///
    /// Scales for the same reason as `display`, and would be the odd one out if
    /// it did not: it is the same headline one size smaller, on a screen with
    /// more room under it, so anything `display` can absorb this can.
    static let displaySmall = Style(
        .sans,
        weight: 600,
        size: 30,
        trackingEm: -0.03,
        lineHeightMultiple: 1.16,
        scalesRelativeTo: .largeTitle
    )

    /// `600 25px`, tracking `-.025em`. `Today`, `Settings`.
    ///
    /// Scales for the same reason as `display` — it is a full-width heading
    /// with only a circular button beside it, which is fixed and does not
    /// compete for the width.
    static let screenTitle = Style(
        .sans,
        weight: 600,
        size: 25,
        trackingEm: -0.025,
        scalesRelativeTo: .title1
    )

    /// `600 22px`, tracking `-.02em`. The title of a sheet over the camera.
    static let sheetTitle = Style(.sans, weight: 600, size: 22, trackingEm: -0.02)

    /// `300 22px`. The `+` on a Recent row, and the only place weight 300 is
    /// drawn — five times, all of them this glyph.
    static let addGlyph = Style(.sans, weight: 300, size: 22)

    /// `400 19px/1.5`. What the user typed in the text-entry field.
    static let textEntry = Style(.sans, weight: 400, size: 19, lineHeightMultiple: 1.5, scalesRelativeTo: .body)

    /// `600 18px`. The current analysis step over the frozen frame.
    static let analysisStep = Style(.sans, weight: 600, size: 18, scalesRelativeTo: .headline)

    /// `600 17px`. The title of an onboarding choice card.
    static let optionTitle = Style(.sans, weight: 600, size: 17, scalesRelativeTo: .headline)

    /// `600 15px`. The label inside a filled or outlined button.
    static let buttonLabel = Style(.sans, weight: 600, size: 15, scalesRelativeTo: .body)

    /// `500 15px`. A key-test step that is done or running, and the name on a
    /// Recent row.
    static let listTitle = Style(.sans, weight: 500, size: 15, scalesRelativeTo: .body)

    /// `400 15px`. A key-test step still pending.
    static let listTitlePending = Style(.sans, weight: 400, size: 15, scalesRelativeTo: .body)

    /// `400 15px/1.5`. Body prose that wraps.
    static let body = Style(.sans, weight: 400, size: 15, lineHeightMultiple: 1.5, scalesRelativeTo: .body)

    /// `500 14.5px`. The meal name on a day-list row.
    static let entryTitle = Style(.sans, weight: 500, size: 14.5, scalesRelativeTo: .body)

    /// `500 14px`. A recognised item's name.
    static let itemTitle = Style(.sans, weight: 500, size: 14, scalesRelativeTo: .body)

    /// `600 14px`. The `New` chip on a Recent row.
    static let chipLabel = Style(.sans, weight: 600, size: 14)

    /// `400 14px`. The gear and the gallery glyph.
    static let iconGlyph = Style(.sans, weight: 400, size: 14)

    /// `400 13.5px/1.6`. The lead paragraph under an onboarding headline.
    static let lead = Style(.sans, weight: 400, size: 13.5, lineHeightMultiple: 1.6, scalesRelativeTo: .subheadline)

    /// `500 13.5px`. The meal name on a Settings clock row.
    static let settingsRowLabel = Style(.sans, weight: 500, size: 13.5, scalesRelativeTo: .subheadline)

    /// `600 13px`. A segment label in a two-segment control, and the mock
    /// status bar's clock.
    static let segmentLabel = Style(.sans, weight: 600, size: 13)

    /// `400 13px`. The subtitle under an onboarding choice card.
    static let caption = Style(.sans, weight: 400, size: 13, scalesRelativeTo: .footnote)

    /// `400 12.5px`. A one-line hint under a sheet title.
    static let hint = Style(.sans, weight: 400, size: 12.5, scalesRelativeTo: .footnote)

    /// `400 12.5px/1.55`. The same hint where it wraps.
    static let hintWrapping = Style(
        .sans,
        weight: 400,
        size: 12.5,
        lineHeightMultiple: 1.55,
        scalesRelativeTo: .footnote
    )

    /// `400 12px`. A footnote under a field or a card.
    static let footnote = Style(.sans, weight: 400, size: 12, scalesRelativeTo: .footnote)

    /// `600 12px`. The `Re-check` action beside the key row.
    static let inlineAction = Style(.sans, weight: 600, size: 12, scalesRelativeTo: .footnote)

    /// `600 11.5px`, tracking `.08em`, uppercase. A field label, and the meal
    /// heading over a group in the day list.
    static let sectionLabel = Style(.sans, weight: 600, size: 11.5, trackingEm: 0.08, uppercased: true)

    /// `600 11.5px`. A tab label in the three-tab log bar, and the favourite
    /// toggle on a result screen.
    static let tabLabel = Style(.sans, weight: 600, size: 11.5)

    /// `500 11px`. The macro name beside a bar.
    static let macroLabel = Style(.sans, weight: 500, size: 11)

    /// `500 10.5px`. The macro name on a card or a result screen.
    static let macroLabelSmall = Style(.sans, weight: 500, size: 10.5)

    /// `500 10px`. The name under an accent swatch.
    static let swatchLabel = Style(.sans, weight: 500, size: 10)

    // MARK: - Roster

    /// Every style above, in one list.
    ///
    /// It exists so a test can sweep the whole set — a style added with a
    /// weight the bundle does not carry would otherwise fall back to a
    /// synthesised face and look merely slightly wrong.
    static let allDrawnStyles: [Style] = [
        dayTotal, resultCalories, goalValue, macroValueLarge, macroValueCard, macroValue,
        settingsValue, monoValue, listValue, listValueSmall, totalSuffix, unit, eyebrow,
        settingsRowTime,
        flowLabel, meta, macroRatio, monoNote, timestamp, macroSummary, overlayAction,
        overlayCaption,
        display, displaySmall, screenTitle, sheetTitle, addGlyph, textEntry, analysisStep,
        optionTitle, buttonLabel, listTitle, listTitlePending, body, entryTitle,
        itemTitle, chipLabel, iconGlyph, lead, settingsRowLabel, segmentLabel, caption, hint,
        hintWrapping, footnote, inlineAction, sectionLabel, tabLabel, macroLabel,
        macroLabelSmall, swatchLabel
    ]

    // MARK: - Font construction

    /// How far a scaling style may grow. Chosen so the largest accessibility
    /// size still fits the drawn rows; beyond it the layout the design
    /// specifies stops holding.
    ///
    /// Not private, because copy that has to survive the cap is checked against
    /// it: the rotating examples on screen 12 are drawn in a prompt, which is
    /// one line and truncates rather than wrapping, so their width is a rule
    /// held to this number rather than to a restatement of it.
    static let maximumScale: CGFloat = 1.4

    /// The `wght` OpenType variation axis, as the four-character tag `wght`
    /// read as a big-endian integer — the form `kCTFontVariationAttribute`
    /// expects.
    private static let weightAxis = 0x77676874

    /// Builds the font for a family and weight.
    ///
    /// The weight is set through the variation axis rather than through
    /// `UIFontDescriptor`'s weight *trait*. The trait route looks simpler and
    /// is wrong here: it matches against the variable font's named instances by
    /// nearest weight trait, and `UIFont.Weight.light` lands on ExtraLight
    /// (200) rather than on the Light (300) the design draws. Naming the axis
    /// value asks for the weight that was drawn and gets it.
    private static func uiFont(_ family: Family, weight: Double, size: CGFloat) -> UIFont {
        var attributes: [UIFontDescriptor.AttributeName: Any] = [.name: family.postScriptName]
        if family.isVariable {
            let variationKey = kCTFontVariationAttribute as UIFontDescriptor.AttributeName
            attributes[variationKey] = [weightAxis: weight]
        }
        return UIFont(descriptor: UIFontDescriptor(fontAttributes: attributes), size: size)
    }
}

// MARK: - Applying a style

extension View {

    /// Applies a drawn text style whole — font, tracking and line spacing
    /// together.
    ///
    /// Three modifiers rather than one would mean three chances for a call site
    /// to take the font and forget the tracking, which on a `.14em` eyebrow is
    /// the difference between the drawn label and a different one.
    func fuelStyle(_ style: FuelTypography.Style) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
            .textCase(style.isUppercased ? .uppercase : nil)
    }
}

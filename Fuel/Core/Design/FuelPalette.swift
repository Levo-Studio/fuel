import SwiftUI

// MARK: - Colour value

/// A colour as four sRGB components, kept as `Double` rather than as a `Color`.
///
/// `Color` cannot be compared or inspected, which would make the oklch
/// conversion below untestable. Everything in this file is therefore built as
/// an `FuelRGBA` first and turned into a `Color` only at the call site.
nonisolated struct FuelRGBA: Equatable, Sendable {

    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double

    /// `false` when the colour the design asked for cannot be shown in sRGB.
    /// The component values are stored unclamped so a reviewer can see how far
    /// out the colour sits; only `color` clamps.
    let isInGamut: Bool

    init(red: Double, green: Double, blue: Double, opacity: Double = 1, isInGamut: Bool = true) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
        self.isInGamut = isInGamut
    }

    /// The design export writes its non-oklch colours as hex and as
    /// `rgba(r,g,b,a)`. Both arrive here so the literal in the code can be read
    /// straight against the palette table in `Fuel Design Notes.md`.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    var color: Color {
        Color(
            .sRGB,
            red: min(max(red, 0), 1),
            green: min(max(green, 0), 1),
            blue: min(max(blue, 0), 1),
            opacity: opacity
        )
    }
}

// MARK: - oklch

nonisolated extension FuelRGBA {

    /// Converts an `oklch(L C H)` triple to sRGB.
    ///
    /// The design was authored in oklch because it keeps the five accents at a
    /// matched lightness across hues, which is the whole reason they read as
    /// one family. iOS has no oklch initialiser, so the conversion happens
    /// here — once, in the one place colour literals are allowed — rather than
    /// as pre-baked hex values whose provenance nobody can check. Every call
    /// site below carries the resulting hex in a comment for exactly that
    /// check.
    ///
    /// The chain is oklch → oklab → LMS → linear sRGB → sRGB, using Björn
    /// Ottosson's published matrices. Gamut is judged on the *linear* values,
    /// before the transfer function, because that is where a negative channel
    /// actually means "outside sRGB".
    ///
    /// - Parameters:
    ///   - l: Perceptual lightness, 0…1.
    ///   - c: Chroma, unbounded in principle.
    ///   - h: Hue angle in degrees.
    static func oklch(_ l: Double, _ c: Double, _ h: Double, opacity: Double = 1) -> FuelRGBA {
        let radians = h * .pi / 180
        let a = c * cos(radians)
        let b = c * sin(radians)

        let longRoot = l + 0.3963377774 * a + 0.2158037573 * b
        let mediumRoot = l - 0.1055613458 * a - 0.0638541728 * b
        let shortRoot = l - 0.0894841775 * a - 1.2914855480 * b

        let long = longRoot * longRoot * longRoot
        let medium = mediumRoot * mediumRoot * mediumRoot
        let short = shortRoot * shortRoot * shortRoot

        let linearRed = 4.0767416621 * long - 3.3077115913 * medium + 0.2309699292 * short
        let linearGreen = -1.2684380046 * long + 2.6097574011 * medium - 0.3413193965 * short
        let linearBlue = -0.0041960863 * long - 0.7034186147 * medium + 1.7076147010 * short

        // A hair of tolerance, because the matrices are rounded decimals and a
        // colour that lands on the gamut boundary should not be reported as
        // outside it.
        let tolerance = 0.0005
        let inGamut = [linearRed, linearGreen, linearBlue]
            .allSatisfy { $0 >= -tolerance && $0 <= 1 + tolerance }

        return FuelRGBA(
            red: encodeSRGB(linearRed),
            green: encodeSRGB(linearGreen),
            blue: encodeSRGB(linearBlue),
            opacity: opacity,
            isInGamut: inGamut
        )
    }

    /// The sRGB transfer function, applied symmetrically around zero so that an
    /// out-of-gamut negative channel keeps its sign instead of folding into a
    /// positive value and quietly becoming a different colour.
    private static func encodeSRGB(_ value: Double) -> Double {
        let magnitude = abs(value)
        let encoded = magnitude <= 0.0031308
            ? 12.92 * magnitude
            : 1.055 * pow(magnitude, 1 / 2.4) - 0.055
        return value < 0 ? -encoded : encoded
    }
}

// MARK: - Theme

/// The two appearances Fuel offers.
///
/// There is deliberately no `system` case. Settings draws a **two**-segment
/// control, Light and Dark, so the app's appearance is a stored choice and
/// never follows the OS. Adding a third case would put a segment on screen 16
/// that was never designed.
nonisolated enum FuelTheme: String, CaseIterable, Identifiable, Sendable {

    case light
    case dark

    var id: String { rawValue }

    /// What the SwiftUI hierarchy is forced to, since the theme is a choice
    /// rather than an inherited environment value.
    var colorScheme: ColorScheme {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }
}

// MARK: - Accent

/// The five accents, in the order Settings draws them. `mono` is the default.
///
/// The accent drives the ring, the macro bars, filled buttons and selection —
/// nothing else. `onColor` is the ink that sits *on* a filled accent surface
/// and is picked per accent rather than derived, because the design chose a
/// tinted near-black for each dark-mode accent instead of a single flat one.
nonisolated enum FuelAccent: String, CaseIterable, Identifiable, Sendable {

    case mono
    case blue
    case green
    case sand
    case lilac

    var id: String { rawValue }

    func color(for theme: FuelTheme) -> Color { rgba(for: theme).color }

    func onColor(for theme: FuelTheme) -> Color { onRGBA(for: theme).color }

    /// Exposed unresolved so the conversion stays checkable in a test; views
    /// use `color(for:)`.
    func rgba(for theme: FuelTheme) -> FuelRGBA {
        switch (self, theme) {
        case (.mono, .dark): FuelRGBA(hex: 0xFAFAFA)
        case (.mono, .light): FuelRGBA(hex: 0x121212)
        case (.blue, .dark): .oklch(0.72, 0.13, 250)   // oklch(0.72 0.13 250) -> #60AAF3
        case (.blue, .light): .oklch(0.52, 0.15, 256)  // oklch(0.52 0.15 256) -> #2368BD
        case (.green, .dark): .oklch(0.76, 0.13, 160)  // oklch(0.76 0.13 160) -> #5ACA94
        // oklch(0.52 0.13 160) -> #007F4E, and this one sits *outside* sRGB:
        // linear red comes out at about -0.014. `color` clamps that channel to
        // zero, which is the closest sRGB can get. The shift is not visible
        // against the design render, which was itself produced by a browser
        // doing the same clamp — but it is a clamp, not an exact match, and
        // `isInGamut` reports it rather than hiding it.
        case (.green, .light): .oklch(0.52, 0.13, 160)
        case (.sand, .dark): .oklch(0.82, 0.11, 72)    // oklch(0.82 0.11 72)  -> #F0B871
        case (.sand, .light): .oklch(0.58, 0.12, 62)   // oklch(0.58 0.12 62)  -> #AC6820
        case (.lilac, .dark): .oklch(0.76, 0.12, 300)  // oklch(0.76 0.12 300) -> #BD9FF2
        case (.lilac, .light): .oklch(0.53, 0.15, 300) // oklch(0.53 0.15 300) -> #7A53B4
        }
    }

    func onRGBA(for theme: FuelTheme) -> FuelRGBA {
        switch (self, theme) {
        case (.mono, .dark): FuelRGBA(hex: 0x111213)
        case (.mono, .light): FuelRGBA(hex: 0xFAF9F8)
        case (.blue, .dark): FuelRGBA(hex: 0x0A1220)
        case (.green, .dark): FuelRGBA(hex: 0x06140E)
        case (.sand, .dark): FuelRGBA(hex: 0x1A1206)
        case (.lilac, .dark): FuelRGBA(hex: 0x150A1C)
        // Every light-mode accent is dark enough to take plain white ink, so
        // the four share one value where the dark ones each have their own.
        case (.blue, .light), (.green, .light), (.sand, .light), (.lilac, .light):
            FuelRGBA(hex: 0xFFFFFF)
        }
    }
}

// MARK: - Palette

/// Every colour in Fuel, resolved for one theme and one accent.
///
/// A view holds a `FuelPalette` rather than reaching for a global, so a
/// preview can render any theme/accent pair without touching app state.
nonisolated struct FuelPalette: Sendable {

    let theme: FuelTheme
    let accent: FuelAccent

    init(theme: FuelTheme, accent: FuelAccent = .mono) {
        self.theme = theme
        self.accent = accent
    }

    // MARK: Surfaces and ink

    /// The page behind everything.
    var background: Color { pick(dark: FuelRGBA(hex: 0x111213), light: FuelRGBA(hex: 0xFAF9F8)).color }

    /// Raised surfaces — cards, sheets, the tab bar.
    var surface: Color { pick(dark: FuelRGBA(hex: 0x1A1B1D), light: FuelRGBA(hex: 0xFFFFFF)).color }

    /// Primary text and iconography.
    var ink: Color { pick(dark: FuelRGBA(hex: 0xFAFAFA), light: FuelRGBA(hex: 0x121212)).color }

    /// Secondary text: units, timestamps, eyebrows, inactive step labels.
    var muted: Color {
        pick(
            dark: FuelRGBA(hex: 0xFAFAFA, opacity: 0.45),
            light: FuelRGBA(hex: 0x121212, opacity: 0.45)
        ).color
    }

    // MARK: Lines and fills

    /// The ordinary 1px border and divider.
    var hair: Color {
        pick(
            dark: FuelRGBA(hex: 0xFAFAFA, opacity: 0.14),
            light: FuelRGBA(hex: 0x121212, opacity: 0.12)
        ).color
    }

    /// The stronger line — the unselected accent swatch ring.
    var hair2: Color {
        pick(
            dark: FuelRGBA(hex: 0xFAFAFA, opacity: 0.3),
            light: FuelRGBA(hex: 0x121212, opacity: 0.25)
        ).color
    }

    /// The faintest line, used between rows inside a card where a full `hair`
    /// would read as a break rather than a separation.
    var hairSoft: Color {
        pick(
            dark: FuelRGBA(hex: 0xFAFAFA, opacity: 0.07),
            light: FuelRGBA(hex: 0x121212, opacity: 0.07)
        ).color
    }

    /// A filled tint rather than a line: the ring's unspent track and the macro
    /// bars' track.
    var soft: Color {
        pick(
            dark: FuelRGBA(hex: 0xFAFAFA, opacity: 0.12),
            light: FuelRGBA(hex: 0x121212, opacity: 0.09)
        ).color
    }

    // MARK: Accent

    var accentColor: Color { accent.color(for: theme) }

    /// Ink for text and glyphs sitting on `accentColor`.
    var onAccent: Color { accent.onColor(for: theme) }

    // MARK: Status

    /// The failed-key note in Settings. Not an accent — it never follows the
    /// user's accent choice, because an error that changes colour with a
    /// preference stops reading as an error.
    var error: Color { Self.errorRGBA.color }

    static let errorRGBA = FuelRGBA.oklch(0.62, 0.17, 25) // oklch(0.62 0.17 25) -> #DA534F

    // MARK: Camera

    /// The camera surface, and it is the same near-black in **both** themes.
    ///
    /// This is deliberate and Settings says so in words under the Light/Dark
    /// control: a viewfinder that turns white in light mode would wash out the
    /// preview it exists to show, and the chrome around it has to stay legible
    /// over whatever the lens is pointed at. So the camera screen is its own
    /// little dark region inside a light app — and everything drawn on it uses
    /// the fixed light-on-dark inks below rather than the theme's ink, for the
    /// same reason.
    var camera: Color { pick(dark: FuelRGBA(hex: 0x090A0A), light: FuelRGBA(hex: 0x0D0D0E)).color }

    /// Ink on the camera surface. Fixed, not theme-dependent — see `camera`.
    enum Camera {

        /// Titles and the shutter fill.
        static let ink = FuelRGBA(hex: 0xFAFAFA).color

        /// The `+` glyph on the Recent rows and the cancel row above the tabs.
        static let inkSecondary = FuelRGBA(hex: 0xFAFAFA, opacity: 0.5).color

        /// Helper prose under a camera-sheet title.
        static let muted = FuelRGBA(hex: 0xFAFAFA, opacity: 0.45).color

        /// The `CANCEL` label over the analysis scrim.
        static let dim = FuelRGBA(hex: 0xFAFAFA, opacity: 0.4).color

        /// Unselected labels in the three-tab bar.
        static let inactive = FuelRGBA(hex: 0xFAFAFA, opacity: 0.38).color

        /// The shutter button's outer ring.
        static let ring = FuelRGBA(hex: 0xFAFAFA, opacity: 0.4).color

        /// Borders on the camera surface.
        static let hair = FuelRGBA(hex: 0xFAFAFA, opacity: 0.24).color

        /// The analysis progress bar's track.
        static let hairSoft = FuelRGBA(hex: 0xFAFAFA, opacity: 0.14).color

        /// The rule above the tab bar.
        static let divider = FuelRGBA(hex: 0xFAFAFA, opacity: 0.1).color

        /// Laid over the frozen frame while the model works, so the progress
        /// bar and step label stay readable on any photo.
        static let scrim = FuelRGBA(hex: 0x090A0A, opacity: 0.72).color

        /// The two tones of the diagonal hatch that stands in for the live
        /// preview in the export. They are the placeholder shown before the
        /// capture session hands over a frame, not decoration on top of one.
        static let placeholderBase = FuelRGBA(hex: 0x111213).color
        static let placeholderStripe = FuelRGBA(hex: 0x17181A).color
    }

    // MARK: Resolution

    private func pick(dark: FuelRGBA, light: FuelRGBA) -> FuelRGBA {
        switch theme {
        case .dark: dark
        case .light: light
        }
    }

}

// MARK: - Environment

private struct FuelPaletteKey: EnvironmentKey {

    /// Dark with the mono accent is what the app opens on before a preference
    /// has been read, and it is the pairing the export treats as the default.
    static let defaultValue = FuelPalette(theme: .dark, accent: .mono)
}

extension EnvironmentValues {

    var fuelPalette: FuelPalette {
        get { self[FuelPaletteKey.self] }
        set { self[FuelPaletteKey.self] = newValue }
    }
}

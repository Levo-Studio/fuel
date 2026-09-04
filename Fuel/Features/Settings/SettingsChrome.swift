import SwiftUI

// MARK: - Hairline

/// The 1px rule the export draws under a section heading and between rows.
///
/// A `Divider` is not used: it carries its own inset and its own system colour,
/// and both would have to be argued back out of it. A filled rectangle is the
/// drawn shape.
struct SettingsHairline: View {

    let color: Color

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: FuelMetrics.Line.hairline)
    }
}

// MARK: - Screen header

/// The `Settings` title with the `Done` control beside it, drawn identically on
/// screens 16 and 17.
struct SettingsHeader: View {

    @Environment(\.fuelPalette) private var palette

    let done: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Text("settings.title")
                .fuelStyle(FuelTypography.screenTitle)
                .foregroundStyle(palette.ink)

            Spacer(minLength: FuelMetrics.Space.s12)

            Button(action: done) {
                Text("settings.done")
                    .fuelStyle(FuelTypography.flowLabel)
                    .foregroundStyle(palette.muted)
            }
            .buttonStyle(FuelPressButtonStyle())
        }
        .padding(.top, FuelMetrics.Space.s26)
    }
}

// MARK: - Section

/// An uppercase section heading with its hairline, and whatever the section
/// draws under it.
///
/// Both Settings screens are built from this: screen 16's three sections and
/// screen 17's two use the same heading, the same rule and the same top gap
/// ladder, so the chrome is one type and the sections are the things that
/// differ.
struct SettingsSection<Content: View>: View {

    @Environment(\.fuelPalette) private var palette

    let titleKey: LocalizedStringKey

    /// The gap above the section. The export draws `22` above the first section
    /// on screen 16 and `20` above every other section on both screens, so the
    /// value is passed rather than assumed.
    var topSpacing: CGFloat = FuelMetrics.Space.s20

    /// The gap between the heading and its rule. `12` everywhere on screen 16;
    /// screen 17's label section draws `10`.
    var headingSpacing: CGFloat = FuelMetrics.Space.s12

    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titleKey)
                .fuelStyle(FuelTypography.sectionLabel)
                .foregroundStyle(palette.muted)
                .padding(.bottom, headingSpacing)

            SettingsHairline(color: palette.hair)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, topSpacing)
    }
}

// MARK: - Segmented control

/// Which surface a `SettingsSegmentedControl` stands on, and therefore where
/// its four colours are read from.
///
/// The drawing is the same either way — the same pill, the same padding, the
/// same fill-and-outline pair. Only the inks differ, which is why this is a
/// surface rather than a second control.
nonisolated enum FuelSegmentedSurface {

    /// The page, in whichever theme is set. Both Settings screens.
    case theme

    /// The log flow's own surface, which is the same near-black in **both**
    /// themes — so everything on it is lettered in the fixed
    /// `FuelPalette.Camera` inks rather than the theme's.
    ///
    /// A filled control there takes those inks too, and not the accent. The one
    /// the export draws on this surface is screen 12's `Analyse` button, written
    /// `background:#fafafa;color:#111213` as a literal, unchanged across all
    /// four theme/accent frames the wrapper renders — so the accent does not
    /// reach this surface. Both alternatives would also be unreadable: the
    /// theme's `ink` is `#121212` in light mode, and the `mono` accent, which is
    /// the default, is the same value, so either would put a near-black segment
    /// on a near-black page.
    case camera
}

/// The two-segment pill control: `Claude / Mistral`, `Light / Dark`, on screen
/// 17 `With a goal / Count only`, and — on the camera surface — the Recent
/// tab's `Recent / Favourites`.
///
/// On the page, the selected segment is filled with the accent and takes the
/// accent's own on-colour, and the unselected one is a `hair` outline. See
/// `FuelSegmentedSurface` for what the camera surface substitutes and why.
///
/// The padding is a parameter because the export draws two: `11` for the
/// provider control and `12` for every other one. That is a two-point
/// difference in height and it is what was drawn.
struct SettingsSegmentedControl<Value: Hashable>: View {

    @Environment(\.fuelPalette) private var palette

    let options: [Value]
    let titleKey: (Value) -> LocalizedStringKey
    @Binding var selection: Value
    var padding: CGFloat = FuelMetrics.Space.s12

    /// Defaulted to the page, which is what all three Settings call sites draw.
    var surface: FuelSegmentedSurface = .theme

    var body: some View {
        HStack(spacing: FuelMetrics.Space.s8) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .fuelAnimation(FuelMotion.standard, value: selection)
    }

    private func segment(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            selection = option
        } label: {
            Text(titleKey(option))
                .fuelStyle(FuelTypography.segmentLabel)
                .foregroundStyle(isSelected ? selectedInk : ink)
                .frame(maxWidth: .infinity)
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .fill(isSelected ? fill : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .strokeBorder(
                            isSelected ? fill : outline,
                            lineWidth: FuelMetrics.Line.hairline
                        )
                )
                .overlay { hitTarget }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Inks

    /// The label of an unselected segment.
    private var ink: Color {
        switch surface {
        case .theme: palette.ink
        case .camera: FuelPalette.Camera.ink
        }
    }

    /// The outline of an unselected segment.
    private var outline: Color {
        switch surface {
        case .theme: palette.hair
        case .camera: FuelPalette.Camera.hair
        }
    }

    /// What the selected segment is filled and bordered with.
    private var fill: Color {
        switch surface {
        case .theme: palette.accentColor
        case .camera: FuelPalette.Camera.ink
        }
    }

    /// The label sitting on that fill.
    private var selectedInk: Color {
        switch surface {
        case .theme: palette.onAccent
        case .camera: FuelPalette.Camera.onInk
        }
    }

    // MARK: - Hit target

    /// The region a segment answers a finger in, which is taller than the one
    /// it draws.
    ///
    /// A segment is a 13pt label between the export's 11 or 12 points of
    /// padding — 38.67 or 40.67 tall drawn, either way short of the 44 a
    /// fingertip needs. An overlay is offered its host's size and may take a
    /// larger one without the host growing, so asking for `minimumHitTarget`
    /// here widens the region symmetrically around the pill and leaves the
    /// drawn box, and everything laid out around it, where the export puts
    /// them. It replaces the pill's own content shape rather than joining it,
    /// because the taller pill contains the drawn one.
    ///
    /// `Control.hitTargetOverhang(around:)` — which Today's gear and the
    /// camera's gallery control use — wants a drawn size to subtract from, and
    /// both of those pass `circleButton`, a number the design layer states. A
    /// segment's height is a line height the text engine resolves at render
    /// time, so there is nothing to hand it that would not first have to be
    /// invented. Asking for the minimum reaches the same geometry without the
    /// invention.
    ///
    /// The growth is vertical only, and it belongs to the segment rather than
    /// to the control, because a segment is what a tap selects. Each one is
    /// already far wider than a finger, so nothing needs to grow sideways —
    /// which is what keeps the export's 8pt gutter out of it. The two regions
    /// stay disjoint in x and cannot overlap, and a tap between the options
    /// still selects neither of them. Grown sideways they would meet inside
    /// that gutter, and a tap aimed at the space between two options would go
    /// to whichever region is hit-tested first rather than to the one the user
    /// was pointing at.
    private var hitTarget: some View {
        Color.clear
            .frame(minHeight: FuelMetrics.Control.minimumHitTarget)
            .contentShape(RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill))
    }
}

// MARK: - Row

/// A label on the left, something on the right, and the faint rule the export
/// draws under most of them.
///
/// The paddings are asymmetric on the drawn rows — `14` above and `10` below
/// the key row, `10` on both sides of the test row — so they are passed rather
/// than folded into a single value.
struct SettingsRow<Trailing: View>: View {

    @Environment(\.fuelPalette) private var palette

    var topPadding: CGFloat = FuelMetrics.Space.s12
    var bottomPadding: CGFloat = FuelMetrics.Space.s12

    /// `false` for the last row of a section, which the export leaves open.
    var showsHairline: Bool = true

    @ViewBuilder let content: Trailing

    var body: some View {
        VStack(spacing: 0) {
            // Spacing zero, not the default. Every gap inside a row is stated
            // by the call site — a `Spacer(minLength:)` between a label and its
            // value, a padding between two actions — and SwiftUI's default
            // spacing would be added on top of each of them, so a stated 8
            // would draw as roughly 16 and no call site could say what it had
            // asked for.
            HStack(alignment: .center, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .padding(.top, topPadding)
            .padding(.bottom, bottomPadding)

            if showsHairline {
                SettingsHairline(color: palette.hairSoft)
            }
        }
    }
}

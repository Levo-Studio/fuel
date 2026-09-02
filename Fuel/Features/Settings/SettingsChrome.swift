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
            .buttonStyle(.plain)
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

/// The two-segment pill control: `Claude / Mistral`, `Light / Dark`, and on
/// screen 17 `With a goal / Count only`.
///
/// The selected segment is filled with the accent and takes the accent's own
/// on-colour; the unselected one is a `hair` outline over the page.
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
                .foregroundStyle(isSelected ? palette.onAccent : palette.ink)
                .frame(maxWidth: .infinity)
                .padding(padding)
                .background(
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .fill(isSelected ? palette.accentColor : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill)
                        .strokeBorder(
                            isSelected ? palette.accentColor : palette.hair,
                            lineWidth: FuelMetrics.Line.hairline
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: FuelMetrics.Radius.pill))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
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
            HStack(alignment: .center) {
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

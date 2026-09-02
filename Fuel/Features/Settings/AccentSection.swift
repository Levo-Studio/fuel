import SwiftUI

// MARK: - Accent section

/// The five swatches, in the order the export draws them: Mono, Blue, Green,
/// Sand, Lilac.
struct AccentSection: View {

    @Bindable var preferences: SettingsPreferences

    var body: some View {
        SettingsSection(titleKey: "settings.section.accent") {
            HStack(spacing: FuelMetrics.Space.s14) {
                ForEach(FuelAccent.allCases) { accent in
                    AccentSwatch(accent: accent, selection: $preferences.accent)
                }
            }
            .padding(.top, FuelMetrics.Space.s18)
            .fuelAnimation(FuelMotion.standard, value: preferences.accent)
        }
    }
}

// MARK: - Swatch

/// A 26pt dot inside a 38pt ring, with its name underneath.
private struct AccentSwatch: View {

    @Environment(\.fuelPalette) private var palette

    let accent: FuelAccent
    @Binding var selection: FuelAccent

    private var isSelected: Bool { accent == selection }

    var body: some View {
        Button {
            selection = accent
        } label: {
            VStack(spacing: FuelMetrics.Space.s7) {
                ring
                Text(accent.settingsSwatchTitle)
                    .fuelStyle(FuelTypography.swatchLabel)
                    .foregroundStyle(palette.muted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The dot carries the swatch's *own* accent rather than the palette's, so
    /// the row shows five colours to choose from rather than five copies of the
    /// current one. The theme is the palette's, because an accent's colour is
    /// different in light and dark.
    private var ring: some View {
        Circle()
            .fill(accent.color(for: palette.theme))
            .frame(width: FuelMetrics.Control.swatchDot, height: FuelMetrics.Control.swatchDot)
            .frame(width: FuelMetrics.Control.swatchRing, height: FuelMetrics.Control.swatchRing)
            // The export draws the ring as `box-shadow: 0 0 0 Npx`, which sits
            // *outside* the 38px box and takes no layout space — so it is an
            // overlay inset by half its width rather than a border, and the
            // 14pt gap stays a gap between two 38pt boxes.
            //
            // The unselected ring is `hair` at 1px, not `hair2`. `hair2` is
            // drawn exactly once in the whole export and it is onboarding's
            // choice-card dot.
            .overlay {
                Circle()
                    .inset(by: -ringWidth / 2)
                    .stroke(
                        isSelected ? palette.ink : palette.hair,
                        lineWidth: ringWidth
                    )
            }
    }

    private var ringWidth: CGFloat {
        isSelected ? FuelMetrics.Line.selectionBorder : FuelMetrics.Line.hairline
    }
}

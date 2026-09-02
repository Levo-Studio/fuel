import SwiftUI

// MARK: - Appearance section

/// Light or Dark, and the line saying the camera is neither.
///
/// There is no `System` segment. The export draws a two-segment control, so the
/// appearance is a stored choice and never follows the OS.
struct AppearanceSection: View {

    @Environment(\.fuelPalette) private var palette

    @Bindable var preferences: SettingsPreferences

    var body: some View {
        SettingsSection(titleKey: "settings.section.appearance") {
            SettingsSegmentedControl(
                options: FuelTheme.allCases,
                titleKey: \.settingsSegmentTitle,
                selection: $preferences.theme
            )
            .padding(.top, FuelMetrics.Space.s16)

            // Spec, but not drawn: screen 16 goes straight from the control to
            // `Accent colour`, because the note only appears once the control
            // has been used. It has no drawn geometry of its own, so both
            // values are borrowed from the one comparable note the export does
            // draw — the privacy line at the foot of screen 17, which is
            // `monoNote` in `muted` and sits `16` under the rule above it.
            //
            // The gap is borrowed; the rule is not. That note closes the screen
            // and the line above it is what separates it from the last section.
            // This one sits inside a section that already has its own chrome,
            // and a second rule in the middle of it would read as a break.
            Text("settings.appearance.cameraNote")
                .fuelStyle(FuelTypography.monoNote)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s16)
        }
    }
}

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
            // has been used. It therefore has no drawn geometry of its own, and
            // the two values here are borrowed rather than invented: `monoNote`
            // in `muted` is the standing explanatory line at the foot of
            // Settings, and `12` is the gap the export puts between a control
            // and the note under it on screen 01.
            Text("settings.appearance.cameraNote")
                .fuelStyle(FuelTypography.monoNote)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, FuelMetrics.Space.s12)
        }
    }
}

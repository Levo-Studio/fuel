import SwiftUI

// MARK: - Settings

/// Screens 16 and 17 are one screen. The export draws two frames because a
/// 390×844 render cannot show a scroll, not because there are two of them —
/// both frames carry the same header, and screen 17's first section sits under
/// it at the same gap every later section uses.
///
/// This type is the scaffold: the header, the scroll, the horizontal inset and
/// the palette every section reads out of the environment. The sections are
/// self-contained views listed in `body`, so the counting, goal and label
/// sections of screen 17 are added by appending three lines here and three
/// files beside this one — no section has to be reopened for another to arrive.
struct SettingsScreen: View {

    /// Owned by whoever presents Settings, not by this view: the theme and the
    /// accent are app-wide, and a screen that created its own copy would hand
    /// back a choice nothing else had heard about.
    let preferences: SettingsPreferences
    let keyModel: APIKeySettingsModel

    let done: () -> Void

    private var palette: FuelPalette {
        FuelPalette(theme: preferences.theme, accent: preferences.accent)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SettingsHeader(done: done)

                AIModelSection(preferences: preferences, model: keyModel)

                AppearanceSection(preferences: preferences)

                AccentSection(preferences: preferences)
            }
            .padding(.horizontal, FuelMetrics.Screen.horizontalPadding)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(palette.background.ignoresSafeArea())
        .environment(\.fuelPalette, palette)
        .preferredColorScheme(palette.theme.colorScheme)
        .fuelAnimation(FuelMotion.standard, value: palette.theme)
    }
}

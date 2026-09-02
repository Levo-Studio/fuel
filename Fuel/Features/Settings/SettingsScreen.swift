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

// MARK: - Previews

#Preview("Dark · connection works") {
    SettingsPreview(theme: .dark, accent: .mono, note: .passed)
}

#Preview("Light · no credit") {
    SettingsPreview(theme: .light, accent: .green, note: .noCredit)
}

/// Renders the whole screen, both themes, with a note showing.
///
/// A design export cannot be checked against source, only against a frame, and
/// until this existed there was no frame: nothing in the app presented
/// `SettingsScreen`, so every fidelity claim about screen 16 — the swatch
/// rings, the section gaps, the note in the error colour — was read off code.
/// The second preview picks a light theme and a non-mono accent on purpose,
/// because that is where a wrong ring colour or a wrong on-colour shows.
///
/// What it writes, it writes somewhere harmless. Setting the theme and the
/// accent goes through the same `didSet` the screen uses, so both land in a
/// plist — but in a suite of the preview's own, never the app's, so a canvas
/// render cannot change the appearance of Fuel on the same machine. The note is
/// seeded rather than earned, so no provider call is made, and no Keychain item
/// is created unless someone types into the field in the canvas.
private struct SettingsPreview: View {

    @State private var preferences: SettingsPreferences
    @State private var model: APIKeySettingsModel

    init(theme: FuelTheme, accent: FuelAccent, note: KeyTestNote) {
        let preferences = SettingsPreferences(defaults: Self.previewDefaults())
        preferences.theme = theme
        preferences.accent = accent
        _preferences = State(initialValue: preferences)
        _model = State(
            initialValue: APIKeySettingsModel(
                keychain: KeychainStore(service: Self.previewService),
                validator: PreviewValidator(),
                showing: note
            )
        )
    }

    var body: some View {
        SettingsScreen(preferences: preferences, keyModel: model, done: {})
    }

    /// A suite of the preview's own, so a canvas render cannot change the
    /// appearance of the app on the same machine.
    private static func previewDefaults() -> UserDefaults {
        UserDefaults(suiteName: "apps.levo-studio.Fuel.previews.settings") ?? .standard
    }

    /// Never written to by these previews, and off the production service if a
    /// canvas is typed into.
    private static let previewService = "apps.levo-studio.Fuel.previews.provider-keys"
}

/// The canvas has no network and must not acquire one. Tapping `Re-check` in a
/// preview concludes nothing, which is the honest answer offline.
private struct PreviewValidator: KeyValidating {

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        .retry
    }
}

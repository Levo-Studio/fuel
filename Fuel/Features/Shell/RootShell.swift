import SwiftUI

// MARK: - Root shell

/// The single window's content.
///
/// The shell decides what the app opens on — the onboarding flow until a goal
/// has been answered, the Today screen afterwards — and nothing else. It draws
/// no chrome of its own: each screen brings its own background and its own
/// margins, and a container that added a second one would shift every one of
/// them.
struct RootShell: View {

    @State private var model: RootShellModel

    /// Settings' own preferences, held here because the appearance has to be
    /// known before the first frame and every feature below reads the palette
    /// out of the environment. Nothing injected `\.fuelPalette` before this,
    /// so the whole app drew against the environment default rather than
    /// against the user's choice.
    ///
    /// It is the type Settings writes through, not a second reader of the same
    /// keys, so a theme changed on screen 16 reaches this palette without a
    /// relaunch and without anything having to be told about it.
    @State private var preferences: SettingsPreferences

    init(store: FuelStore, validator: KeyValidating, defaults: UserDefaults = .standard) {
        _model = State(initialValue: RootShellModel(store: store, validator: validator))
        _preferences = State(initialValue: SettingsPreferences(defaults: defaults))
    }

    private var palette: FuelPalette {
        FuelPalette(theme: preferences.theme, accent: preferences.accent)
    }

    var body: some View {
        ZStack {
            switch model.stage {
            case .onboarding:
                OnboardingFlow(model: model.onboarding)
            case .today:
                TodayView(
                    presentation: model.today,
                    // Both controls are drawn on screens 05 and 06, both
                    // have a destination that now exists, and both are still
                    // inert here.
                    //
                    // Screen 16's three sections are merged and screen 17's
                    // four are not; the log flow draws its bar and its Recent
                    // tab, and the two modes that need a key and a capture
                    // session are placeholders. Neither is finished, and
                    // neither export draws how it is entered from Today — no
                    // sheet, no push, no dismissal is drawn anywhere — so the
                    // presentation is a design decision rather than a wiring
                    // one, and it is not this branch's to make.
                    //
                    // What is missing is a call, not a mechanism: both take a
                    // model this shell already has the store for.
                    onOpenSettings: {},
                    onAddEntry: {}
                )
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
        .environment(\.fuelPalette, palette)
        // The theme is a stored choice and never follows the OS, so the system
        // chrome — the status bar, the keyboard, the home indicator — is forced
        // to match it rather than left to invert against the app underneath.
        .preferredColorScheme(preferences.theme.colorScheme)
    }
}

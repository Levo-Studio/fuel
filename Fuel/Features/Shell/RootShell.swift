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
                    // Both controls are drawn, and both are inert, for two
                    // different reasons.
                    //
                    // Settings exists but is half of itself: screen 16's
                    // sections are merged and screen 17's are not, and
                    // `SettingsScreen` says presenting it belongs to whoever
                    // does. Routing into a screen that is still being built is
                    // not this branch's call to make.
                    //
                    // The log flow has no target at all — the feature is
                    // unmerged — so its button has nowhere to go rather than
                    // somewhere unfinished.
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

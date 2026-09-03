import SwiftUI

// MARK: - Root shell

/// The single window's content.
///
/// The shell decides what the app opens on — the onboarding flow until a goal
/// has been answered, the Today screen afterwards — and what is presented over
/// Today when one of its two controls is used. It draws no chrome of its own:
/// each screen brings its own background and its own margins, and a container
/// that added a second one would shift every one of them. That is why the log
/// flow and Settings arrive as full-screen covers and not inside a navigation
/// stack — see `RootShellModel.Destination`.
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
        // One instance, handed to both. The model reads the selected provider
        // when a log flow opens and Settings writes it on screen 16, so a
        // second `SettingsPreferences` built from the same suite would work
        // until the moment it mattered — the write would land in the plist and
        // the flow already open would still be pointed at the old provider.
        let preferences = SettingsPreferences(defaults: defaults)
        _preferences = State(initialValue: preferences)
        _model = State(
            initialValue: RootShellModel(
                store: store,
                validator: validator,
                preferences: preferences
            )
        )
    }

    private var palette: FuelPalette {
        FuelPalette(theme: preferences.theme, accent: preferences.accent)
    }

    /// `fullScreenCover` takes a binding it can clear, and the model's
    /// destination is read-only from outside. The write is routed back through
    /// `dismissDestination` rather than assigning the property, so a return to
    /// Today the system initiates goes through the same re-read of the day as
    /// the drawn controls do.
    private var presentedDestination: Binding<RootShellModel.Destination?> {
        Binding(
            get: { model.destination },
            set: { presented in
                guard presented == nil else { return }
                model.dismissDestination()
            }
        )
    }

    var body: some View {
        ZStack {
            switch model.stage {
            case .onboarding:
                OnboardingFlow(model: model.onboarding)
            case .today:
                TodayView(
                    presentation: model.today,
                    onOpenSettings: model.openSettings,
                    onAddEntry: model.openLogFlow
                )
            }
        }
        .fullScreenCover(item: presentedDestination) { destination in
            switch destination {
            case .logFlow:
                LogFlowView(
                    model: model.logFlow,
                    camera: model.cameraLog,
                    text: model.textLog,
                    onCancel: model.dismissDestination,
                    onLogged: model.dismissDestination
                )
                // The status bar is forced light because the export draws it
                // light on exactly these screens. Every theme-following frame
                // draws it `color:var(--ink)`; the three log-flow screens
                // hard-code `#fafafa` over their `var(--cam)` frame — 07 the
                // camera, 12 the text entry, 13 Recent. That is the export
                // refusing to let the status bar follow the theme here, not an
                // inference from the surface colour underneath it.
                //
                // Blanket over the whole cover, which is right only while the
                // cover hosts flow chrome. Screens 14 and 15 draw
                // `color:var(--ink)` on `var(--bg)` and carry `‹ Back` rather
                // than `✕ Cancel` — they are result screens, not chrome — so
                // the moment the result screen lands inside `LogFlowView` this
                // becomes a light-theme bug, and it has to move in with the
                // tabs that actually draw dark.
                //
                // It sits at this call site rather than beside `palette.camera`
                // in `LogFlowScaffold`, where it belongs, only because that
                // file is another branch's. Move it there once the two are in
                // one tree; do not tidy it anywhere else.
                .preferredColorScheme(.dark)
            case .settings:
                if let counting = model.settingsCounting {
                    SettingsScreen(
                        preferences: preferences,
                        keyModel: model.settingsKey,
                        countingModel: counting,
                        done: model.dismissDestination
                    )
                }
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
        // What the curve governs here is Today rearranging itself underneath —
        // the totals, the ring and a new meal section arriving when the flow
        // dismisses and the day is re-read. The cover's own travel up and down
        // is the system's presentation, which honours Reduce Motion on its own
        // account; there is nothing to hand it, and a hand-rolled curve at this
        // call site would be the design-layer bypass `FuelMotion` exists to
        // prevent.
        .fuelAnimation(FuelMotion.emphasised, value: model.destination)
        .environment(\.fuelPalette, palette)
        // The theme is a stored choice and never follows the OS, so the system
        // chrome — the status bar, the keyboard, the home indicator — is forced
        // to match it rather than left to invert against the app underneath.
        .preferredColorScheme(preferences.theme.colorScheme)
    }
}

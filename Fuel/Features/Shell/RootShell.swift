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

    /// Where a scan request from outside the app arrives. Held rather than
    /// reached for at the call site so a test can name its own, the way
    /// `defaults` is injected below.
    private let router: ScanRouter

    init(
        store: FuelStore,
        validator: KeyValidating,
        defaults: UserDefaults = .standard,
        router: ScanRouter = .shared
    ) {
        self.router = router
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
                    gettingStarted: model.gettingStarted,
                    onOpenSettings: model.openSettings,
                    onAddEntry: model.openLogFlow,
                    onOpenMeal: model.openMealDetail
                )
            }
        }
        // The shell registers for scan requests here rather than in
        // `RootShellModel.init`, and the difference is which shell registers.
        //
        // A `@State`'s initial value expression runs on every initialisation of
        // the struct holding it while `State` keeps only the first value it is
        // handed — the reason `FuelApp` opens the store where it does. A model
        // built by a construction SwiftUI then discards would, if it registered
        // itself, consume a request waiting from a cold launch and take the
        // router's weak reference down with it when it deallocated, leaving the
        // shortcut a silent no-op for the rest of the process. Registering on
        // appearance means the shell that is actually in the hierarchy is the
        // one the router holds, so the failure mode is gone rather than argued
        // against.
        //
        // Repeated appearances are safe and wanted: `adopt` re-points the weak
        // reference and delivers a request that arrived while nothing held one.
        .onAppear { router.adopt(model) }
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
                // The cover hosts two kinds of screen and the export inks the
                // status bar differently on each, so the scheme is per stage
                // rather than blanket: `LogFlowChrome` holds which is which and
                // why, read off the two AI models' own stages.
                //
                // It stays at this call site rather than moving into
                // `LogFlowScaffold` beside `palette.camera`. `LogFlowView`
                // keeps the scaffold in the hierarchy underneath the result
                // overlay, so a modifier there would still apply while screens
                // 14 and 15 are up — which is the one case this has to stop
                // applying to.
                .preferredColorScheme(
                    LogFlowChrome.colorScheme(
                        camera: model.cameraLog.stage,
                        text: model.textLog.stage,
                        theme: preferences.theme
                    )
                )
            case .mealDetail:
                if let detail = model.mealDetail {
                    MealDetailView(model: detail, onClose: model.dismissDestination)
                }
            case .settings:
                if let counting = model.settingsCounting {
                    SettingsScreen(
                        preferences: preferences,
                        keyModel: model.settingsKey,
                        countingModel: counting,
                        done: model.dismissDestination
                    )
                    // Settings loses nothing by being left: every control on it
                    // writes the moment it is used, and the key row is built
                    // once and held, so a half-typed key is still there when the
                    // screen is opened again. `Done` stays the drawn control;
                    // this is the same exit for a thumb that starts at the edge.
                    .fuelBackSwipe(perform: model.dismissDestination)
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

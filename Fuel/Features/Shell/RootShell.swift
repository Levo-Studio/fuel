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
///
/// The one exception is the screen a logged meal opens on, which is pushed. The
/// stack it is pushed on is still chromeless: the bar is hidden on both the
/// root and the pushed screen, so the two are laid out from the top of the
/// frame exactly as they were under a cover.
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

    /// Whether the confirmation in front of an interactive pop is up.
    ///
    /// Interface state and so held here rather than on the model, the way
    /// `MealDetailView` holds the delete confirmation: a confirmation is a
    /// thing the interface is showing, not a thing the meal is doing.
    @State private var isConfirmingPop = false

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

    /// Today, with the one screen that is pushed rather than presented.
    ///
    /// The bar is hidden on both ends of the stack. Every Fuel screen is laid
    /// out from the top of its own frame and brings its own header, so a
    /// navigation bar would be a second one — and on the root it would push
    /// Today's date and totals down by its height.
    private var todayStack: some View {
        NavigationStack(path: mealDetailPath) {
            TodayView(
                presentation: model.today,
                navigation: model.dayNavigation,
                isTravellingBackward: model.dayTravelIsBackward,
                gettingStarted: model.gettingStarted,
                onOpenSettings: model.openSettings,
                onAddEntry: model.openLogFlow,
                onOpenMeal: model.openMealDetail,
                onShowPreviousDay: model.showPreviousDay,
                onShowNextDay: model.showNextDay,
                onShowDay: model.showDay
            )
            .toolbar(.hidden, for: .navigationBar)
            // The path element is the meal's identity and the screen is the
            // model the shell built for it, so the identity is not read here.
            // It is what the stack needs to be a stack — a `Hashable` value it
            // can hold — while the model stays where every other screen's does,
            // built and released by the shell model.
            .navigationDestination(for: UUID.self) { _ in
                if let detail = model.mealDetail {
                    MealDetailView(model: detail, onClose: model.dismissMealDetail)
                        .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
        // Raised by a pop the user made with the system's gesture, never by
        // `‹ Back`: that control has its own confirmation inside
        // `MealResultView`, which this one deliberately repeats word for word.
        //
        // It sits here rather than on the meal screen because the gesture is
        // not something that screen can see. An interactive pop arrives as a
        // write to the path, which is held here, and the path is also the only
        // thing that can undo it.
        .confirmationDialog(
            MealDetailCopy.discardEditsConfirmation.title,
            isPresented: $isConfirmingPop,
            titleVisibility: .visible
        ) {
            Button(MealDetailCopy.discardEditsConfirmation.confirm, role: .destructive) {
                model.dismissMealDetail()
            }

            Button(MealDetailCopy.discardEditsConfirmation.cancel, role: .cancel) {}
        }
    }

    /// The stack's path, and the one place an interactive pop can be caught.
    ///
    /// A push cannot be withheld and then still be offered: the system's
    /// back-swipe belongs to the navigation controller, and SwiftUI exposes no
    /// way to arm it conditionally or to veto it while the finger is still
    /// down. What it does expose is this binding, and a binding that does not
    /// write is a pop that does not happen — the getter still says the meal is
    /// on the stack, so the screen comes back.
    ///
    /// So the gesture is kept and routed through the same question `‹ Back`
    /// asks. The cost is honest and visible: with edits pending the screen
    /// returns in one step rather than following the finger back, and the
    /// dialog arrives over it. Withholding the gesture outright was the
    /// alternative and is worse — a dead edge is not something a user can see
    /// the reason for, and it would be dead exactly when they most want out.
    private var mealDetailPath: Binding<[UUID]> {
        Binding(
            get: { model.pushedMeal.map { [$0] } ?? [] },
            set: { path in
                // Only a pop is routed here. Pushes are made by
                // `openMealDetail`, which writes the model directly.
                guard path.isEmpty, model.pushedMeal != nil else { return }
                if model.mealDetailDiscardsEdits {
                    isConfirmingPop = true
                } else {
                    model.dismissMealDetail()
                }
            }
        )
    }

    var body: some View {
        ZStack {
            switch model.stage {
            case .onboarding:
                OnboardingFlow(model: model.onboarding)
            case .today:
                todayStack
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
                    // The one exit that is not the same as the others: a meal
                    // is logged now, so the flow closes onto the current day
                    // rather than onto whichever one was being browsed.
                    onLogged: model.dismissDestinationAfterLogging
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
                // A scan takes several seconds the user is entitled to look
                // away from, which is what the two outcomes are felt for.
                //
                // Read here rather than inside the flow for the reason the
                // chrome above it is: this is already where both models' stages
                // are known, and a second place that had to be told what the
                // flow was doing would be a second copy of it to drift.
                .onChange(of: model.cameraLog.stage) { previous, current in
                    reportCameraScan(from: previous, to: current)
                }
                .onChange(of: model.textLog.stage) { previous, current in
                    reportTextScan(from: previous, to: current)
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
        // The same curve on the same subject for the screen that is pushed
        // rather than presented: a meal deleted on it leaves the day one meal
        // shorter, and Today rearranges to that while the screen is on its way
        // out. The push and the pop themselves are the stack's own travel,
        // which honours Reduce Motion on its own account.
        .fuelAnimation(FuelMotion.emphasised, value: model.pushedMeal)
        .environment(\.fuelPalette, palette)
        // The theme is a stored choice and never follows the OS, so the system
        // chrome — the status bar, the keyboard, the home indicator — is forced
        // to match it rather than left to invert against the app underneath.
        .preferredColorScheme(preferences.theme.colorScheme)
    }

    // MARK: - A finished scan

    /// Both modes reach an estimate at `.result` and a failure at `.failed`,
    /// and neither is where a cancelled scan lands — cancelling returns to the
    /// viewfinder or to the field. So the outcome is read straight off the
    /// stage here, with none of the bookkeeping the meal detail needs.
    private func reportCameraScan(
        from previous: CameraLogModel.Stage,
        to current: CameraLogModel.Stage
    ) {
        guard case .analysing = previous else { return }
        switch current {
        case .result:
            FuelHaptics.play(.scanSucceeded)
        case .failed:
            FuelHaptics.play(.scanFailed)
        case .viewfinder, .noKey, .analysing:
            break
        }
    }

    private func reportTextScan(
        from previous: TextLogModel.Stage,
        to current: TextLogModel.Stage
    ) {
        guard case .analysing = previous else { return }
        switch current {
        case .result:
            FuelHaptics.play(.scanSucceeded)
        case .failed:
            FuelHaptics.play(.scanFailed)
        case .entry, .noKey, .analysing:
            break
        }
    }
}

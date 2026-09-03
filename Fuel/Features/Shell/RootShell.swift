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

    init(store: FuelStore, validator: KeyValidating) {
        _model = State(initialValue: RootShellModel(store: store, validator: validator))
    }

    var body: some View {
        ZStack {
            switch model.stage {
            case .onboarding:
                OnboardingFlow(model: model.onboarding)
            case .today:
                TodayView(
                    presentation: model.today,
                    // Settings and the log flow are separate features and are
                    // not on `main` yet. Their two controls are drawn — they
                    // are part of screens 05 and 06 — and stay inert until the
                    // screens behind them exist.
                    onOpenSettings: {},
                    onAddEntry: {}
                )
            }
        }
        .fuelAnimation(FuelMotion.emphasised, value: model.stage)
    }
}

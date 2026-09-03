import Foundation
import Observation

// MARK: - Root shell model

/// Decides what the app opens on, and holds the state that must outlive a
/// re-render.
///
/// Both halves are the same concern. The launch decision is not a stored flag:
/// it is read from the store, because the existence of the `GoalSettings` row
/// is what "onboarding has been answered" means. A second boolean beside it —
/// in `UserDefaults`, in the keychain, anywhere — would be a second answer to
/// one question, and the two would eventually disagree.
@MainActor
@Observable
final class RootShellModel {

    // MARK: - Stage

    enum Stage: Equatable {
        case onboarding
        case today
    }

    // MARK: - Dependencies

    private let store: FuelStore

    // MARK: - State

    private(set) var stage: Stage

    /// What Today draws, worked out from the store rather than kept in step
    /// with it: it is recomputed whenever the stage becomes `today`, which is
    /// the only moment its inputs can have changed while no log flow exists.
    private(set) var today: TodayPresentation

    /// The onboarding flow's own state, built once so a re-render of the shell
    /// cannot drop a half-typed key or restart the key test.
    ///
    /// It cannot be a `let`: its completion handler captures `self`, which is
    /// only available once every stored property holds a value. Observation is
    /// switched off for it because the reference never changes — the object it
    /// points at is `@Observable` on its own account.
    @ObservationIgnored private(set) var onboarding: OnboardingModel!

    // MARK: - Creation

    init(store: FuelStore, validator: KeyValidating) {
        self.store = store
        self.stage = Self.launchStage(for: store)
        self.today = Self.presentation(for: store)
        self.onboarding = OnboardingModel(
            validator: validator,
            store: store,
            onFinished: { [weak self] in self?.showToday() }
        )
    }

    // MARK: - Launch decision

    /// No settings row means onboarding has never been answered.
    ///
    /// A fetch that throws is read as "not answered". Asking the questions
    /// again is recoverable; opening Today against a store that cannot be read
    /// is not, and onboarding's own write would surface the same failure where
    /// the user can respond to it.
    private static func launchStage(for store: FuelStore) -> Stage {
        let settings = (try? store.existingGoalSettings()) ?? nil
        return settings == nil ? .onboarding : .today
    }

    private static func presentation(for store: FuelStore) -> TodayPresentation {
        let now = Date()
        return TodayPresentation(
            entries: (try? store.nutritionEntries(on: now)) ?? [],
            mode: (try? store.countingMode()) ?? .goal(.default),
            date: now
        )
    }

    // MARK: - Transition

    /// Called when onboarding has written the settings row. The row is the
    /// truth, so the presentation is read back from the store rather than
    /// assembled from what the flow happened to hold.
    private func showToday() {
        today = Self.presentation(for: store)
        stage = .today
    }
}

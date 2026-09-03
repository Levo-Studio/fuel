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

    // MARK: - Destination

    /// What is presented over Today.
    ///
    /// Both are full-screen presentations rather than pushes, because both are
    /// dismissed by a control the export draws on their own chrome: the log
    /// flow's `✕ Cancel` at the top left of screens 07, 12 and 13, and
    /// Settings' `Done` opposite its title on screens 16 and 17. Neither is a
    /// back chevron, neither sits in a navigation bar, and no screen in the
    /// export draws one — so there is nothing for a stack to draw, and a stack
    /// would put its own bar above screens that are laid out from the top of
    /// the frame.
    enum Destination: Hashable, Identifiable {

        case logFlow
        case settings

        var id: Self { self }
    }

    // MARK: - Composition

    /// Builds the camera half of a log flow for the provider that is selected
    /// at the moment the flow opens.
    typealias CameraLogFactory = @MainActor (FuelStore, AIProvider) -> CameraLogModel

    /// The real thing: the device camera, and the client for that provider.
    ///
    /// The provider is passed twice on purpose and they are not the same
    /// question. `client` decides which endpoint an estimate is sent to;
    /// `provider` decides which key the model looks for before it lets the
    /// shutter work. Handing the model a Claude client while it checked for a
    /// Mistral key would put a dead shutter in front of a working account.
    @MainActor
    static let liveCameraLog: CameraLogFactory = { store, provider in
        CameraLogModel(
            store: store,
            client: ProviderClients.client(for: provider),
            camera: AVFoundationCamera(),
            provider: provider
        )
    }

    // MARK: - Dependencies

    private let store: FuelStore

    /// The three preferences Settings stores. Held rather than read once,
    /// because the provider a scan talks to is whichever one is selected when
    /// the flow is opened — not the one that was selected at launch.
    private let preferences: SettingsPreferences

    /// How the camera half of a log flow is built.
    ///
    /// A seam rather than a direct call, and it earns its keep twice.
    /// `CameraLogModel` keeps its client, its keychain reader and the provider
    /// it looks a key up under to itself, so without this nothing outside it
    /// could establish that the provider Settings stores is the provider the
    /// next scan uses. It is also the only way a test reaches this screen at
    /// all: the real composition opens the device camera and builds a client
    /// pointed at a provider's endpoint.
    private let makeCameraLog: CameraLogFactory

    // MARK: - State

    private(set) var stage: Stage

    private(set) var destination: Destination?

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

    /// The log flow's state, replaced each time the flow is opened.
    ///
    /// A kept model would reopen on whichever tab was left selected, and the
    /// export is explicit about where the flow starts: screen 07 is captioned
    /// `Log · camera (default)`. Nothing is lost by starting again either —
    /// the Recent list is read from the store on appearance, and a flow that
    /// was cancelled had by definition typed nothing worth keeping.
    ///
    /// Observed rather than `@ObservationIgnored`, unlike `onboarding`: this
    /// reference does change, and a presentation still reading the previous
    /// flow's model would show the tab the user left rather than the one they
    /// are opening.
    private(set) var logFlow: LogFlowModel

    /// The camera half of the same flow, rebuilt with it and for the same
    /// reason — more urgently, in fact. `LogFlowModel` would only reopen on
    /// the wrong tab; this one holds a stage, a captured frame and a draft, so
    /// a flow left on a failed scan or on the result screen would reopen onto
    /// that screen instead of onto the viewfinder screen 07 draws. Rebuilding
    /// also releases the frame: a photo the user walked away from has no
    /// reason to stay in memory until the next scan replaces it.
    private(set) var cameraLog: CameraLogModel

    /// Settings' API-key row. Built once, because a re-render must not drop a
    /// half-typed key or restart a check in flight — the same reason
    /// `onboarding` is built here rather than in a view.
    @ObservationIgnored private(set) var settingsKey: APIKeySettingsModel

    /// Screen 17's counting mode and its four targets, built when Settings is
    /// opened rather than held from launch.
    ///
    /// Unlike the three preferences beside it, these are store rows — and at
    /// the moment this model is created the store may not have them yet, since
    /// onboarding is what writes the first one. Reading at the launch of the
    /// app would show the user a mode they had not chosen.
    private(set) var settingsCounting: CountingSettingsModel?

    // MARK: - Creation

    init(
        store: FuelStore,
        validator: KeyValidating,
        preferences: SettingsPreferences,
        makeCameraLog: @escaping CameraLogFactory = RootShellModel.liveCameraLog
    ) {
        self.store = store
        self.preferences = preferences
        self.makeCameraLog = makeCameraLog
        self.stage = Self.launchStage(for: store)
        self.today = Self.presentation(for: store)
        self.logFlow = LogFlowModel(store: store)
        self.cameraLog = makeCameraLog(store, preferences.provider)
        self.settingsKey = APIKeySettingsModel(validator: validator)
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

    // MARK: - Leaving and returning to Today

    /// The plus on screens 05 and 06.
    func openLogFlow() {
        logFlow = LogFlowModel(store: store)
        // Read here rather than kept from launch, so a provider switched on
        // screen 16 is the one the next scan talks to and looks a key up
        // under. Nothing has to tell the flow that Settings was used.
        cameraLog = makeCameraLog(store, preferences.provider)
        destination = .logFlow
    }

    /// The gear on screens 05 and 06.
    ///
    /// A store that cannot be read leaves the gear unanswered rather than
    /// opening screen 17 against invented defaults. Those fields write back
    /// the moment they are edited, so a user adjusting a 2400 the store never
    /// held would overwrite the goal they actually set — worse than a control
    /// that did nothing, and the export draws no state for either.
    func openSettings() {
        guard let counting = try? CountingSettingsModel(store: store) else { return }
        settingsCounting = counting
        destination = .settings
    }

    /// Comes back to Today from whatever was presented, with the day re-read
    /// from the store.
    ///
    /// **One exit for all four of them** — `✕ Cancel`, a meal logged, `Done`,
    /// and a preference changed on the way out — because the refresh is a
    /// re-read rather than an update. Nothing here is told what happened while
    /// the presentation was up; the store is asked again, and it answers with
    /// the day and the counting mode as they now are. Cancel costs one fetch
    /// that returns the same day, which is the price of not having a second
    /// path that depends on the flow's own account of whether it wrote.
    ///
    /// It is not left to SwiftData to notice, either. `today` is a value
    /// worked out from a fetch, not a live query, so an entry written inside
    /// the flow reaches the totals and its meal section only when this runs.
    func dismissDestination() {
        // The flow starts the session when the camera tab appears and stops it
        // when another tab does, through a `.task(id:)` keyed on the selected
        // tab. Cancelling that task does not stop the session, so nothing
        // stopped it when the whole cover went away — the camera and its
        // indicator would keep running behind Today. It was unreachable while
        // nothing presented the flow; presenting it is what this branch does.
        //
        // Stopping belongs here rather than in the flow because this is what
        // owns the model's lifetime: it builds the camera half when the flow
        // opens and releases it here.
        if destination == .logFlow {
            cameraLog.camera.stop()
        }

        today = Self.presentation(for: store)
        destination = nil
    }
}

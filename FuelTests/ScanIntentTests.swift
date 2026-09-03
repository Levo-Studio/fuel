import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Doubles

/// The shell has to hand `OnboardingModel` a validator to build it at all, and
/// nothing here submits a key.
private nonisolated struct UnusedValidator: KeyValidating {

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        .retry
    }
}

/// A client no test in this file lets an estimate reach.
///
/// **Nothing here goes near a provider.** What the shortcut is asked about is
/// which screen it lands on, never what an estimate comes back as.
private nonisolated struct UnusedEstimator: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .failed(.cancelled) }

    func estimate(photo: MealPhoto) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }
}

/// A camera that opens no lens.
private final class StubCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage { UIImage() }
}

// MARK: - Suite

/// What the "Scan" shortcut does to the running app.
///
/// It draws nothing of its own, so everything worth asserting is the shell's
/// state afterwards: which destination is presented, which tab it is on, and
/// which flow object that tab belongs to.
@MainActor
@Suite("Scan shortcut")
struct ScanIntentTests {

    // MARK: - Building a shell

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true)
    }

    /// Never the app's suite: a run must not change the provider Fuel opens on
    /// for whoever is on the machine.
    private func makePreferences() -> SettingsPreferences {
        let suite = "apps.levo-studio.Fuel.tests.scan.\(UUID().uuidString)"
        return SettingsPreferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func makeModel(
        store: FuelStore,
        keys: any MealKeyPresence = StoredKey()
    ) -> RootShellModel {
        RootShellModel(
            store: store,
            validator: UnusedValidator(),
            preferences: makePreferences(),
            makeCameraLog: { store, provider in
                CameraLogModel(
                    store: store,
                    client: UnusedEstimator(),
                    camera: StubCamera(),
                    keys: keys,
                    provider: provider
                )
            },
            makeTextLog: { store, provider in
                TextLogModel(
                    store: store,
                    client: UnusedEstimator(),
                    keys: keys,
                    provider: provider,
                    pace: {}
                )
            }
        )
    }

    /// A shell that has been through onboarding, which is the state every test
    /// but the onboarding one starts from.
    private func makeTodayModel(keys: any MealKeyPresence = StoredKey()) throws -> RootShellModel {
        let store = try makeStore()
        try store.setCountingMode(.goal(.default))
        return makeModel(store: store, keys: keys)
    }

    // MARK: - The destination

    /// Screen 07 is where the shortcut is meant to land, and the tab is the
    /// half of that claim a destination alone does not carry.
    @Test("The shortcut opens the log flow on the camera tab")
    func scanOpensTheCameraTab() throws {
        let model = try makeTodayModel()
        #expect(model.destination == nil)

        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.logFlow.selectedTab == .camera)
    }

    // MARK: - No key stored

    /// The shortcut does not ask whether a key exists, and this is why it does
    /// not need to: the camera half asks when its tab appears and says so on
    /// screen 07. A shortcut that refused to open would leave the user with
    /// nothing to read and nothing to fix.
    @Test("Without a key the shortcut still opens the flow, on the keyless notice")
    func scanWithoutAKeyOpensTheKeylessState() throws {
        let model = try makeTodayModel(keys: NoKeys())

        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.logFlow.selectedTab == .camera)

        // What the camera tab does on appearance.
        model.cameraLog.refreshAvailability()
        #expect(model.cameraLog.stage == .noKey)
    }

    // MARK: - Onboarding

    /// Screens 01 to 03 come before 04 and cannot be skipped, so there is no
    /// key to scan with and no Today to present over. Opening the app onto
    /// onboarding is the whole answer, and it is not a silent one: the app is
    /// in front of the user, on the step that has to happen first.
    @Test("A shortcut fired before onboarding is answered presents nothing over it")
    func scanDuringOnboardingPresentsNothing() throws {
        let model = makeModel(store: try makeStore())
        #expect(model.stage == .onboarding)

        model.requestScan()

        #expect(model.stage == .onboarding)
        #expect(model.destination == nil)
    }

    /// The request is not remembered either. It was answered by the app coming
    /// to the front; replaying it minutes later, on top of a Today the user
    /// arrived at by finishing onboarding, would open a viewfinder nobody
    /// asked for.
    @Test("Finishing onboarding does not replay the shortcut")
    func scanIsNotReplayedAfterOnboarding() throws {
        let model = makeModel(store: try makeStore())

        model.requestScan()
        model.onboarding.selectGoalMode()
        #expect(model.onboarding.complete())

        #expect(model.stage == .today)
        #expect(model.destination == nil)
    }

    // MARK: - Something already presented

    /// The destination the shortcut asks for is already on screen, so only the
    /// tab is left to answer.
    @Test("A flow already open moves to its camera tab")
    func scanSelectsTheCameraTabOfAnOpenFlow() throws {
        let model = try makeTodayModel()

        model.openLogFlow()
        model.logFlow.selectedTab = .recent
        let flow = model.logFlow

        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.logFlow.selectedTab == .camera)
        // The same flow, not a second one over the first.
        #expect(model.logFlow === flow)
    }

    /// The destructive reading of "open the camera" is the one this rules out:
    /// a shortcut fired while a scan is being looked at must not throw the
    /// scan away.
    @Test("A flow already open keeps the camera half it had")
    func scanKeepsTheCameraHalfOfAnOpenFlow() throws {
        let model = try makeTodayModel()

        model.openLogFlow()
        let camera = model.cameraLog

        model.requestScan()

        #expect(model.cameraLog === camera)
    }

    /// Two covers cannot be presented over one another, and ignoring the user
    /// is not the alternative. Settings is left the way `Done` leaves it, and
    /// the flow is opened as the plus opens it.
    @Test("Settings gives way to the flow rather than being covered by it")
    func scanReplacesSettings() throws {
        let model = try makeTodayModel()

        model.openSettings()
        #expect(model.destination == .settings)

        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.logFlow.selectedTab == .camera)
    }

    /// Coming out of Settings through the drawn exit is what makes a counting
    /// mode changed there the one Today holds afterwards — the flow is opened
    /// over a Today that has been re-read, not over a stale one.
    @Test("A preference changed in Settings survives the shortcut")
    func scanFromSettingsRereadsTheDay() throws {
        let model = try makeTodayModel()
        #expect(model.today.showsRing)

        model.openSettings()
        model.settingsCounting?.choice = .countOnly
        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.today.showsRing == false)
    }

    // MARK: - The hand-off

    /// Fuel is already running, which is the case the router has least to do
    /// in: the request goes straight through to the shell that registered.
    @Test("A request reaches the shell that registered with the router")
    func routerForwardsToTheShell() throws {
        let router = ScanRouter()
        let model = try makeTodayModel()
        router.adopt(model)

        router.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.logFlow.selectedTab == .camera)
    }

    /// The cold-launch case, and the reason the router is not a plain
    /// forwarding call. The app is started by the shortcut, so the request can
    /// arrive before any shell is on screen; dropping it there would leave the
    /// shortcut working only when Fuel happened to be open already.
    @Test("A request that arrives before the shell is answered when it registers")
    func routerHoldsARequestUntilAShellRegisters() throws {
        let router = ScanRouter()
        router.requestScan()

        let model = try makeTodayModel()
        // Built, and not yet on screen. Building is not registering.
        #expect(model.destination == nil)

        router.adopt(model)

        #expect(model.destination == .logFlow)
        #expect(model.logFlow.selectedTab == .camera)
    }

    /// Held once, not for the life of the process. A request answered at
    /// launch must not open a viewfinder again in front of whatever the user
    /// is doing later — and appearing a second time is normal: `RootShell`
    /// registers on every appearance, so this runs whenever Fuel comes back to
    /// the front.
    @Test("A held request is answered once, however often the shell registers")
    func routerHoldsARequestOnlyOnce() throws {
        let router = ScanRouter()
        router.requestScan()

        let model = try makeTodayModel()
        router.adopt(model)
        model.dismissDestination()
        #expect(model.destination == nil)

        router.adopt(model)
        #expect(model.destination == nil)
    }

    /// A shell that never reaches Today answers the request by being on
    /// screen, so nothing is presented and nothing is kept for later.
    @Test("A request held for a shell that opens on onboarding presents nothing")
    func routerHandsAnEarlyRequestToOnboarding() throws {
        let router = ScanRouter()
        router.requestScan()

        let model = makeModel(store: try makeStore())
        router.adopt(model)

        #expect(model.stage == .onboarding)
        #expect(model.destination == nil)
    }

    /// The registration is the view's, on appearance, and not the model's, in
    /// its initialiser — because a `@State`'s initial value expression runs on
    /// every initialisation of the struct holding it while `State` keeps only
    /// the first value. A model that registered itself would let a shell
    /// SwiftUI built and threw away swallow a request waiting from a cold
    /// launch, and take the router's weak reference down with it when it
    /// deallocated.
    ///
    /// What this pins is the half that is observable from here: a shell that
    /// was only built is not what the router answers through. The other half —
    /// that nothing in `RootShellModel` reaches `ScanRouter.shared` behind the
    /// suite's back — is structural rather than tested, and deliberately so:
    /// the initialiser takes no router and the file names the type nowhere, so
    /// there is no call for a test to catch.
    ///
    /// **The shared router is not usable here.** The test host is the Fuel app
    /// itself, so its own `RootShell` appears and registers the real shell with
    /// `ScanRouter.shared` before any of this runs — a suite that reached for
    /// it would be talking to the app around it.
    @Test("The router answers through the shell that registered, not the one built last")
    func routerAnswersThroughTheRegisteredShell() throws {
        let router = ScanRouter()
        let registered = try makeTodayModel()
        router.adopt(registered)

        // Built afterwards and never registered: what a discarded initial
        // value is, and what a self-registering initialiser would have made
        // the router point at.
        let unregistered = try makeTodayModel()

        router.requestScan()

        #expect(registered.destination == .logFlow)
        #expect(registered.logFlow.selectedTab == .camera)
        #expect(unregistered.destination == nil)
    }
}

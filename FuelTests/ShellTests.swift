import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Validator double

/// The shell has to hand `OnboardingModel` a validator to build it at all, and
/// the launch tests are not about the key. This one is never reached: none of
/// them submits one.
private nonisolated struct UnusedValidator: KeyValidating {

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        .retry
    }
}

// MARK: - Transport double

/// Answers every request with one recorded shape, or fails the way a lost
/// connection does.
///
/// **Nothing in this file reaches a provider.** A suite that spends the
/// runner's credit is not a suite anyone can run, and the point of these tests
/// is what the shell makes of an answer, not that a provider gave one.
private nonisolated struct StubTransport: HTTPTransport {

    let outcome: Result<HTTPResponse, TransportFailure>

    /// `URLError` and friends are not `Equatable` enough to write inline, and
    /// the two failures worth testing are the two the mapping treats
    /// differently, so they are named rather than constructed.
    enum TransportFailure: Error {
        case offline
        case cancelled
    }

    static func answering(_ status: Int, body: String = "") -> StubTransport {
        StubTransport(outcome: .success(HTTPResponse(statusCode: status, body: Data(body.utf8))))
    }

    static func failing(_ failure: TransportFailure) -> StubTransport {
        StubTransport(outcome: .failure(failure))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        switch outcome {
        case .success(let response): return response
        case .failure(.offline): throw URLError(.notConnectedToInternet)
        case .failure(.cancelled): throw CancellationError()
        }
    }
}

// MARK: - Camera doubles

/// Answers the key question without a keychain, which is what lets these tests
/// run without an access group and without ever holding a secret.
///
/// It always says yes. Whether the camera half goes dead without a key is
/// `CameraLogTests`' subject and is covered there; here a key has to exist for
/// the shutter to reach a stage worth reopening onto.
private nonisolated struct StubKeys: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { true }
}

/// A client no test in this file lets an estimate reach.
///
/// **Nothing here goes near a provider.** The shell's business with the camera
/// half is which one it is pointed at and when it is built, never what an
/// estimate comes back as — that is `CameraLogTests`' subject and it has its
/// own recorded shapes.
private nonisolated struct UnusedEstimator: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .failed(.cancelled) }

    func estimate(photo: MealPhoto) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }
}

/// A camera that opens nothing and counts the one thing this suite asks about.
///
/// Only `stop()` is counted. The shell never starts a session — the flow does
/// that when its tab appears — so a `startCount` here would be a number no
/// test could assert without pretending the shell had a part in it.
private final class StubCamera: MealCamera {

    private(set) var stopCount = 0

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() { stopCount += 1 }

    func capturePhoto() async throws -> UIImage { UIImage() }
}

/// A camera whose shutter fails, which is how a test drives the camera half
/// into a stage the viewfinder is not.
private final class FailingCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage { throw MealCameraError.unavailable }
}

/// Remembers which provider each log flow was built for.
private final class ProviderLog {

    private(set) var providers: [AIProvider] = []

    func record(_ provider: AIProvider) { providers.append(provider) }
}

// MARK: - Suite

@Suite("Shell")
@MainActor
struct ShellTests {

    // MARK: - Fixtures

    /// In memory, so a suite run leaves nothing on disk and one test's answers
    /// cannot decide the next test's launch.
    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true)
    }

    /// Never the app's suite: these tests write a provider preference, and a
    /// run must not change the provider Fuel opens on for whoever is on the
    /// machine.
    private func makePreferences() -> SettingsPreferences {
        let suite = "apps.levo-studio.Fuel.tests.shell.\(UUID().uuidString)"
        return SettingsPreferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func makeModel(
        store: FuelStore,
        preferences: SettingsPreferences? = nil,
        makeCameraLog: @escaping RootShellModel.CameraLogFactory = ShellTests.stubCameraLog
    ) -> RootShellModel {
        RootShellModel(
            store: store,
            validator: UnusedValidator(),
            preferences: preferences ?? makePreferences(),
            makeCameraLog: makeCameraLog
        )
    }

    /// The camera half, with nothing behind it that could reach a provider, a
    /// keychain or a lens.
    private static let stubCameraLog: RootShellModel.CameraLogFactory = { store, provider in
        CameraLogModel(
            store: store,
            client: UnusedEstimator(),
            camera: StubCamera(),
            keys: StubKeys(),
            provider: provider
        )
    }

    // MARK: - Launch decision

    @Test("A store with no settings row opens on onboarding")
    func opensOnOnboardingWithoutSettings() throws {
        let store = try makeStore()
        #expect(try store.existingGoalSettings() == nil)

        #expect(makeModel(store: store).stage == .onboarding)
    }

    @Test("A store with a settings row opens on Today")
    func opensOnTodayWithSettings() throws {
        let store = try makeStore()
        try store.setCountingMode(.goal(.default))

        #expect(makeModel(store: store).stage == .today)
    }

    /// Count-only writes no goal, so it is the case where a shell that looked
    /// for a *target* rather than for the row would ask the questions again.
    @Test("Count-only counts as answered")
    func countOnlyOpensOnToday() throws {
        let store = try makeStore()
        try store.setCountingMode(.countOnly)

        let model = makeModel(store: store)
        #expect(model.stage == .today)
        #expect(model.today.showsRing == false)
    }

    // MARK: - Finishing onboarding

    @Test("Completing onboarding moves to Today without a relaunch")
    func completingOnboardingMovesToToday() throws {
        let store = try makeStore()
        let model = makeModel(store: store)
        #expect(model.stage == .onboarding)

        model.onboarding.selectGoalMode()
        #expect(model.onboarding.complete())

        #expect(model.stage == .today)
        #expect(model.today.showsRing)
    }

    /// The transition re-reads the store rather than trusting what the flow
    /// held, which is what makes the mode the user chose the one Today draws.
    @Test("The mode chosen in onboarding is the mode Today opens in")
    func countOnlyChoiceReachesToday() throws {
        let store = try makeStore()
        let model = makeModel(store: store)

        model.onboarding.selectCountOnly()
        #expect(model.onboarding.complete())

        #expect(model.stage == .today)
        #expect(model.today.showsRing == false)
    }

    // MARK: - Leaving and returning to Today

    /// A meal to hand the log flow. Built rather than read back out of the
    /// store, because what is under test is the shell's refresh and not how a
    /// Recent row is assembled.
    private static let meal = RecentMeal(
        id: UUID(),
        title: "Oats with skyr",
        kilocalories: 420,
        macros: MacroTotals(protein: 30, carbs: 55, fat: 9)
    )

    private func makeTodayModel() throws -> (FuelStore, RootShellModel) {
        let store = try makeStore()
        try store.setCountingMode(.goal(.default))
        return (store, makeModel(store: store))
    }

    @Test("The plus opens the log flow")
    func plusOpensTheLogFlow() throws {
        let (_, model) = try makeTodayModel()
        #expect(model.destination == nil)

        model.openLogFlow()
        #expect(model.destination == .logFlow)
    }

    /// Screen 07 is the entry into the flow, so a flow opened a second time
    /// opens where the first one did rather than where it was left.
    @Test("A reopened log flow starts on the camera tab")
    func reopenedFlowStartsOnCamera() throws {
        let (_, model) = try makeTodayModel()

        model.openLogFlow()
        model.logFlow.selectedTab = .recent
        model.dismissDestination()

        model.openLogFlow()
        #expect(model.logFlow.selectedTab == .camera)
    }

    /// The one the refresh exists for: `today` is worked out from a fetch and
    /// not a live query, so without the re-read on dismissal the meal is in
    /// the store and nowhere on the screen.
    @Test("A meal logged in the flow is on Today when the flow closes")
    func loggingRefreshesToday() throws {
        let (_, model) = try makeTodayModel()
        #expect(model.today.totals.kilocalories == 0)
        #expect(model.today.groups.isEmpty)

        model.openLogFlow()
        #expect(model.logFlow.log(Self.meal))
        model.dismissDestination()

        #expect(model.destination == nil)
        #expect(model.today.totals.kilocalories == 420)
        #expect(model.today.totals.macros.protein == 30)
        // In a meal section, not merely in the totals.
        #expect(model.today.groups.count == 1)
        #expect(model.today.groups.first?.entries.count == 1)
    }

    @Test("Cancelling the flow writes nothing")
    func cancellingWritesNothing() throws {
        let (store, model) = try makeTodayModel()

        model.openLogFlow()
        model.dismissDestination()

        #expect(model.destination == nil)
        #expect(try store.entries(on: Date()).isEmpty)
        #expect(model.today.totals.kilocalories == 0)
        #expect(model.today.groups.isEmpty)
    }

    /// The camera half is rebuilt with the flow for a reason `LogFlowModel`
    /// does not have: it carries a stage. A flow abandoned on a failed scan
    /// would otherwise reopen onto that failure rather than onto the
    /// viewfinder screen 07 draws.
    @Test("A reopened flow is back at the viewfinder, whatever the last scan ended on")
    func reopenedFlowResetsTheCameraHalf() async throws {
        let (store, _) = try makeTodayModel()
        let model = makeModel(store: store) { store, provider in
            CameraLogModel(
                store: store,
                client: UnusedEstimator(),
                camera: FailingCamera(),
                keys: StubKeys(),
                provider: provider
            )
        }

        model.openLogFlow()
        await model.cameraLog.capture()
        #expect(model.cameraLog.stage == .failed(.retry))

        model.dismissDestination()
        model.openLogFlow()
        #expect(model.cameraLog.stage == .viewfinder)
        #expect(model.cameraLog.photo == nil)
    }

    /// What this pins is the read: the provider a flow is built for is taken
    /// when the flow opens, not held from launch, so switching the segment on
    /// screen 16 and scanning straight afterwards is built for the provider
    /// the user just chose.
    ///
    /// It does not pin what that provider is then spent on. The factory is
    /// replaced here, and the real one keeps its client and the provider it
    /// looks a key up under private — the suite cannot see either. That the
    /// two agree is structural rather than tested: `liveCameraLog` takes one
    /// provider and passes it to both, so there is no second source for them
    /// to drift apart from.
    @Test("The provider selected in Settings is the one the next scan is built for")
    func providerPreferenceReachesTheFlow() throws {
        let (store, _) = try makeTodayModel()
        let preferences = makePreferences()
        let providers = ProviderLog()
        let model = makeModel(store: store, preferences: preferences) { store, provider in
            providers.record(provider)
            return ShellTests.stubCameraLog(store, provider)
        }

        #expect(preferences.provider == .claude)
        #expect(providers.providers == [.claude])

        preferences.provider = .mistral
        model.openLogFlow()

        #expect(providers.providers.last == .mistral)
    }

    /// The session outliving the cover is the bug this closes: the flow stops
    /// it when the tab changes, and a dismissal is not a tab change.
    @Test("Dismissing the flow stops the capture session")
    func dismissingStopsTheCamera() throws {
        let (store, _) = try makeTodayModel()
        let camera = StubCamera()
        let model = makeModel(store: store) { store, provider in
            CameraLogModel(
                store: store,
                client: UnusedEstimator(),
                camera: camera,
                keys: StubKeys(),
                provider: provider
            )
        }

        model.openLogFlow()
        #expect(camera.stopCount == 0)

        model.dismissDestination()
        #expect(camera.stopCount == 1)
    }

    @Test("The gear opens Settings")
    func gearOpensSettings() throws {
        let (_, model) = try makeTodayModel()

        model.openSettings()
        #expect(model.destination == .settings)
    }

    /// Screen 17's counting control is the preference that changes what Today
    /// draws rather than how it is tinted: goal mode has a ring and count-only
    /// has none. Driven through Settings' own model, so what is under test is
    /// the whole way back — the control writes, and Today re-reads on the way
    /// out.
    @Test("A counting mode changed in Settings is what Today draws afterwards")
    func settingsChangeReachesToday() throws {
        let (_, model) = try makeTodayModel()
        #expect(model.today.showsRing)

        model.openSettings()
        model.settingsCounting?.choice = .countOnly
        model.dismissDestination()

        #expect(model.today.showsRing == false)
    }

    // MARK: - The validator seam

    /// Shaped like a real key and is not one. No real key belongs in a
    /// repository, least of all a public one.
    private static let claudeKey = APIKey("sk-ant-api03-000000000000000000000000")

    private func outcome(
        from transport: StubTransport,
        provider: AIProvider = .claude
    ) async -> KeyValidationOutcome {
        await ProviderKeyValidator(transport: transport).validate(Self.claudeKey, for: provider)
    }

    @Test("A provider that answers normally passes the key")
    func passingKeyValidates() async {
        let body = #"{"content":[{"type":"text","text":"Hi"}]}"#
        #expect(await outcome(from: .answering(200, body: body)) == .passed)
    }

    @Test("A refused key is reported as refused, not as a retry", arguments: [401, 403])
    func refusedKey(status: Int) async {
        #expect(await outcome(from: .answering(status)) == .invalidKey)
    }

    /// The signal is the body, not the status — which is why this arrives as a
    /// `400` rather than as something that looks like a payment error.
    @Test("An exhausted balance is reported as no credit")
    func exhaustedBalance() async {
        let body = #"{"error":{"message":"Your credit balance is too low to access the API."}}"#
        #expect(await outcome(from: .answering(400, body: body)) == .noCredit)
    }

    /// A throttled user has to wait, not top up. Reading this as no-credit
    /// would send someone with a full balance to a billing page.
    @Test("A rate limit is a retry, not a billing problem")
    func rateLimited() async {
        #expect(await outcome(from: .answering(429)) == .retry)
    }

    @Test("Nothing reached means nothing is known about the key")
    func offline() async {
        #expect(await outcome(from: .failing(.offline)) == .retry)
        #expect(await outcome(from: .failing(.cancelled)) == .retry)
    }

    /// Both providers go through the same narrowing, so the shell cannot pass
    /// a key on one and refuse it on the other.
    @Test("Mistral is validated through the same mapping")
    func mistralUsesTheSameMapping() async {
        #expect(await outcome(from: .answering(401), provider: .mistral) == .invalidKey)
        #expect(await outcome(from: .answering(200, body: "{}"), provider: .mistral) == .passed)
    }
}

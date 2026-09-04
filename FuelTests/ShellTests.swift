import Foundation
import Testing
import UIKit

@testable import Fuel

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

/// A client whose estimate fails, which is how a test drives the text half into
/// a stage the entry field is not.
///
/// It is the text mode's `BrokenCamera`: what the shell is asked about is
/// whether a flow reopens on that stage, never what the failure says.
private nonisolated struct FailingEstimator: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .failed(.network) }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate { throw AIError.network }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.network }
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

    /// Never the app's service, for the reason `KeychainStore` gives at
    /// length: a test that wrote to it would clobber the real key of whoever
    /// is running the suite, and the cleanup below would delete it.
    private func makeKeychain() -> KeychainStore {
        KeychainStore(service: "apps.levo-studio.Fuel.tests.shell.\(UUID().uuidString)")
    }

    private func clear(_ keychain: KeychainStore) {
        for provider in AIProvider.allCases {
            try? keychain.deleteKey(for: provider)
        }
    }

    private func makeModel(
        store: FuelStore,
        preferences: SettingsPreferences? = nil,
        makeCameraLog: @escaping RootShellModel.CameraLogFactory = ShellTests.stubCameraLog,
        makeTextLog: @escaping RootShellModel.TextLogFactory = ShellTests.stubTextLog,
        makeMealDetail: @escaping RootShellModel.MealDetailFactory = ShellTests.stubMealDetail
    ) -> RootShellModel {
        RootShellModel(
            store: store,
            validator: UnusedValidator(),
            preferences: preferences ?? makePreferences(),
            makeCameraLog: makeCameraLog,
            makeTextLog: makeTextLog,
            makeMealDetail: makeMealDetail
        )
    }

    /// The camera half, with nothing behind it that could reach a provider, a
    /// keychain or a lens.
    private static let stubCameraLog: RootShellModel.CameraLogFactory = { store, provider in
        CameraLogModel(
            store: store,
            client: UnusedEstimator(),
            camera: CountingCamera(),
            keys: StubKeys(),
            provider: provider
        )
    }

    /// The text half, with nothing behind it that could reach a provider or a
    /// keychain. The steps are walked instantly: what this suite asks about is
    /// which stage a reopened flow is on, not how long the bar takes.
    private static let stubTextLog: RootShellModel.TextLogFactory = { store, provider in
        TextLogModel(
            store: store,
            client: UnusedEstimator(),
            keys: StubKeys(),
            provider: provider,
            pace: {}
        )
    }

    /// The screen a logged meal opens on, with nothing behind it that could
    /// reach a provider or a keychain. What this suite asks it is whether a tap
    /// gets there and what a deletion leaves on Today, never what an estimate
    /// comes back as.
    private static let stubMealDetail: RootShellModel.MealDetailFactory = { store, provider, entryID in
        MealDetailModel(
            entryID: entryID,
            store: store,
            client: UnusedEstimator(),
            keys: StubKeys(),
            provider: provider,
            pace: {}
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

    // MARK: - The get-started checklist

    /// The state the owner looked at: onboarding answered, nothing logged, the
    /// appearance Fuel ships with.
    @Test("A first run has nothing on the checklist done")
    func firstRunChecklist() throws {
        let store = try makeStore()
        try store.setCountingMode(.countOnly)

        let model = makeModel(store: store)
        #expect(model.gettingStarted.items.allSatisfy { $0.isDone == false })
        #expect(model.gettingStarted.isOffered)
    }

    /// The shipped theme and accent are not a choice the user made, so each row
    /// stays open until its own control differs.
    @Test("The theme and the accent tick their own rows")
    func appearanceRows() throws {
        let store = try makeStore()
        try store.setCountingMode(.countOnly)

        let preferences = makePreferences()
        let untouched = makeModel(store: store, preferences: preferences).gettingStarted
        #expect(untouched.isDone(.theme) == false)
        #expect(untouched.isDone(.accent) == false)

        preferences.accent = .blue
        let accented = makeModel(store: store, preferences: preferences).gettingStarted
        #expect(accented.isDone(.accent))
        #expect(accented.isDone(.theme) == false)

        preferences.theme = .light
        #expect(makeModel(store: store, preferences: preferences).gettingStarted.isDone(.theme))
    }

    /// The row that would un-tick itself at midnight if it asked about today.
    @Test("A meal logged on another day still ticks the meal row")
    func mealRow() throws {
        let store = try makeStore()
        try store.setCountingMode(.countOnly)
        let lastWeek = try #require(Calendar.current.date(byAdding: .day, value: -7, to: Date()))
        try store.log(
            title: "Porridge",
            kilocalories: 420,
            macros: .zero,
            loggedAt: lastWeek,
            source: .photo
        )

        let model = makeModel(store: store)
        #expect(model.today.hasEntries == false)
        #expect(model.gettingStarted.isDone(.firstMeal))
        // And the whole checklist is retired by it, on a day with nothing in.
        #expect(model.gettingStarted.isOffered == false)
    }

    /// The checklist is read from places a presented cover can change, so it is
    /// re-read where the day is.
    @Test("Dismissing a cover re-reads the checklist")
    func checklistIsRefreshedOnDismissal() throws {
        let store = try makeStore()
        try store.setCountingMode(.countOnly)

        let preferences = makePreferences()
        let model = makeModel(store: store, preferences: preferences)
        #expect(model.gettingStarted.isDone(.accent) == false)

        model.openSettings()
        preferences.accent = .lilac
        model.dismissDestination()

        #expect(model.gettingStarted.isDone(.accent))
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
                camera: BrokenCamera(),
                keys: StubKeys(),
                provider: provider
            )
        }

        model.openLogFlow()
        await model.cameraLog.capture()
        #expect(model.cameraLog.stage == .failed(.retry(.device)))

        model.dismissDestination()
        model.openLogFlow()
        #expect(model.cameraLog.stage == .viewfinder)
        #expect(model.cameraLog.photo == nil)
    }

    /// The text half is rebuilt with the flow for the camera half's reason and
    /// one more: it carries the sentence the user typed. A flow abandoned on a
    /// failed estimate would otherwise reopen onto that failure, with the
    /// abandoned meal still in the field.
    @Test("A reopened flow is back at the text entry, with nothing left in the field")
    func reopenedFlowResetsTheTextHalf() async throws {
        let (store, _) = try makeTodayModel()
        let model = makeModel(store: store) { store, provider in
            ShellTests.stubCameraLog(store, provider)
        } makeTextLog: { store, provider in
            TextLogModel(
                store: store,
                client: FailingEstimator(),
                keys: StubKeys(),
                provider: provider,
                pace: {}
            )
        }

        model.openLogFlow()
        model.textLog.typedText = "2 eggs with 200g cottage cheese and polenta"
        model.textLog.analyse()
        while case .analysing = model.textLog.stage {
            await Task.yield()
        }
        #expect(model.textLog.stage == .failed(.retry(.transport)))

        model.dismissDestination()
        model.openLogFlow()

        #expect(model.textLog.stage == .entry)
        #expect(model.textLog.typedText.isEmpty)
        #expect(model.textLog.draft == nil)
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

    /// The whole product, broken at first launch, for anyone who picked
    /// Mistral: onboarding stored the key under Mistral and kept the choice to
    /// itself, so the flow was built for Claude, the presence check asked for
    /// a Claude key that did not exist, and both the shutter and `Analyse`
    /// went dead in front of a working account with nothing on screen to say
    /// why.
    ///
    /// It drives the real path and it asks the question the user would: not
    /// whether a preference was written, but whether the shutter works. The
    /// camera half is built against the same Keychain onboarding wrote to, so
    /// `refreshAvailability` answers from the stored item rather than from a
    /// stand-in that says yes to everything.
    @Test("The provider chosen during onboarding is the one the first scan is built for")
    func onboardingProviderReachesTheFirstScan() async throws {
        let keychain = makeKeychain()
        defer { clear(keychain) }
        let store = try makeStore()
        let preferences = makePreferences()
        let providers = ProviderLog()
        let model = RootShellModel(
            store: store,
            validator: StubValidator(outcome: .passed),
            preferences: preferences,
            keychain: keychain,
            makeCameraLog: { store, provider in
                providers.record(provider)
                return CameraLogModel(
                    store: store,
                    client: UnusedEstimator(),
                    camera: CountingCamera(),
                    keys: keychain,
                    provider: provider
                )
            },
            makeTextLog: ShellTests.stubTextLog
        )

        #expect(model.stage == .onboarding)

        model.onboarding.selectProvider(.mistral)
        model.onboarding.keyDraft = OnboardingTests.mistralKey
        model.onboarding.submitKey()
        await model.onboarding.validation?.value
        model.onboarding.continueFromKeyTest()
        model.onboarding.selectGoalMode()
        #expect(model.onboarding.complete())

        #expect(model.stage == .today)

        model.openLogFlow()

        #expect(providers.providers.last == .mistral)

        // The question the user asks by pressing it.
        model.cameraLog.refreshAvailability()
        #expect(model.cameraLog.stage == .viewfinder)

        // One entry per provider, and only the chosen one was written.
        #expect(keychain.hasKey(for: .mistral))
        #expect(!keychain.hasKey(for: .claude))
    }

    /// One flow, one provider. The two halves are built from a single read, so
    /// there is no window in which a camera tab talks to one provider and the
    /// text tab beside it to another.
    @Test("Both halves of a flow are built for the same provider")
    func bothHalvesShareOneProvider() throws {
        let (store, _) = try makeTodayModel()
        let preferences = makePreferences()
        let cameraProviders = ProviderLog()
        let textProviders = ProviderLog()
        let model = makeModel(store: store, preferences: preferences) { store, provider in
            cameraProviders.record(provider)
            return ShellTests.stubCameraLog(store, provider)
        } makeTextLog: { store, provider in
            textProviders.record(provider)
            return ShellTests.stubTextLog(store, provider)
        }

        #expect(cameraProviders.providers == [.claude])
        #expect(textProviders.providers == [.claude])

        preferences.provider = .mistral
        model.openLogFlow()

        #expect(cameraProviders.providers == [.claude, .mistral])
        #expect(textProviders.providers == cameraProviders.providers)
    }

    /// The session outliving the cover is the bug this closes: the flow stops
    /// it when the tab changes, and a dismissal is not a tab change.
    @Test("Dismissing the flow stops the capture session")
    func dismissingStopsTheCamera() throws {
        let (store, _) = try makeTodayModel()
        let camera = CountingCamera()
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

    // MARK: - Opening a logged meal

    /// A meal to open the detail screen on, written through the store because
    /// the screen is opened on a row rather than on a value.
    @discardableResult
    private func logMeal(in store: FuelStore, title: String = "Oats with skyr") throws -> FoodEntry {
        try store.log(
            title: title,
            kilocalories: 420,
            macros: MacroTotals(protein: 30, carbs: 55, fat: 9),
            loggedAt: Date(),
            source: .photo
        )
    }

    /// The screen is **pushed**, and the assertion on `destination` is the
    /// point of the test rather than a leftover. It is the one destination the
    /// export draws no frame for, it is reached by tapping a row in a list, and
    /// a push is what iOS does for that — so it must not be a cover, and a
    /// future change that made it one again would fail here.
    @Test("Tapping a meal on Today pushes it rather than presenting it")
    func tappingAMealOpensIt() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)

        #expect(model.pushedMeal == entry.entryID)
        #expect(model.destination == nil)
        #expect(model.mealDetail?.draft.title == "Oats with skyr")
    }

    /// What the shell asks before it lets the system's back-swipe through.
    ///
    /// An untouched screen answers `false`, exactly as `‹ Back` is immediate on
    /// one: a confirmation on a screen with nothing at stake would be a dialog
    /// in front of nothing.
    @Test("A meal nobody edited can be left without a question")
    func leavingAnUntouchedMealAsksNothing() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)

        #expect(model.mealDetailDiscardsEdits == false)
    }

    /// The reason the interactive pop is intercepted rather than taken as it
    /// arrives. A previous round found `‹ Back` destroying corrections
    /// silently; a system gesture that popped straight through would be the
    /// same bug reached a different way.
    @Test("A meal with breakdown edits cannot be left silently")
    func leavingAnEditedMealAsksFirst() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)
        model.mealDetail?.addItem("Olive oil, 1 tbsp")

        #expect(model.mealDetailDiscardsEdits)
        // Nothing has left yet: the question is asked, and the screen is still
        // on the stack until it is answered.
        #expect(model.pushedMeal == entry.entryID)
    }

    /// `hasItemEdits` and not "anything at all was touched". The pill writes
    /// straight to the store and is undone in one tap, so gating on it would
    /// put the dialog in front of nothing.
    @Test("A relabelled meal is not an edited one")
    func relabellingDoesNotRaiseTheQuestion() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)
        model.mealDetail?.cycleLabel()

        #expect(model.mealDetailDiscardsEdits == false)
    }

    /// The screen is not there to be asked about once it is gone.
    @Test("With no meal open there is nothing to ask about")
    func noMealOpenAsksNothing() throws {
        let (_, model) = try makeTodayModel()

        #expect(model.mealDetailDiscardsEdits == false)
    }

    /// A row for a meal that is no longer there leaves the tap unanswered
    /// rather than presenting a screen with nothing on it.
    @Test("A meal that is not in the store opens nothing")
    func tappingAMissingMealOpensNothing() throws {
        let (_, model) = try makeTodayModel()

        model.openMealDetail(UUID())

        #expect(model.pushedMeal == nil)
        #expect(model.mealDetail == nil)
    }

    /// The screen carries a draft the user may have edited without asking for
    /// it to be priced, so it is released when it pops.
    @Test("Closing a meal releases the screen it was on")
    func closingAMealReleasesTheScreen() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)
        model.mealDetail?.addItem("Olive oil, 1 tbsp")
        model.dismissMealDetail()

        #expect(model.pushedMeal == nil)
        #expect(model.mealDetail == nil)

        model.openMealDetail(entry.entryID)
        #expect(model.mealDetail?.draft.hasItemEdits == false)
    }

    /// The refresh the day list needs: `today` is worked out from a fetch and
    /// not a live query, so without the re-read on dismissal a deleted meal is
    /// gone from the store and still on the screen.
    @Test("A meal deleted on its own screen is off Today when the screen closes")
    func deletingRefreshesToday() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)
        model.dismissDestination()
        #expect(model.today.totals.kilocalories == 420)

        model.openMealDetail(entry.entryID)
        #expect(model.mealDetail?.delete() == true)
        model.dismissMealDetail()

        #expect(model.today.totals.kilocalories == 0)
        #expect(model.today.groups.isEmpty)
    }

    /// The shortcut asks for the camera, not for the camera on top of a meal
    /// the user would find again on the way out — so the push is popped the way
    /// its own `‹ Back` pops it before the flow opens.
    @Test("A scan request from a meal lands on the camera")
    func scanRequestFromAMeal() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)
        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.pushedMeal == nil)
        #expect(model.mealDetail == nil)
        #expect(model.logFlow.selectedTab == .camera)
    }

    /// A request from outside is not the user leaving, so it is not asked
    /// about: the dialog stands in front of the gesture and the drawn control,
    /// and raising it here would ask a question nobody on this screen asked.
    /// The stored meal is untouched either way.
    @Test("A scan request does not stop at the discard question")
    func scanRequestFromAnEditedMeal() throws {
        let (store, model) = try makeTodayModel()
        let entry = try logMeal(in: store)

        model.openMealDetail(entry.entryID)
        model.mealDetail?.addItem("Olive oil, 1 tbsp")
        model.requestScan()

        #expect(model.destination == .logFlow)
        #expect(model.pushedMeal == nil)
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

import Foundation
import Testing

@testable import Fuel

// MARK: - Validator double

/// The shell has to hand `OnboardingModel` a validator to build it at all, and
/// none of these tests are about the key. This one is never reached: no test
/// below submits a key.
private nonisolated struct UnusedValidator: KeyValidating {

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        .retry
    }
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

    private func makeModel(store: FuelStore) -> RootShellModel {
        RootShellModel(store: store, validator: UnusedValidator())
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
}

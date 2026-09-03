import Foundation
import Testing

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

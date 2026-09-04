import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Stand-ins

/// The pieces the AI log modes and the two shell suites are tested against.
///
/// **Nothing here reaches a network or a Keychain.** The client answers from
/// memory and the key answers a `Bool`, so a camera test and a text test run on
/// the same evidence whatever the machine's connection is doing and without a
/// keychain-access group.
///
/// Shared rather than declared twice: the request count in particular is load
/// bearing in both suites — a mode that is drawn as unavailable and still sends
/// the request passes any test that only looks at the stage.

/// Answers estimates, from memory, and counts how often it was asked.
///
/// A list rather than a single answer, because a re-analysis is a second
/// request about the same meal: a test that pins one has to be able to tell the
/// new estimate from the old. The last answer repeats, so the ordinary case —
/// one answer, however many requests — is still `init(answer:)`.
final class ScriptedClient: AIClient, @unchecked Sendable {

    let provider: AIProvider = .claude

    private let answers: [Result<MealEstimate, AIError>]
    private let adjustments: [Result<MealAdjustmentOutcome, AIError>]
    private(set) var requests = 0

    /// The last sentence it was asked about, so a test can check that a retry
    /// sends what the user actually typed, and that a re-analysis sends the
    /// edited list. Never printed anywhere.
    private(set) var lastText: String?

    /// The note that came with the last photo, so a test can check that what
    /// the user typed under the viewfinder is what the scan handed over — and
    /// that an empty field hands over nothing. Never printed anywhere either.
    private(set) var lastPhotoContext: String?

    // MARK: - Adjustments

    /// Counted apart from `requests`, because a screen that talks about a meal
    /// and a screen that re-analyses one both spend the user's credit and a
    /// test has to be able to say which of the two happened.
    private(set) var adjustRequests = 0

    private(set) var lastAdjustedMeal: AdjustableMeal?
    private(set) var lastHistory: [MealChatTurn] = []
    private(set) var lastMessage: String?

    convenience init(answer: Result<MealEstimate, AIError>) {
        self.init(answers: [answer])
    }

    init(
        answers: [Result<MealEstimate, AIError>] = [.failure(.cancelled)],
        adjustments: [Result<MealAdjustmentOutcome, AIError>] = [.failure(.cancelled)]
    ) {
        self.answers = answers
        self.adjustments = adjustments
    }

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate {
        lastPhotoContext = context
        return try next()
    }

    func estimate(text: String) async throws -> MealEstimate {
        lastText = text
        return try next()
    }

    /// The scripted answer, with the request recorded rather than applied.
    ///
    /// **The outcome is handed over whole**, so a model test says what came
    /// back without also re-testing `MealAdjuster` — what a reply does to a
    /// meal is that type's subject, and it has a suite of its own against the
    /// real table.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) async throws -> MealAdjustmentOutcome {
        lastAdjustedMeal = meal
        lastHistory = history
        lastMessage = message
        let answer = adjustments[min(adjustRequests, adjustments.count - 1)]
        adjustRequests += 1
        return try answer.get()
    }

    private func next() throws -> MealEstimate {
        let answer = answers[min(requests, answers.count - 1)]
        requests += 1
        return try answer.get()
    }
}

/// No key for any provider.
struct NoKeys: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { false }
}

/// A key for every provider.
struct StoredKey: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { true }
}

/// A key that can be added or taken away between two questions, which is what
/// Settings does while the app is running.
final class MutableKeys: MealKeyPresence, @unchecked Sendable {

    var hasKey: Bool

    init(hasKey: Bool) {
        self.hasKey = hasKey
    }

    func hasKey(for provider: AIProvider) -> Bool { hasKey }
}

// MARK: - Shell stand-ins

/// A validator no suite lets a key reach.
///
/// The shell has to be handed one to build `OnboardingModel` at all, and the
/// suites that build a shell to ask where it navigates never submit a key.
nonisolated struct UnusedValidator: KeyValidating {

    func validate(_ key: APIKey, for provider: AIProvider) async -> KeyValidationOutcome {
        .retry
    }
}

/// A client no suite lets an estimate reach.
///
/// **Nothing here goes near a provider.** What a shell is asked about is which
/// screen it lands on and which provider a flow was built for, never what an
/// estimate comes back as — that is the log modes' subject, and they have
/// `ScriptedClient` and recorded response shapes for it.
nonisolated struct UnusedEstimator: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .failed(.cancelled) }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }

    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) async throws -> MealAdjustmentOutcome {
        throw AIError.cancelled
    }
}

/// A camera that opens nothing and counts the one thing a shell can be asked
/// about.
///
/// Only `stop()` is counted. A shell never starts a session — the flow does
/// that when its tab appears — so a `startCount` here would be a number no test
/// could assert without pretending the shell had a part in it.
@MainActor
final class CountingCamera: MealCamera {

    private(set) var stopCount = 0

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() { stopCount += 1 }

    func capturePhoto() async throws -> UIImage { UIImage() }
}

/// A camera whose shutter fails, which is how a test drives the camera half
/// into a stage the viewfinder is not.
@MainActor
final class BrokenCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage { throw MealCameraError.unavailable }
}

// MARK: - Overlapping requests

/// A client that holds every request open until it is let go, one at a time.
///
/// `ScriptedClient` answers before the caller can do anything else, which
/// makes two estimates in flight at once impossible to build — and two in
/// flight at once is the only situation in which one of them can be stale.
/// This is the same recorded-answer idea with the answer withheld: a test
/// starts a request, does whatever the user would have done in the meantime,
/// and then releases the answers in the order it wants them to arrive.
///
/// **Still nothing near a network.** The answers are values handed to the
/// initialiser.
final class GatedClient: AIClient, @unchecked Sendable {

    let provider: AIProvider = .claude

    private let lock = NSLock()
    private let answers: [Result<MealEstimate, AIError>]
    private let adjustments: [Result<MealAdjustmentOutcome, AIError>]
    private var started = 0
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

    init(
        answers: [Result<MealEstimate, AIError>] = [.failure(.cancelled)],
        adjustments: [Result<MealAdjustmentOutcome, AIError>] = [.failure(.cancelled)]
    ) {
        self.answers = answers
        self.adjustments = adjustments
    }

    /// How many requests have been made and are waiting to be let go or have
    /// already been.
    var requests: Int {
        lock.withLock { started }
    }

    /// Lets request number `index` answer, counting from zero. Does nothing if
    /// it is not waiting.
    ///
    /// By index rather than in order, because the order the answers arrive in
    /// is exactly what the stale-run tests are about: a request that was
    /// abandoned can come back after the one that replaced it, and a queue
    /// could only ever produce the other case.
    func release(_ index: Int) {
        let waiter: CheckedContinuation<Void, Never>? = lock.withLock {
            waiting.removeValue(forKey: index)
        }
        waiter?.resume()
    }

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate {
        try await next()
    }

    func estimate(text: String) async throws -> MealEstimate {
        try await next()
    }

    /// A conversation held open the same way, and counted in the same
    /// sequence: a screen that can re-analyse and talk at once has two kinds
    /// of request in flight, and `release(_:)` has to be able to name either.
    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) async throws -> MealAdjustmentOutcome {
        let index = await waitForTurn()
        return try adjustments[min(index, adjustments.count - 1)].get()
    }

    private func next() async throws -> MealEstimate {
        let index = await waitForTurn()
        return try answers[min(index, answers.count - 1)].get()
    }

    private func waitForTurn() async -> Int {
        let index: Int = lock.withLock {
            defer { started += 1 }
            return started
        }

        await withCheckedContinuation { continuation in
            lock.withLock { waiting[index] = continuation }
        }

        return index
    }
}

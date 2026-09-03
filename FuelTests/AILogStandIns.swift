import Foundation
import Testing

@testable import Fuel

// MARK: - Stand-ins

/// The pieces both AI log modes are tested against.
///
/// **Nothing here reaches a network or a Keychain.** The client answers from
/// memory and the key answers a `Bool`, so a camera test and a text test run on
/// the same evidence whatever the machine's connection is doing and without a
/// keychain-access group.
///
/// Shared rather than declared twice: the request count in particular is load
/// bearing in both suites — a mode that is drawn as unavailable and still sends
/// the request passes any test that only looks at the stage.

/// Answers one estimate, from memory, and counts how often it was asked.
final class ScriptedClient: AIClient, @unchecked Sendable {

    let provider: AIProvider = .claude

    private let answer: Result<MealEstimate, AIError>
    private(set) var requests = 0

    /// The last sentence it was asked about, so a test can check that a retry
    /// sends what the user actually typed. Never printed anywhere.
    private(set) var lastText: String?

    init(answer: Result<MealEstimate, AIError>) {
        self.answer = answer
    }

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto) async throws -> MealEstimate {
        requests += 1
        return try answer.get()
    }

    func estimate(text: String) async throws -> MealEstimate {
        requests += 1
        lastText = text
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

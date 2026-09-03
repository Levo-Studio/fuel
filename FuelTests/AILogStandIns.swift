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

    func estimate(photo: MealPhoto) async throws -> MealEstimate { throw AIError.cancelled }

    func estimate(text: String) async throws -> MealEstimate { throw AIError.cancelled }
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

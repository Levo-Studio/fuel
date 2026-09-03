import Foundation

// MARK: - Key presence

/// Whether a provider key exists, without reading one.
///
/// The whole feature asks exactly this question and never the other one. A
/// protocol rather than a `KeychainStore` parameter so a test can answer it
/// without a keychain-access group, and so nothing in the log flow is even
/// able to pull a secret into memory: `hasKey(for:)` is the only method, and
/// `KeychainStore` implements it by asking the Keychain for an item's presence
/// with `kSecReturnData` off.
nonisolated protocol MealKeyPresence: Sendable {

    func hasKey(for provider: AIProvider) -> Bool
}

extension KeychainStore: MealKeyPresence {}

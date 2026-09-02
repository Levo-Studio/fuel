import Foundation

// MARK: - Provider

/// The AI providers Fuel can talk to.
///
/// There are exactly two cases and there is no `case other(String)` escape
/// hatch. Adding a third provider is a product decision — it changes the
/// Settings segment, the model labels drawn in the design, and the shape of the
/// request Fuel sends — so it belongs to the owner, not to whoever happens to
/// be editing this file. A closed enum makes that visible: a new provider
/// cannot slip in as a string literal at some call site.
nonisolated enum AIProvider: String, CaseIterable, Sendable {

    /// Anthropic's Claude, reached directly at `api.anthropic.com`.
    case claude

    /// Mistral, reached directly at Mistral's endpoint.
    case mistral

    // MARK: - Keychain identity

    /// The Keychain account name for this provider's key.
    ///
    /// One account per provider, under a single service, is what lets a user
    /// hold a Claude key and a Mistral key at the same time and switch between
    /// them without losing the one they are not currently using.
    ///
    /// The value is derived from `rawValue`, so it is stable as long as the raw
    /// values are. Renaming a case's raw value orphans the key already stored
    /// on a user's device — the item stays in the Keychain, unreachable, and
    /// the user is asked for a key they already gave. Do not rename these.
    var keychainAccount: String {
        rawValue
    }
}

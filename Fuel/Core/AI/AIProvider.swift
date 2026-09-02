import Foundation

// MARK: - Provider

/// The AI providers Fuel can talk to.
///
/// This is a domain concept, not a storage detail. The provider decides which
/// endpoint a request goes to, which request shape it has, which model label
/// the design draws, and which segment is selected on screen 01. The Keychain
/// happens to file a key per provider, but it does not own the idea of one —
/// which is why the type lives here and the mapping onto a Keychain account
/// lives in `KeychainStore`.
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
}

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
///
/// Deliberately without a raw value. It had one, and nothing read it once the
/// Keychain account names were spelled out in `KeychainStore` — and an unused
/// `String` representation sitting on a provider enum is an invitation to
/// derive storage keys from it, which is precisely the mistake the hazard
/// comment on `KeychainStore.account(for:)` exists to prevent. Whatever needs
/// a string for a provider — a persisted Settings selection, a request header —
/// should say so where it needs it, and own the consequences of renaming it.
nonisolated enum AIProvider: CaseIterable, Sendable {

    /// Anthropic's Claude, reached directly at `api.anthropic.com`.
    case claude

    /// Mistral, reached directly at Mistral's endpoint.
    case mistral
}

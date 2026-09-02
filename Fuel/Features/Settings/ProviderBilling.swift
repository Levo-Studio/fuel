import Foundation

// MARK: - Billing

/// Where a user whose account has run out of credit goes to fix it.
///
/// **This is a placeholder for one constant, not for the error type.** The same
/// two URLs live on the `feat/ai-clients` branch in `Fuel/Core/AI/AIError.swift`,
/// where they belong: the no-credit state is a provider error, and the link is
/// part of it. That branch has not merged, and Settings needs the link now to
/// draw the note the owner ruled on, so the URLs are defined here and nothing
/// else from `AIError` is copied. **When the branches meet, this type is
/// deleted and its call site reads `AIError`'s constants** — two definitions of
/// the same URL are one silent divergence away from sending a user to a page
/// that has moved.
nonisolated enum ProviderBilling {

    /// The provider's own billing page, reached from the device like every
    /// other request Fuel makes. Nothing of the user's travels with it — it is
    /// a plain link to a console the user already has an account on.
    static func url(for provider: AIProvider) -> URL {
        switch provider {
        case .claude: anthropic
        case .mistral: mistral
        }
    }

    // Force-unwrapped: both are string literals that cannot fail to parse, and
    // `SettingsAITests` pins each of them, so a typo goes red in the suite
    // rather than at a user's tap.
    private static let anthropic = URL(string: "https://console.anthropic.com/settings/billing")!
    private static let mistral = URL(string: "https://console.mistral.ai/billing")!
}

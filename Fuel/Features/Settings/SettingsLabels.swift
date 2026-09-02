import SwiftUI

// MARK: - Provider

extension AIProvider {

    /// The segment label. `Claude` and `Mistral` are product names and are not
    /// translated, but they are catalog entries all the same: a visible string
    /// sitting as a literal in a view is a literal whether or not it would ever
    /// change.
    var settingsSegmentTitle: LocalizedStringKey {
        switch self {
        case .claude: "settings.provider.claude"
        case .mistral: "settings.provider.mistral"
        }
    }

    /// The placeholder in the key field.
    ///
    /// A design placeholder, not a validation rule: Anthropic keys really do
    /// begin `sk-ant-`, but Mistral publishes no prefix and `APIKeyFormat`
    /// checks that provider's keys for shape only.
    var settingsKeyPlaceholder: LocalizedStringKey {
        switch self {
        case .claude: "settings.apiKey.placeholder.claude"
        case .mistral: "settings.apiKey.placeholder.mistral"
        }
    }
}

// MARK: - Theme

extension FuelTheme {

    var settingsSegmentTitle: LocalizedStringKey {
        switch self {
        case .light: "settings.theme.light"
        case .dark: "settings.theme.dark"
        }
    }
}

// MARK: - Accent

extension FuelAccent {

    /// The name under the swatch.
    var settingsSwatchTitle: LocalizedStringKey {
        switch self {
        case .mono: "settings.accent.mono"
        case .blue: "settings.accent.blue"
        case .green: "settings.accent.green"
        case .sand: "settings.accent.sand"
        case .lilac: "settings.accent.lilac"
        }
    }
}

// MARK: - Test note

extension KeyTestNote {

    /// `nil` where the design draws no note at all.
    var titleKey: LocalizedStringKey? {
        switch self {
        case .none: nil
        case .passed: "settings.keyTest.passed"
        case .notAccepted: "settings.keyTest.notAccepted"
        }
    }
}

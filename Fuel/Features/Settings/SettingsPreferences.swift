import Foundation

// MARK: - Preferences

/// The three choices screen 16 stores: theme, accent, and which provider is
/// selected.
///
/// **`UserDefaults`, deliberately, and only for these three.** The rule that
/// keeps secrets out of `UserDefaults` is about the API key, and the key is not
/// here — it is in the Keychain, and this type never sees it. What is here is
/// presentation state: which of two appearances to draw, which of five accents
/// to tint with, and which segment of the provider control is selected. None of
/// it is user data and none of it is a secret.
///
/// It is not in SwiftData either, and that is the choice worth explaining. The
/// appearance has to be known before the first frame, which means before the
/// `ModelContainer` has been opened; a theme read out of the store would give
/// the app a flash of the wrong one at every launch. `GoalSettings` is also the
/// row whose *existence* means onboarding is done, so an appearance written
/// into it would create that row before the user has answered anything.
///
/// The suite is injectable so a test can use its own and leave the app's
/// defaults untouched.
///
/// **This type is the only place the three keys and their defaults are
/// written down.** Settings is not the only reader — the shell needs the theme
/// and the accent before it draws its first frame — so `Key` and `Default` are
/// visible, and anything that needs a preference constructs a
/// `SettingsPreferences` rather than reading a raw key out of `UserDefaults`.
/// A second copy of `"settings.appearance.theme"` somewhere else is drift no
/// compiler can catch: it keeps working until one of the two is renamed, and
/// then the app quietly opens on the wrong theme.
@Observable
final class SettingsPreferences {

    private let defaults: UserDefaults

    // MARK: - Storage keys

    /// Namespaced, because `UserDefaults` for an app target is one flat
    /// dictionary shared with every framework that writes into it.
    ///
    /// **These are on-device state, not identifiers.** Renaming one does not
    /// break a build; it silently drops the user's choice and opens the app on
    /// the default. Changing one is a migration.
    enum Key {
        static let theme = "settings.appearance.theme"
        static let accent = "settings.appearance.accent"
        static let provider = "settings.ai.provider"
    }

    // MARK: - Defaults

    /// What each preference is before the user has chosen.
    ///
    /// Named rather than written inline at the three `??`s below, so a reader
    /// who has to know what the app opens on — the shell, deciding a colour
    /// scheme before any of this has been read — finds one answer instead of
    /// three literals buried in an initialiser.
    enum Default {

        /// Dark, matching the palette's own default and the pairing the export
        /// treats as the default.
        static let theme: FuelTheme = .dark

        static let accent: FuelAccent = .mono

        /// Claude is the selected segment in every drawn frame.
        static let provider: AIProvider = .claude
    }

    // MARK: - Choices

    var theme: FuelTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }

    var accent: FuelAccent {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }

    var provider: AIProvider {
        didSet { defaults.set(Self.storedValue(for: provider), forKey: Key.provider) }
    }

    // MARK: - Creation

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: Key.theme)
            .flatMap(FuelTheme.init(rawValue:)) ?? Default.theme
        self.accent = defaults.string(forKey: Key.accent)
            .flatMap(FuelAccent.init(rawValue:)) ?? Default.accent
        self.provider = Self.provider(fromStored: defaults.string(forKey: Key.provider))
            ?? Default.provider
    }

    // MARK: - Provider mapping

    /// `AIProvider` carries no raw value on purpose, so that nothing can derive
    /// on-device state from a case name. Anything that needs a string for a
    /// provider owns that string itself — this is Settings' copy.
    ///
    /// **These two strings are on-device state, not labels.** Changing one
    /// resets the user's provider selection back to Claude on the next launch.
    /// That is a great deal less damaging than the same mistake in
    /// `KeychainStore`, where it would orphan a key, but it is still a
    /// migration rather than a rename.
    private static func storedValue(for provider: AIProvider) -> String {
        switch provider {
        case .claude: "claude"
        case .mistral: "mistral"
        }
    }

    private static func provider(fromStored stored: String?) -> AIProvider? {
        AIProvider.allCases.first { storedValue(for: $0) == stored }
    }
}

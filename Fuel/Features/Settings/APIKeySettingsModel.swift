import Foundation

// MARK: - Test note

/// The states of the note beside `Re-check`.
///
/// Two are drawn in `Screens2c.dc.html`: nothing at all, and `Connection works`.
/// `Key not accepted` is spec but not drawn — it is a `[P]` row in the notes'
/// copy table, and grepping the screens for it comes back empty — and the
/// colour it takes is the error colour, which is `[P]` for the same reason.
/// `noCredit` is a fourth, added on an owner ruling, and it is the one undrawn
/// state that could not stay empty: a user
/// who cannot pay for a scan and is shown nothing has no way to work out what
/// happened or what to do. It is built out of drawn parts rather than invented
/// — the same slot and the same error colour as `notAccepted`, and a second
/// action in the same style the `Re-check` beside it already uses.
///
/// Everything else with no drawn state stays `none`: no key stored yet, a check
/// in flight, a network call that concluded nothing, and a Keychain write that
/// failed. Copy for those would have to be invented, and an in-flight check
/// already shows itself by disabling the button.
nonisolated enum KeyTestNote: Equatable, Sendable {

    /// Nothing is drawn.
    case none

    /// `✓ Connection works`, in `muted`.
    case passed

    /// `Key not accepted`, in the error colour.
    case notAccepted

    /// `No credit with <provider>`, in the error colour, with a link to that
    /// provider's billing page.
    ///
    /// The provider is not carried here. The note always belongs to the
    /// selected provider — switching the segment clears it — so the row reads
    /// the provider it is already drawing rather than the note holding a second
    /// copy that could disagree with it.
    case noCredit

    /// Whether the row draws the billing link beside the note. True for exactly
    /// one state, and the view asks rather than matching the case itself.
    var showsBillingLink: Bool { self == .noCredit }
}

// MARK: - Model

/// Holds the API-key row and the key test for whichever provider is selected.
///
/// Everything about the key that could be read back is closed off:
///
/// - the stored key is never fetched into a visible `String`. It is read as an
///   `APIKey` only to be handed to the validator, and `APIKey` redacts every
///   textual representation Swift has;
/// - `draft` is the one place a plain secret exists, it exists only while the
///   user is typing, and it is emptied the moment the key is submitted;
/// - this type's own `description`, `debugDescription` and `customMirror` are
///   redacted too, so `"\(model)"`, `po model` and `dump(model)` cannot spell
///   the draft out. `@Observable` synthesises stored properties that reflection
///   would otherwise walk straight into.
///
/// Nothing here logs. Not the key, not a prefix, not its length, not behind
/// `#if DEBUG`.
@Observable
final class APIKeySettingsModel {

    // MARK: - State

    /// What the user is typing into the secure field. Never populated from the
    /// Keychain — a stored key is not read back into the interface, which is
    /// why the field draws a placeholder rather than the key.
    var draft: String = ""

    private(set) var note: KeyTestNote = .none

    /// True while a test call is in flight. The design draws no state for it,
    /// so it only disables `Re-check` against a second tap.
    private(set) var isChecking: Bool = false

    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let validator: any KeyValidating

    // MARK: - Creation

    init(keychain: KeychainStore = KeychainStore(), validator: any KeyValidating) {
        self.keychain = keychain
        self.validator = validator
    }

    // MARK: - Provider

    /// Called when the provider segment changes.
    ///
    /// It clears the note and the draft and nothing else. The other provider's
    /// key stays in the Keychain untouched — one item per provider is what lets
    /// a user hold both and switch without losing either — and the note is
    /// cleared because a result that belonged to the provider the user just
    /// left would be read as belonging to the one they arrived at.
    func providerChanged() {
        draft = ""
        note = .none
    }

    // MARK: - Submitting a typed key

    /// Takes what the user typed, empties the field, and tests it.
    ///
    /// The draft is cleared before anything can fail, so a secret does not sit
    /// in memory — or on screen behind a secure field's dots — waiting for a
    /// network call to come back.
    func submitDraft(for provider: AIProvider) async {
        let key = APIKey(draft)
        draft = ""
        await check(key, for: provider)
    }

    // MARK: - Re-checking the stored key

    /// The `Re-check` action: tests the key already in the Keychain.
    ///
    /// With no key stored there is nothing to test and no request is made. The
    /// note stays empty, because the design has no state that says "no key" —
    /// see `KeyTestNote`.
    func recheck(for provider: AIProvider) async {
        guard let key = try? keychain.readKey(for: provider) else {
            note = .none
            return
        }
        await check(key, for: provider)
    }

    // MARK: - The check

    /// Format first, then at most one test call.
    ///
    /// The offline check runs before every validation, on the re-check path as
    /// much as on the typed one, so an obvious typo never costs the user a
    /// request. A rejected format is reported as `notAccepted`: the reason
    /// differs, but what the user is being told — this key will not work — is
    /// the same, and it is the only failure note the design draws.
    private func check(_ key: APIKey, for provider: AIProvider) async {
        guard APIKeyFormat.check(key, for: provider) == .plausible else {
            note = .notAccepted
            return
        }

        isChecking = true
        note = .none
        let outcome = await validator.validate(key, for: provider)
        isChecking = false

        switch outcome {
        case .passed:
            note = store(key, for: provider) ? .passed : .none
        case .noCredit:
            // The key authenticated — the account simply has nothing left on
            // it — so it is worth keeping. The note says so and offers the way
            // out; `Connection works` would be a lie about a key that cannot
            // pay for a request.
            note = store(key, for: provider) ? .noCredit : .none
        case .invalidKey:
            // Deliberately not stored. Overwriting a key that works with one
            // the provider has just rejected would take a working app away
            // from the user for a typo.
            note = .notAccepted
        case .retry:
            // The call did not conclude anything, so neither does this: the
            // stored key is left alone and the note stays empty.
            note = .none
        }
    }

    /// Writes the key to the Keychain, reporting whether it landed.
    ///
    /// A failed write is not shown — there is no drawn state for it — but it
    /// does keep the passed note off the screen, because a note saying the
    /// connection stands next to a key the app did not manage to keep is the
    /// worst of the available lies.
    private func store(_ key: APIKey, for provider: AIProvider) -> Bool {
        do {
            try keychain.store(key, for: provider)
            return true
        } catch {
            // Swallowed on purpose: a `KeychainError` carries an `OSStatus`,
            // and there is nowhere to put one. Logging it is out — nothing
            // about the key, including the fact that one was being written,
            // goes into a log.
            return false
        }
    }
}

// MARK: - Redacted text representations

extension APIKeySettingsModel: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    private static let redacted = "APIKeySettingsModel(redacted)"

    var description: String { Self.redacted }

    var debugDescription: String { Self.redacted }

    /// No children, so `dump` and any reflection-driven serialiser cannot reach
    /// `draft`.
    var customMirror: Mirror {
        Mirror(self, children: [Mirror.Child](), displayStyle: .class)
    }
}

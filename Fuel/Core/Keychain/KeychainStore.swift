import Foundation
import Security

// MARK: - Store

/// Stores one API key per provider in the iOS Keychain.
///
/// Fuel is bring-your-own-key: the only credential in the app belongs to the
/// user, and Levo Studio never sees it. That makes this file the whole security
/// surface of the app, so it is written to be boring and to be read.
///
/// Three decisions are load-bearing, and each is defended at its line below:
///
/// 1. **Keychain, never `UserDefaults`.** `UserDefaults` is a property list in
///    the app container: plain text, readable from a file-system backup, and
///    included in an unencrypted iTunes backup. Nothing about it protects a
///    credential.
/// 2. **`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.** See `accessibility`.
/// 3. **iCloud Keychain sync is off, in every query.** See `synchronizable`.
///
/// The type talks to the Security framework directly. There is no wrapper
/// package, because Fuel has no dependencies and that is a feature — and a
/// credential store is the last place to take one on.
///
/// `nonisolated` because the Security framework is thread-safe and callers
/// should not have to hop to the main actor to read a key on the way into a
/// request.
nonisolated struct KeychainStore: Sendable {

    // MARK: - Configuration

    /// The Keychain service every provider key is filed under. Accounts within
    /// it are the providers.
    ///
    /// Injectable so tests can use a namespace of their own. A test that wrote
    /// to the production service would clobber the real key of whoever is
    /// running it, and its cleanup would delete it — the isolation is not
    /// tidiness, it is the difference between a green run and a user losing
    /// their key.
    let service: String

    static let defaultService = "apps.levo-studio.Fuel.provider-keys"

    init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    // MARK: - Security attributes

    /// The accessibility class every item is written with.
    ///
    /// `WhenUnlockedThisDeviceOnly` rather than the alternatives:
    ///
    /// - `…ThisDeviceOnly` is the point. Items in a `ThisDeviceOnly` class are
    ///   excluded from encrypted backups and never restored onto a different
    ///   device — the key cannot travel through Apple's cloud on its way to a
    ///   new phone. A key that leaves the device is exactly what local-first is
    ///   meant to avoid, and Fuel has nothing else that would need to be
    ///   restored: there is no account and no server to re-pair with. The cost
    ///   is that a user setting up a new phone pastes their key again, which is
    ///   the correct trade for a credential they can regenerate for free.
    /// - `WhenUnlocked` rather than `AfterFirstUnlock` because Fuel only ever
    ///   reads a key in response to something the user just did — a photo, a
    ///   typed meal, a key test. There is no background task, no push
    ///   extension, no widget that needs the key while the device is locked, so
    ///   the wider class would buy nothing and would leave the key reachable
    ///   from a locked device.
    ///
    /// Computed rather than stored: `CFString` is not `Sendable`, so a `static
    /// let` would be global mutable state as far as strict concurrency is
    /// concerned. The constant is immutable in practice; recomputing it costs
    /// nothing and keeps the checker honest.
    private static var accessibility: CFString {
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    /// iCloud Keychain sync, pinned to false on every query.
    ///
    /// A synced key would be copied to Apple's servers and pushed to every
    /// device on the account. Fuel has no cloud, no account and no sync by
    /// design; the user's credential must not be the one exception.
    ///
    /// `kSecAttrSynchronizable` is not merely an attribute: in a search it is
    /// also a filter, and pinned to false it means "non-synchronising items
    /// only" — so this store cannot create a synced item, and cannot read or
    /// update one that some other code left in the same slot.
    ///
    /// **Being explicit here does not change behaviour, and that is the point
    /// of writing it down.** Omitting the attribute gives the same result,
    /// because the Security framework already defaults to false for both adds
    /// and searches. But a guarantee this file exists to make should not rest
    /// on a reader remembering an unwritten default correctly, and a default is
    /// the kind of thing that is easy to misremember in the wrong direction —
    /// the first version of this comment did exactly that. Stated in the query,
    /// the intent is visible at the line where it takes effect and survives
    /// anyone rewriting the code around it.
    ///
    /// The guarantee that a key cannot reach iCloud is carried by two things
    /// together: nothing here ever sets the flag true, and the `ThisDeviceOnly`
    /// accessibility above is a combination the Keychain refuses to synchronise
    /// at all. `KeychainTests` asserts both on the stored item.
    ///
    /// Computed for the same strict-concurrency reason as `accessibility`.
    private static var synchronizable: Any {
        kCFBooleanFalse as Any
    }

    // MARK: - Reading

    /// The key stored for `provider`, or `nil` if there is none.
    ///
    /// "No key yet" is not an error — it is the state of every first launch and
    /// of Settings after a key is removed — so `errSecItemNotFound` comes back
    /// as `nil` rather than as a thrown error.
    func readKey(for provider: AIProvider) throws -> APIKey? {
        let query = itemQuery(for: provider, adding: [
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)

        switch status {
        case errSecSuccess:
            guard
                let data = item as? Data,
                let secret = String(data: data, encoding: .utf8)
            else {
                throw KeychainError.unreadableItem
            }
            return APIKey(secret)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Whether a key exists for `provider`.
    ///
    /// Asks the Keychain for the item's presence without requesting its data,
    /// so the common "should the camera button be enabled" question never pulls
    /// a secret into memory it has no use for.
    ///
    /// Non-throwing: every failure here — including a locked device — means the
    /// same thing to a caller, namely "do not assume there is a usable key".
    /// Anything that actually needs the key calls `readKey(for:)` and gets a
    /// real error.
    func hasKey(for provider: AIProvider) -> Bool {
        let query = itemQuery(for: provider, adding: [
            kSecReturnData as String: false,
            kSecMatchLimit as String: kSecMatchLimitOne
        ])

        return SecItemCopyMatching(query, nil) == errSecSuccess
    }

    // MARK: - Writing

    /// Stores `key` for `provider`, replacing any key already there.
    ///
    /// `SecItemAdd` fails with `errSecDuplicateItem` when an item with the same
    /// service and account exists, which is the ordinary case of a user
    /// correcting a key. That is handled as an update rather than surfaced as a
    /// failure — and never as a delete-then-add, which would leave the user
    /// with no key at all if the second half failed.
    func store(_ key: APIKey, for provider: AIProvider) throws {
        let secret = Data(key.secret.utf8)

        let addQuery = itemQuery(for: provider, adding: [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: Self.accessibility
        ])

        let addStatus = SecItemAdd(addQuery, nil)

        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            try update(secret, for: provider)
        default:
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    private func update(_ secret: Data, for provider: AIProvider) throws {
        // The accessibility class is rewritten alongside the data so an item
        // written by an older build under a weaker class is healed the next
        // time the user touches their key, rather than staying weak forever.
        // `KeychainTests` writes a weakened item and checks that this repairs
        // it, because a comment promising a repair nobody verifies is worse
        // than no comment.
        //
        // `kSecAttrSynchronizable` is deliberately not in the update payload:
        // the query below already restricts the match to non-synchronising
        // items, so there is nothing to change.
        let attributes: [String: Any] = [
            kSecValueData as String: secret,
            kSecAttrAccessible as String: Self.accessibility
        ]

        let status = SecItemUpdate(
            itemQuery(for: provider),
            attributes as CFDictionary
        )

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Deleting

    /// Removes the key for `provider`.
    ///
    /// A real delete of the Keychain item — never an empty string written over
    /// the old value, which would leave an item behind that `hasKey(for:)`
    /// would keep answering `true` for, and would leave the user unable to tell
    /// a removed key from a broken one.
    ///
    /// Idempotent: deleting a key that is not there succeeds. "It is gone" is
    /// the caller's desired end state, and it holds either way.
    func deleteKey(for provider: AIProvider) throws {
        let status = SecItemDelete(itemQuery(for: provider))

        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Query

    /// The single place in this type where a Keychain query is built.
    ///
    /// Every `SecItem*` call above passes through here and adds only the flags
    /// specific to what it is doing. That is deliberate: with four call sites
    /// each assembling their own dictionary, "every query pins
    /// `kSecAttrSynchronizable` to false" was a convention that a fifth method
    /// could quietly break. Funnelled through one function it is structure: a
    /// caller adds the flags specific to its own operation and can neither omit
    /// the sync flag and the item's identity nor overwrite them, because the
    /// pinned values win every collision. `KeychainTests` hands this function a
    /// dictionary that tries all four and checks that none of them takes.
    ///
    /// Returns a `CFDictionary` rather than a Swift dictionary so a caller
    /// cannot take the result and mutate an attribute back out of it.
    ///
    /// Not `private`: the guarantee above is about what this function does with
    /// a hostile `extra`, and `KeychainTests` proves it by handing it one. The
    /// seam is safe to widen because the function performs no Security call —
    /// it builds a dictionary, and the dictionary it builds is always pinned.
    func itemQuery(
        for provider: AIProvider,
        adding extra: [String: Any] = [:]
    ) -> CFDictionary {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecAttrSynchronizable as String: Self.synchronizable
        ]
        // The pinned value wins every collision. `merge` hands the closure
        // `(existing, new)`, and returning `new` — the obvious-looking way to
        // write this, and the way it was written first — would let a caller
        // overwrite the class, the service, the account or the sync flag by
        // passing them in `extra`. That is the exact convention this funnel was
        // built to make impossible. No call site needs to override those four,
        // so keeping them is free.
        query.merge(extra) { existing, _ in existing }
        return query as CFDictionary
    }

    /// The Keychain account name a provider's key is filed under.
    ///
    /// One account per provider, under a single service, is what lets a user
    /// hold a Claude key and a Mistral key at the same time and switch between
    /// them without losing the one they are not currently using.
    ///
    /// **These strings are on-device state, not labels.** They are written out
    /// here rather than derived from the enum so that renaming a case — a
    /// harmless-looking edit in a domain type that has nothing to do with
    /// storage — cannot orphan a key already on a user's device. An orphaned
    /// item stays in the Keychain, unreachable, and the user is asked for a key
    /// they already gave. Changing a string here is a migration.
    ///
    /// `AIProvider` carries no raw value for the same reason: there must be
    /// nothing convenient to derive these from.
    private func account(for provider: AIProvider) -> String {
        switch provider {
        case .claude: "claude"
        case .mistral: "mistral"
        }
    }
}

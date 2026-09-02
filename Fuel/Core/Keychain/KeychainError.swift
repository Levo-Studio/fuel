import Foundation
import Security

// MARK: - Error

/// The ways a Keychain operation can fail.
///
/// Note what is *not* in here: `notFound`. "There is no key for this provider"
/// is a normal state — it is what every first launch looks like, and what
/// Settings looks like after a key is removed — so it is answered with `nil`
/// from `readKey(for:)` rather than by throwing. Reserving `throws` for genuine
/// failures keeps call sites from wrapping an expected outcome in a `do`/`catch`
/// and treating it as a problem.
///
/// No case carries a key, a fragment of a key, or anything derived from one. An
/// error is the single most likely value to end up in a log line or a crash
/// report, which makes it the single most likely place for a key to leak.
nonisolated enum KeychainError: Error, Equatable {

    /// The Security framework returned a status we have no specific handling
    /// for. The raw `OSStatus` is carried so a bug report can name the code;
    /// it says nothing about the key's content.
    case unexpectedStatus(OSStatus)

    /// The Keychain returned an item whose data is not valid UTF-8, which means
    /// something other than this wrapper wrote to the same service and account.
    /// Treated as a failure rather than repaired, because guessing at the
    /// encoding of a credential is worse than reporting that it is unusable.
    case unreadableItem
}

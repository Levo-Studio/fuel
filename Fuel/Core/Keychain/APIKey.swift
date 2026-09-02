import Foundation

// MARK: - API key

/// A provider API key.
///
/// The type exists so a key is not just another `String` travelling through the
/// app, where any interpolation into a message, an error, or a crash report
/// would spell it out. Every way Swift has of turning a value into text is
/// closed here:
///
/// - `description` — used by `"\(key)"` and `String(describing:)`
/// - `debugDescription` — used by `debugPrint` and the debugger's `po`
/// - `customMirror` — used by `dump`, and by reflection-based loggers and
///   crash reporters that walk a value's children
///
/// All three answer with a fixed placeholder. Reading the secret out requires
/// naming `secret` explicitly, which is a deliberate act and greppable in
/// review. `KeychainTests` asserts that interpolation cannot leak it, because
/// this guarantee is easy to break by accident — a synthesised `Codable`
/// conformance or a stray `Equatable`-by-reflection would do it.
///
/// Deliberately not `Codable`: a key must never be encoded into anything that
/// could be written to disk, sent over a wire, or dropped into a log. The
/// Keychain is the only place it is persisted.
nonisolated struct APIKey: Sendable, Equatable, Hashable {

    /// The key itself. Read this only where the key is actually needed: writing
    /// it to the Keychain, checking its format, or putting it into a request
    /// header. Never into a string that goes anywhere else.
    let secret: String

    // MARK: - Creation

    /// Wraps a raw key string, trimming surrounding whitespace and newlines.
    ///
    /// Trimming happens here rather than at the call site because the realistic
    /// input path is a paste from a browser or a password manager, and those
    /// routinely carry a trailing newline. A user should not be told their key
    /// is malformed because of an invisible character they did not type.
    ///
    /// Only the outer edges are trimmed. Whitespace *inside* the string is left
    /// alone and rejected by `APIKeyFormat`, because that is a real typo — half
    /// a key, or two things pasted together — and silently repairing it would
    /// hide the mistake instead of reporting it.
    init(_ raw: String) {
        secret = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Redacted text representations

extension APIKey: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {

    /// The placeholder every textual representation of a key resolves to.
    private static let redacted = "APIKey(redacted)"

    var description: String {
        Self.redacted
    }

    var debugDescription: String {
        Self.redacted
    }

    /// An empty mirror, so `dump` and any reflection-driven serialiser see a
    /// value with no children rather than a `secret` field they can read.
    var customMirror: Mirror {
        Mirror(self, children: [Mirror.Child](), displayStyle: .struct)
    }
}

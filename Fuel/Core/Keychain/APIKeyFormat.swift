import Foundation

// MARK: - Verdict

/// The outcome of the offline format check.
///
/// Not a `Bool`. The interface has to tell the user *why* a key was rejected —
/// the design's failed-key note is a sentence, not a red border — and a boolean
/// throws that reason away at the exact moment it is needed. The view layer
/// maps a `Problem` onto its string catalog key; this type carries no user-
/// facing text of its own, because the strings live in `Localizable.xcstrings`.
nonisolated enum APIKeyFormatVerdict: Equatable, Sendable {

    /// Nothing obviously wrong. This is emphatically not "the key is valid" —
    /// only the live test call can say that. It means the key is worth spending
    /// a request on.
    case plausible

    /// The key cannot be valid, and no request needs to be made to know it.
    case rejected(Problem)

    // MARK: - Problem

    /// Why a key was rejected. Each case is something visible in the string
    /// itself; none of them require the network.
    enum Problem: Equatable, Sendable {

        /// Empty, or nothing but whitespace.
        case empty

        /// Whitespace inside the key. `APIKey` already trims the edges, so any
        /// whitespace still present is interior — a partial paste, or two
        /// values run together.
        case containsWhitespace

        /// Shorter than any real key of this provider.
        case tooShort

        /// Longer than any real key of this provider. Almost always a whole
        /// page pasted instead of one line.
        case tooLong

        /// Anthropic only: the key does not begin `sk-ant-`.
        case missingAnthropicPrefix
    }
}

// MARK: - Format check

/// The cheap, offline check a key gets before Fuel spends an API request on it.
///
/// It runs first so an obvious typo — an empty field, half a paste, a Mistral
/// key pasted under Claude — is reported instantly and for free. It is a filter,
/// not an oracle: a `plausible` verdict only earns the key a single
/// smallest-possible test call, which is what actually decides.
///
/// Deliberately knows nothing about the network. The test call lives in
/// `Core/AI/`; this file must stay runnable in a unit test with no simulator,
/// no server, and no user's real key.
nonisolated enum APIKeyFormat {

    // MARK: - Entry point

    static func check(_ key: APIKey, for provider: AIProvider) -> APIKeyFormatVerdict {
        let secret = key.secret

        if secret.isEmpty {
            return .rejected(.empty)
        }

        // `APIKey` trimmed the outer edges already, so anything found here is
        // inside the key and is a real mistake rather than a stray newline from
        // the pasteboard.
        if secret.contains(where: \.isWhitespace) {
            return .rejected(.containsWhitespace)
        }

        switch provider {
        case .claude:
            return checkAnthropic(secret)
        case .mistral:
            return checkMistral(secret)
        }
    }

    // MARK: - Anthropic

    /// Anthropic publishes the prefix and every key carries it, so checking it
    /// is free accuracy: it catches the common case of a key pasted under the
    /// wrong provider before it costs a request.
    private static let anthropicPrefix = "sk-ant-"

    /// Bounds, not exact lengths. Anthropic does not promise a key length and
    /// has changed it before, so the lower bound is chosen wide enough that a
    /// real key cannot fall under it, and narrow enough to catch a truncated
    /// paste.
    ///
    /// The 512 ceiling models no key length at all — neither provider publishes
    /// one, and Fuel must not reject a key because it is longer than the ones
    /// that existed when this line was written. It is there for one case: a
    /// whole page pasted into the field instead of a single line, which is
    /// worth naming as its own mistake rather than sending to the API. Both
    /// providers share the value for that reason.
    private static let anthropicLengthRange = 20...512

    private static func checkAnthropic(_ secret: String) -> APIKeyFormatVerdict {
        guard secret.hasPrefix(anthropicPrefix) else {
            return .rejected(.missingAnthropicPrefix)
        }
        return checkLength(secret, within: anthropicLengthRange)
    }

    // MARK: - Mistral

    /// Mistral keys are checked for **shape only, and never for a prefix.**
    ///
    /// This is deliberate and it is the thing most likely to be "fixed" by
    /// someone reading the design export. The `mist-…` in the key field on
    /// screen 01 is placeholder text — it tells the user which field they are
    /// in — and `Fuel Design Notes.md` says so explicitly. Mistral publishes no
    /// key prefix, so a `hasPrefix("mist-")` check here would reject perfectly
    /// valid keys and leave the user with an error they cannot act on, for a
    /// rule Fuel invented.
    ///
    /// So: non-empty, no whitespace, plausible length — and the live test call
    /// is the verdict. Do not add a prefix check without a link to Mistral's own
    /// documentation stating the prefix.
    ///
    /// The lower bound is looser than Anthropic's for the same reason: with no
    /// published format, the only defensible floor is "too short to be a
    /// credential at all". The ceiling is the shared pasted-page guard
    /// described on `anthropicLengthRange`, not a claim about key length.
    private static let mistralLengthRange = 16...512

    private static func checkMistral(_ secret: String) -> APIKeyFormatVerdict {
        checkLength(secret, within: mistralLengthRange)
    }

    // MARK: - Shared

    private static func checkLength(
        _ secret: String,
        within range: ClosedRange<Int>
    ) -> APIKeyFormatVerdict {
        let length = secret.count
        if length < range.lowerBound {
            return .rejected(.tooShort)
        }
        if length > range.upperBound {
            return .rejected(.tooLong)
        }
        return .plausible
    }
}

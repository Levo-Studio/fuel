import Foundation

// MARK: - Entry source

/// Where an entry came from. The day list prints it beside the time
/// (`08:14 · Photo`), and it is the only provenance Fuel keeps.
///
/// There are three log modes and there is no fourth: camera, text, recent.
nonisolated enum EntrySource: String, CaseIterable, Codable, Hashable, Sendable {

    case photo
    case text
    case recent
}

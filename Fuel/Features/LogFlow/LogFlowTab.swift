import Foundation

// MARK: - Log tab

/// The three log modes, in the order the tab bar draws them.
///
/// Three, and there is no fourth. A manual food search was explored and cut, so
/// the bar is a fixed three-column grid rather than a list that happens to hold
/// three things today: `design/Fuel Design Notes.md` says the log flow has
/// camera, text and recent, and the export draws
/// `grid-template-columns:repeat(3,1fr)`. A fourth case here is a design
/// change, not an addition.
nonisolated enum LogFlowTab: String, CaseIterable, Identifiable, Hashable, Sendable {

    case camera
    case text
    case recent

    var id: String { rawValue }
}

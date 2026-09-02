import Foundation

// MARK: - Targets

/// A day's targets in goal mode: the calorie goal and the three macro goals.
nonisolated struct DailyTargets: Hashable, Sendable {

    var kilocalories: Int
    var protein: Int
    var carbs: Int
    var fat: Int

    /// The values onboarding starts from, straight out of the design notes.
    static let `default` = DailyTargets(kilocalories: 2400, protein: 160, carbs: 240, fat: 70)
}

// MARK: - Counting mode

/// Whether the user counts against a goal or only counts.
///
/// The two modes are one enum rather than a flag next to an optional target,
/// so that reading a target without first establishing that there is a goal is
/// not expressible. Count-only is not goal mode with the ring switched off —
/// the design draws a different Today screen for it, with no ring and no macro
/// bars — and the type says so.
nonisolated enum CountingMode: Hashable, Sendable {

    case goal(DailyTargets)
    case countOnly

    var targets: DailyTargets? {
        switch self {
        case .goal(let targets): targets
        case .countOnly: nil
        }
    }

    /// The ring exists only in goal mode.
    var showsRing: Bool {
        targets != nil
    }
}

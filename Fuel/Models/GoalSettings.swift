import Foundation
import SwiftData

// MARK: - Goal settings

/// The single row that holds how the user counts.
///
/// One row exists once onboarding has been answered, and its existence is what
/// says onboarding is done — a separate "has onboarded" flag would be a second
/// source of truth for the same fact.
@Model
final class GoalSettings {

    /// Goal mode or count-only. The targets below stay filled in either way.
    var countsAgainstGoal: Bool

    /// Kept even in count-only mode, so switching back in Settings returns the
    /// user's own numbers rather than the defaults.
    var kilocalorieGoal: Int
    var proteinGoal: Int
    var carbGoal: Int
    var fatGoal: Int

    init(mode: CountingMode = .goal(.default)) {
        let targets = mode.targets ?? .default
        self.countsAgainstGoal = mode.targets != nil
        self.kilocalorieGoal = targets.kilocalories
        self.proteinGoal = targets.protein
        self.carbGoal = targets.carbs
        self.fatGoal = targets.fat
    }

    // MARK: - Typed accessor

    var mode: CountingMode {
        get {
            guard countsAgainstGoal else { return .countOnly }
            return .goal(targets)
        }
        set {
            countsAgainstGoal = newValue.targets != nil
            if let targets = newValue.targets {
                self.targets = targets
            }
        }
    }

    var targets: DailyTargets {
        get {
            DailyTargets(
                kilocalories: kilocalorieGoal,
                protein: proteinGoal,
                carbs: carbGoal,
                fat: fatGoal
            )
        }
        set {
            kilocalorieGoal = newValue.kilocalories
            proteinGoal = newValue.protein
            carbGoal = newValue.carbs
            fatGoal = newValue.fat
        }
    }
}

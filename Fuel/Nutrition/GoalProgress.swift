import Foundation

// MARK: - Goal progress

/// How far a day has come against its targets.
///
/// Goal mode only. In count-only mode there is no goal, no ring and no macro
/// bars, so there is nothing here to build — which is why this is a separate
/// type rather than a set of optional properties on the totals.
nonisolated struct GoalProgress: Hashable, Sendable {

    let totals: DailyTotals
    let targets: DailyTargets

    init(totals: DailyTotals, targets: DailyTargets) {
        self.totals = totals
        self.targets = targets
    }

    /// The fraction the ring is drawn at: `min(1, total ÷ goal)`. The ring
    /// never wraps past full, so a day over the goal reads as a closed ring.
    var ringFraction: Double {
        Self.fraction(totals.kilocalories, of: targets.kilocalories)
    }

    /// The figure inside the ring, as a whole number.
    ///
    /// Truncated, not rounded: at 99.6% of the goal the ring is visibly still
    /// open, and a label reading `100%` beside it would contradict the drawing.
    ///
    /// Worked out in integers rather than by truncating `ringFraction × 100`.
    /// A share that is exactly a whole percent is not exact in binary floating
    /// point — 696 ÷ 2400 × 100 comes out as 28.999999999999996 — so
    /// truncating the Double drops a percent from a figure that is not short
    /// of it at all.
    var percentage: Int {
        guard targets.kilocalories > 0 else { return 0 }
        return min(100, totals.kilocalories * 100 / targets.kilocalories)
    }

    /// The macro bars, each capped at full like the ring.
    var proteinFraction: Double { Self.fraction(totals.macros.protein, of: targets.protein) }
    var carbFraction: Double { Self.fraction(totals.macros.carbs, of: targets.carbs) }
    var fatFraction: Double { Self.fraction(totals.macros.fat, of: targets.fat) }

    /// A target of zero or less has no meaningful fraction; it reads as empty
    /// rather than dividing by nothing.
    static func fraction(_ used: Int, of target: Int) -> Double {
        guard target > 0 else { return 0 }
        return min(1, Double(used) / Double(target))
    }
}

// MARK: - Building it from the mode

nonisolated extension CountingMode {

    /// Progress in goal mode, `nil` in count-only mode.
    func progress(for totals: DailyTotals) -> GoalProgress? {
        guard let targets else { return nil }
        return GoalProgress(totals: totals, targets: targets)
    }
}

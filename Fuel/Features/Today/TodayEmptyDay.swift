import Foundation

// MARK: - The row a day with nothing on it carries

/// What Today draws in the day list's place on a day that is still running and
/// has nothing logged to it yet: a meal heading, and one row under it that
/// offers to log something.
///
/// **The export draws no empty state**, on either Today screen. The row is the
/// owner's instruction, and every value in it is recomposed from what the
/// screens do draw — `TodayEmptyDayView` names the source of each at the line
/// that uses it.
///
/// A plain value with no store and no view in it, so the rule that could
/// actually be wrong here — which meal the heading names — is pinned without a
/// `ModelContainer` and without a simulator. It is not in `Fuel/Nutrition/`
/// for the reason `TodayGettingStarted` is not: none of *this* is nutrition,
/// and the rule it leans on already lives there.
///
/// **It is not an entry, and it cannot become one by accident.** The type
/// carries a label and nothing else — no calories, no macros, no identity, no
/// timestamp. `TodayPresentation` never sees it, so nothing it could contribute
/// exists to reach a total, the ring, the macro figures, the accuracy figure or
/// the day list.
nonisolated struct TodayEmptyDay: Hashable, Sendable {

    /// The meal the heading over the row names.
    ///
    /// **The label a meal logged at this moment would actually be filed under**,
    /// derived by `MealLabeler` rather than read off the clock a second time.
    /// The owner named three labels; the rule gives a fourth in the small
    /// hours, and a heading promising `Dinner` over an entry the store then
    /// files as `Snack` would be the kind of lie this app refuses everywhere
    /// else. So the heading says whatever the rule says, `Snack` included.
    ///
    /// On an empty day — the only day this exists on — the rule works out at:
    ///
    /// | Logged at | Heading |
    /// |---|---|
    /// | `00:00 – 03:59` | Snack |
    /// | `04:00 – 10:59` | Breakfast |
    /// | `11:00 – 17:59` | Lunch |
    /// | `18:00 – 23:59` | Dinner |
    ///
    /// The afternoon is `Lunch` and not `Snack`, which is worth stating because
    /// it reaches past the hours Settings prints. Screen 17 draws three rows,
    /// one per main meal, and lunch's stops at `14:59`; lunch's *reach* runs on
    /// through the gap after it on a day that never got one, and an empty day
    /// never did. Those rows are the plain-language summary the user reads
    /// rather than the rule — `AutomaticLabelsSection` names all three places
    /// the two part company. The rule itself is
    /// `MainMeal.claimable(atMinuteOfDay:)`.
    let label: MealLabel

    // MARK: - Whether it is offered

    /// `nil` when Today does not offer the row, and the label it heads when it
    /// does.
    ///
    /// Three things have to hold, and each excludes a state that already has an
    /// answer of its own:
    ///
    /// - **The day being shown is today.** A past day nobody logged to gets
    ///   `TodayEmptyPastDay`'s line instead, and the reason is not taste. The
    ///   label is derived from the clock, so it describes now rather than that
    ///   day; and a meal is logged *now* whatever day Today is showing — see
    ///   `RootShellModel.dismissDestinationAfterLogging`, which closes the flow
    ///   onto the current day because the log flow draws no control for
    ///   choosing a date. A row offered on a Tuesday in March would promise a
    ///   meal on Tuesday, write one today, and take the screen with it.
    /// - **The day has nothing on it.** The day list wins the moment there is
    ///   one entry, which is what the owner asked for; it is also what makes
    ///   the claimed-labels set below the day's real state rather than a
    ///   convenient assumption.
    /// - **The get-started checklist is not being offered.** Both stand in the
    ///   day list's place and a brand-new user's first day satisfies both, so
    ///   one of them has to give way. The checklist stays: `Log your first
    ///   meal` is already one of its three rows and already opens this same
    ///   flow, so drawing the placeholder beside it would be two controls, two
    ///   rows apart, saying one thing. They hand over at a single moment
    ///   without ever overlapping — the first logged meal retires the checklist
    ///   for good, and that is the same event that ends the placeholder for
    ///   that day.
    init?(
        isToday: Bool,
        hasEntries: Bool,
        isGettingStartedOffered: Bool,
        now: Date,
        calendar: Calendar
    ) {
        guard isToday, !hasEntries, !isGettingStartedOffered else { return nil }
        // Empty, and not as a shortcut: the guard directly above establishes
        // that the day carries no entry, so no meal has been handed out on it
        // and the empty set is what the day actually holds. An entry arriving
        // is what takes this row off the screen, not something it has to reason
        // around.
        label = MealLabeler(calendar: calendar)
            .label(forEntryAt: now, claimedLabels: [])
    }
}

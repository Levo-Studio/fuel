import Foundation

// MARK: - Meal labeler

/// Derives the label of an entry from the course of the day, not from the
/// clock alone.
///
/// Breakfast, lunch and dinner are each handed out **once per day**, to the
/// first entry that can claim them. Everything else is a snack. Two
/// consequences are the whole reason the rule exists:
///
/// - A second entry inside the breakfast window is a snack, not a second
///   breakfast — breakfast was already handed out.
/// - An entry at `16:00` on a day with no lunch yet *is* lunch, because the
///   lunch window passed unused and dinner has not been reached. A fixed
///   `15:00 – 17:59` snack band would get this wrong.
///
/// The clock rows in Settings and the prototype's `labelFor(hour)` both look
/// like this rule and are not it: the first is the plain-language summary the
/// user reads, the second is demo scaffolding for a prototype that has no day
/// history to reason about.
///
/// The labeler never asks what time it is. Every entry point takes the moment
/// it should reason about, so the rule is testable without a clock.
nonisolated struct MealLabeler {

    /// The calendar decides which day an entry belongs to and what its local
    /// time of day is. It is injected so a test can pin a time zone.
    var calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - Deriving

    /// The label an entry logged at `date` should get, given what the same day
    /// has already been handed.
    ///
    /// Only entries of the same calendar day that were logged before `date`
    /// can have claimed a meal — a later entry cannot have taken breakfast off
    /// an earlier one.
    func label(forEntryAt date: Date, existing entries: [NutritionEntry]) -> MealLabel {
        let claimed = entries
            .filter { $0.loggedAt < date && calendar.isDate($0.loggedAt, inSameDayAs: date) }
            .map(\.label)
        return label(forEntryAt: date, claimedLabels: Set(claimed))
    }

    /// The same rule against an explicit set of labels the day has already
    /// handed out. This is the whole rule; everything else feeds it.
    func label(forEntryAt date: Date, claimedLabels claimed: Set<MealLabel>) -> MealLabel {
        guard let meal = MainMeal.claimable(atMinuteOfDay: minuteOfDay(of: date)) else {
            return .snack
        }
        // The meal is only still available if nothing today carries it yet. A
        // label the user set by hand counts as claimed just like a derived one:
        // it is on the day's list under that name.
        return claimed.contains(meal.label) ? .snack : meal.label
    }

    // MARK: - Re-deriving a whole day

    /// Re-derives the labels of one day's entries, in chronological order.
    ///
    /// Entries whose label the user set by hand keep it and hold their meal
    /// against later entries. Re-deriving must never undo a correction, which
    /// is what makes this safe to run after a day changes.
    func relabelling(_ entries: [NutritionEntry]) -> [NutritionEntry] {
        var claimed: Set<MealLabel> = []
        return entries.sorted { $0.loggedAt < $1.loggedAt }.map { entry in
            guard !entry.isLabelUserSet else {
                claimed.insert(entry.label)
                return entry
            }
            let derived = label(forEntryAt: entry.loggedAt, claimedLabels: claimed)
            claimed.insert(derived)
            return entry.withLabel(derived, userSet: false)
        }
    }

    // MARK: - Time of day

    private func minuteOfDay(of date: Date) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}

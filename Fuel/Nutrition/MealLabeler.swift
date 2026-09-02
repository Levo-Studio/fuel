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
/// How far a meal reaches, and what the two ends of the day do, is settled in
/// `MainMeal.claimable(atMinuteOfDay:)`.
///
/// The clock rows in Settings and the prototype's `labelFor(hour)` both look
/// like this rule and are not it: the first is the plain-language summary the
/// user reads, the second is demo scaffolding for a prototype that has no day
/// history to reason about.
///
/// The labeler never asks what time it is. Every entry point takes the moment
/// it should reason about, so the rule is testable without a clock.
nonisolated struct MealLabeler {

    /// The calendar decides what an entry's local time of day is. It has no
    /// default: the whole rule is about time of day, and a default would let a
    /// caller — a future test above all — read the ambient one by omission.
    var calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    // MARK: - Deriving

    /// The label an entry logged at `date` should get, given the labels the day
    /// has already handed out. This is the whole rule; everything else feeds it.
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

    /// Re-derives the labels of **one calendar day's** entries, in
    /// chronological order.
    ///
    /// This is the only way a label is assigned. Deriving from "the day so far"
    /// at the moment of logging would be enough for entries that arrive in
    /// order, and wrong for one that does not: a back-dated entry would take a
    /// meal a later entry already holds, and both would carry it.
    ///
    /// Entries whose label the user set by hand keep it. Re-deriving must
    /// never undo a correction, which is what makes this safe to run after a
    /// day changes.
    ///
    /// Their meals are reserved **before** anything is derived rather than as
    /// the pass reaches them: a meal is handed out once a day, and a correction
    /// the user made on a later entry has to hold it against an earlier one
    /// too. Reserving in order would let a back-dated entry derive the same
    /// dinner the hand-set entry after it already carries, and the day would
    /// show two.
    func relabelling(_ entries: [NutritionEntry]) -> [NutritionEntry] {
        var claimed = Set(entries.lazy.filter(\.isLabelUserSet).map(\.label))
        return entries.sorted { $0.loggedAt < $1.loggedAt }.map { entry in
            guard !entry.isLabelUserSet else { return entry }
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

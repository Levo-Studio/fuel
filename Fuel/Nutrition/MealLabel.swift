import Foundation

// MARK: - Meal label

/// The four labels an entry can carry.
///
/// `Snack` is deliberately not a time window. It is what an entry gets when no
/// main meal is still available to it — see `MealLabeler` for the rule.
nonisolated enum MealLabel: String, CaseIterable, Codable, Hashable, Sendable {

    case breakfast
    case lunch
    case snack
    case dinner

    /// The order the day list renders in, and the order the result screen's
    /// label control cycles through before it wraps.
    ///
    /// It is written out rather than taken from `allCases`, because both of
    /// those are a promise to the design and neither should silently change
    /// when somebody reorders the cases above.
    static let dayOrder: [MealLabel] = [.breakfast, .lunch, .snack, .dinner]

    /// The next label in the cycle, wrapping at the end.
    var next: MealLabel {
        let order = MealLabel.dayOrder
        guard let index = order.firstIndex(of: self) else { return order[0] }
        return order[(index + 1) % order.count]
    }
}

// MARK: - Main meals

/// The three meals that own a window in the day. Snack is not one of them.
nonisolated enum MainMeal: CaseIterable, Hashable, Sendable {

    case breakfast
    case lunch
    case dinner

    var label: MealLabel {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        }
    }

    /// The meal's window, as an inclusive range of minutes since midnight.
    ///
    /// Breakfast `04:00 – 10:59`, lunch `11:00 – 14:59`, dinner `18:00 – 22:59`.
    /// The upper bounds are the last minute *inside* the window, which is how
    /// the design writes them down.
    var window: ClosedRange<Int> {
        switch self {
        case .breakfast: MainMeal.minutes(4, 0) ... MainMeal.minutes(10, 59)
        case .lunch: MainMeal.minutes(11, 0) ... MainMeal.minutes(14, 59)
        case .dinner: MainMeal.minutes(18, 0) ... MainMeal.minutes(22, 59)
        }
    }

    /// The meals in the order the day runs through them.
    static let inDayOrder: [MainMeal] = [.breakfast, .lunch, .dinner]

    /// The meal a given moment can still claim, or `nil` when none can.
    ///
    /// This is not "which window is this minute inside". A meal's reach extends
    /// past the end of its own window up to the moment the next meal's window
    /// opens, which is why `16:00` claims *lunch*: the lunch window has passed
    /// and dinner has not been reached. Reading the windows literally would
    /// leave the 15:00–17:59 gap unclaimed and produce a fixed snack band —
    /// exactly the naive mapping the design rejects.
    ///
    /// Two ends of the day the windows alone do not settle, ruled by the owner:
    ///
    /// - **Dinner's reach runs to the end of the calendar day.** An entry at
    ///   23:30 on a day with no dinner is dinner, by the same reasoning as the
    ///   16:00 case: the window passed unused and no later main meal exists to
    ///   reach. Cutting the reach at 22:59 would leave a day whose only meal
    ///   was late showing a Snack group and no Dinner group at all.
    /// - **The small hours are always a snack.** Reach does not cross midnight,
    ///   so 00:00–03:59 claims nothing however the day went. Handing dinner to
    ///   an entry on a day that has barely begun would be absurd, and entries
    ///   are filed by calendar day, so a reach across midnight would attach
    ///   dinner to the wrong day.
    ///
    /// That leaves lunch (11:00 → 17:59) and dinner (18:00 → 23:59) symmetric
    /// within the day, with the small hours as the deliberate exception.
    static func claimable(atMinuteOfDay minute: Int) -> MainMeal? {
        guard let first = inDayOrder.first, minute >= first.window.lowerBound else { return nil }
        return inDayOrder.last { minute >= $0.window.lowerBound }
    }

    private static func minutes(_ hour: Int, _ minute: Int) -> Int {
        hour * 60 + minute
    }
}

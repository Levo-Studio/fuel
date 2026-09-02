import Foundation
import Testing

@testable import Fuel

// MARK: - Fixtures

/// A calendar pinned to UTC.
///
/// The rule is about local time of day, so a test that ran in a shifting zone
/// would pass or fail depending on where the machine stands. Pinning it makes
/// every time below mean exactly what it says.
nonisolated let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()

/// A moment on a chosen day, built by plain arithmetic because the calendar is
/// UTC and therefore has no gaps or repeats to reason about.
nonisolated func at(_ hour: Int, _ minute: Int = 0, day: Int = 0) -> Date {
    Date(timeIntervalSince1970: TimeInterval(day * 86_400 + hour * 3_600 + minute * 60))
}

nonisolated func entry(
    at date: Date,
    kilocalories: Int = 0,
    macros: MacroTotals = .zero,
    label: MealLabel = .snack,
    userSet: Bool = false,
    title: String = "Meal",
    source: EntrySource = .text
) -> NutritionEntry {
    NutritionEntry(
        title: title,
        kilocalories: kilocalories,
        macros: macros,
        loggedAt: date,
        source: source,
        label: label,
        isLabelUserSet: userSet
    )
}

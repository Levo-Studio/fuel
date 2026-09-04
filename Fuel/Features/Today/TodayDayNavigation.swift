import Foundation

// MARK: - Day title

/// What the big word on Today says about the day underneath it.
///
/// **Screens 05 and 06 draw the word `Heute`** — one state, because the export
/// draws one day. Browsing back is the owner's instruction and it leaves that
/// word standing over a day that is not today, which it cannot say. So the
/// title becomes a name for whichever day is shown, in the same drawn type at
/// the same drawn position.
///
/// A *name*, not a date. The eyebrow directly above already carries the
/// coordinate — `Tue, September 2` — and repeating it in 25pt would say the same
/// thing twice in two sizes. `Today` and `Yesterday` are the two days English
/// has words for; every other day is named by its weekday, which is the nearest
/// thing to a name a day has. The pair reads `Tuesday` over `Tue, September 2`:
/// the title says which day, the eyebrow says which Tuesday.
nonisolated enum TodayDayTitle: Hashable, Sendable {

    case today
    case yesterday

    /// Anything older, named by its weekday.
    case weekday(Date)

    init(day: Date, now: Date, calendar: Calendar) {
        let day = calendar.startOfDay(for: day)
        let today = calendar.startOfDay(for: now)

        if day == today {
            self = .today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), day == yesterday {
            self = .yesterday
        } else {
            self = .weekday(day)
        }
    }
}

// MARK: - Day navigation

/// Which day Today is showing, and which days it can move to.
///
/// **Nothing on screens 05 and 06 draws this.** The export draws one day and no
/// way to leave it; browsing is the owner's instruction, and this type is where
/// the rules of that browse live so that the three ways into it — a swipe, an
/// arrow, a date jump — cannot each answer them differently.
///
/// Pure and free of SwiftUI and of SwiftData, like `TodayPresentation` beside
/// it, so the two bounds can be held by tests that run in milliseconds instead
/// of by a simulator someone has to swipe on.
///
/// Every date it holds and every date it returns is the **start** of a day.
/// A browsed day is a calendar day, not an instant, and letting an instant
/// through would make two navigations to the same day compare unequal.
nonisolated struct TodayDayNavigation: Hashable, Sendable {

    // MARK: - The three days

    /// The day being shown.
    let day: Date

    /// The newest day that can be browsed, and the reason there is no forward
    /// bound to decide: **the future is not browsable.** A day that has not
    /// happened has no entries and never will have any until it is today, so a
    /// screen showing it would be an empty day the user cannot act on and
    /// cannot get out of except by coming back.
    let today: Date

    /// The oldest day that can be browsed: the day of the first meal ever
    /// logged.
    ///
    /// The alternative was to keep going into empty days forever. That is a
    /// walk with no end, and every step of it is the same screen; the first
    /// entry is where the user's record actually begins, and stopping there is
    /// the only bound that means anything. Empty days *inside* the range are
    /// still reachable — a day the user ate on and did not log is part of the
    /// record and says so.
    let earliest: Date

    private let calendar: Calendar

    // MARK: - Creation

    /// - Parameters:
    ///   - day: the day to show. Clamped into the range, so a stored day that
    ///     has fallen out of it — the store's oldest entry deleted, or the
    ///     browse carried across midnight — lands somewhere real rather than
    ///     showing a day the arrows cannot leave.
    ///   - now: the current instant, which decides what "today" is.
    ///   - firstEntry: when the oldest stored meal was logged, or `nil` for a
    ///     store nothing has been logged to.
    init(showing day: Date, now: Date, firstEntry: Date?, calendar: Calendar) {
        let today = calendar.startOfDay(for: now)
        // An empty store has no history, so the range is the current day alone
        // and both arrows are dead. `min` because a stored entry can be dated
        // after today — the log flow takes the device clock, and a clock that
        // moved backwards would otherwise put the far end of the range beyond
        // the near one.
        let earliest = min(calendar.startOfDay(for: firstEntry ?? now), today)

        self.init(
            day: Self.clamped(calendar.startOfDay(for: day), earliest: earliest, today: today),
            today: today,
            earliest: earliest,
            calendar: calendar
        )
    }

    private init(day: Date, today: Date, earliest: Date, calendar: Calendar) {
        self.day = day
        self.today = today
        self.earliest = earliest
        self.calendar = calendar
    }

    private static func clamped(_ day: Date, earliest: Date, today: Date) -> Date {
        min(max(day, earliest), today)
    }

    // MARK: - Where it can go

    var isToday: Bool { day == today }

    var canGoBackward: Bool { day > earliest }

    var canGoForward: Bool { day < today }

    /// Every day that can be browsed, for a control that offers them all at
    /// once rather than one at a time.
    var browsableDays: ClosedRange<Date> { earliest...today }

    // MARK: - Moving

    /// The day before this one, or this one again at the far end.
    ///
    /// Standing still rather than returning `nil`: the caller is a control that
    /// is already disabled at the bound, and a second answer to "can it move"
    /// is a second thing to keep in step with `canGoBackward`.
    func backward() -> Self {
        showing(calendar.date(byAdding: .day, value: -1, to: day) ?? day)
    }

    func forward() -> Self {
        showing(calendar.date(byAdding: .day, value: 1, to: day) ?? day)
    }

    /// Jumps straight to a day, clamped into the range the way the initialiser
    /// clamps — so a picker handed a date outside the range lands on the
    /// nearest one inside it instead of on nothing.
    func jumping(to date: Date) -> Self {
        showing(date)
    }

    private func showing(_ date: Date) -> Self {
        Self(
            day: Self.clamped(calendar.startOfDay(for: date), earliest: earliest, today: today),
            today: today,
            earliest: earliest,
            calendar: calendar
        )
    }

    // MARK: - What it is called

    var title: TodayDayTitle {
        TodayDayTitle(day: day, now: today, calendar: calendar)
    }

    /// Whether moving from `previous` to this landed on an earlier day.
    ///
    /// The direction a day change travels in, kept here rather than worked out
    /// at the call site: a swipe, an arrow and a date jump all have to travel
    /// the same way for the same move, and three call sites deciding
    /// separately is three chances for one of them to read backwards.
    func isBackward(from previous: Self) -> Bool {
        day < previous.day
    }
}

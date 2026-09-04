import Foundation
import Testing
import UIKit

@testable import Fuel

// MARK: - Fixtures

/// Day 7 at midday, so "now" is unambiguously inside its day and there is a
/// week of history behind it to walk into.
private nonisolated let now = at(12, 0, day: 7)

private nonisolated func navigation(
    showing day: Date = now,
    firstEntry: Date? = at(8, 14, day: 1)
) -> TodayDayNavigation {
    TodayDayNavigation(showing: day, now: now, firstEntry: firstEntry, calendar: testCalendar)
}

private nonisolated func startOfDay(_ day: Int) -> Date {
    at(0, 0, day: day)
}

// MARK: - The bounds

@Suite("Today · which days can be browsed")
struct TodayDayNavigationBoundsTests {

    @Test("a fresh navigation stands on today, at the start of it")
    func opensOnToday() {
        let navigation = navigation()

        #expect(navigation.isToday)
        #expect(navigation.day == startOfDay(7))
    }

    /// The forward bound, and the reason the forward arrow is drawn disabled
    /// rather than left out: there is a day past this one, it just cannot be
    /// browsed.
    @Test("the future is not browsable")
    func cannotGoPastToday() {
        let navigation = navigation()

        #expect(!navigation.canGoForward)
        #expect(navigation.forward().day == startOfDay(7))
        #expect(navigation.jumping(to: at(9, 0, day: 30)).day == startOfDay(7))
    }

    @Test("the walk back stops at the day of the first meal ever logged")
    func stopsAtTheFirstEntry() {
        var navigation = navigation(firstEntry: at(8, 14, day: 5))

        navigation = navigation.backward().backward()
        #expect(navigation.day == startOfDay(5))
        #expect(!navigation.canGoBackward)

        #expect(navigation.backward().day == startOfDay(5))
        #expect(navigation.jumping(to: at(12, 0, day: 0)).day == startOfDay(5))
    }

    /// An empty store has no record to walk into, so both arrows are dead and
    /// the only day is the current one.
    @Test("a store nothing has been logged to browses nowhere")
    func emptyStoreHasOneDay() {
        let navigation = navigation(firstEntry: nil)

        #expect(navigation.isToday)
        #expect(!navigation.canGoBackward)
        #expect(!navigation.canGoForward)
        #expect(navigation.browsableDays == startOfDay(7)...startOfDay(7))
    }

    /// The device clock can move backwards, and an entry dated after today
    /// would otherwise put the far end of the range past the near one and make
    /// the range itself invalid.
    @Test("an entry dated in the future does not push the range past today")
    func futureEntryIsClamped() {
        let navigation = navigation(firstEntry: at(9, 0, day: 40))

        #expect(navigation.earliest == startOfDay(7))
        #expect(navigation.browsableDays == startOfDay(7)...startOfDay(7))
    }

    @Test("the browsable range runs from the first entry's day to today")
    func rangeSpansTheHistory() {
        #expect(navigation().browsableDays == startOfDay(1)...startOfDay(7))
    }
}

// MARK: - Moving

@Suite("Today · moving between days")
struct TodayDayNavigationMovementTests {

    @Test("back one day, then forward again, lands where it started")
    func retreatsAndAdvances() {
        let today = navigation()
        let yesterday = today.backward()

        #expect(yesterday.day == startOfDay(6))
        #expect(yesterday.canGoForward)
        #expect(yesterday.forward().day == startOfDay(7))
    }

    /// A jump is the same movement as an arrow, so it has to normalise the same
    /// way: a picker hands back an instant, and two jumps to the same day must
    /// be the same navigation.
    @Test("a jump lands on the start of the chosen day, whatever time it carries")
    func jumpNormalisesToTheDay() {
        let morning = navigation().jumping(to: at(6, 30, day: 3))
        let evening = navigation().jumping(to: at(23, 45, day: 3))

        #expect(morning.day == startOfDay(3))
        #expect(morning == evening)
    }

    /// The direction all three entry points travel in. An arrow, a swipe and a
    /// jump that all land on the same day have to move the same way.
    @Test("a move to an earlier day reads backward, whichever control made it")
    func directionFollowsTheDay() {
        let today = navigation()
        let earlier = today.backward()
        let jumped = today.jumping(to: at(12, 0, day: 2))

        #expect(earlier.isBackward(from: today))
        #expect(jumped.isBackward(from: today))
        #expect(!today.isBackward(from: earlier))
        #expect(!today.isBackward(from: today))
    }

    /// A day held from before — the store's oldest entry deleted while it was
    /// showing, or midnight passing — is pulled back into the range rather than
    /// left outside it.
    @Test("a day outside the range is clamped into it")
    func staleDayIsClamped() {
        #expect(navigation(showing: at(12, 0, day: 0)).day == startOfDay(1))
        #expect(navigation(showing: at(12, 0, day: 99)).day == startOfDay(7))
    }
}

// MARK: - What the day is called

@Suite("Today · what the title says")
struct TodayDayTitleTests {

    @Test("the day being shown keeps the drawn word")
    func todayKeepsTheDrawnWord() {
        #expect(navigation().title == .today)
        #expect(TodayCopy.dayTitle(.today) == TodayCopy.title)
    }

    @Test("the day before is Yesterday, and anything older is its weekday")
    func earlierDaysAreNamed() {
        #expect(navigation().backward().title == .yesterday)
        #expect(navigation().backward().backward().title == .weekday(startOfDay(5)))
    }

    /// Five days after the epoch is 6 January 1970, a Tuesday, and the eyebrow
    /// above it abbreviates the same weekday — the two are different renderings
    /// on purpose.
    @Test("the weekday title is wide where the eyebrow is abbreviated")
    func weekdayIsWide() {
        let day = startOfDay(5)

        #expect(TodayFormat.weekday(day, timeZone: .gmt) == "Tuesday")
        #expect(TodayFormat.eyebrowDate(day, timeZone: .gmt) == "Tue, January 6")
    }

    /// The one place the interface would otherwise follow the device: a whole
    /// English word sitting in 25pt over an English screen.
    @Test("the weekday is English whatever the device is set to")
    func weekdayIgnoresTheDeviceLocale() {
        let day = startOfDay(5)

        #expect(
            TodayFormat.weekday(day, timeZone: .gmt)
                != TodayFormat.weekday(day, locale: Locale(identifier: "de_DE"), timeZone: .gmt)
        )
    }
}

// MARK: - The header the arrows sit in

/// The condition on this feature was that the drawn header does not move for
/// the navigation added to it. Two of the three claims that rest on are
/// arithmetic and are held here; the third — that the eyebrow and the title
/// keep the leading edge and the gear the trailing one — is layout and is held
/// by reading the view.
@Suite("Today · the header the arrows sit in")
struct TodayHeaderGeometryTests {

    /// The three header controls are 34pt circles with 44pt regions around
    /// them. At a `Space.s10` gap their centres are 44 apart, so the regions
    /// abut exactly: none of them steals a touch from its neighbour, and none
    /// of them leaves a dead strip between.
    @Test("the three header controls' touch regions abut without overlapping")
    func headerControlsTileTheirTouchRegions() {
        let pitch = FuelMetrics.Control.circleButton + FuelMetrics.Space.s10

        #expect(pitch == FuelMetrics.Control.minimumHitTarget)
    }

    /// The date and the title are the third way into the browse, so the block
    /// has to answer a finger. It carries `minimumHitTarget` as a floor, and
    /// this is what makes that a floor rather than something that grows the
    /// drawn header: the two drawn lines are already taller than a fingertip on
    /// their own, so the frame is never the thing deciding the height.
    ///
    /// Line heights rather than a rendered measurement, because that is what
    /// SwiftUI stacks: neither style sets a `lineHeightMultiple`, so each line
    /// occupies its font's own.
    @Test("the drawn date and title are past a fingertip without a frame saying so")
    func titleBlockClearsTheMinimumOnItsOwn() {
        let drawnHeight = FuelTypography.meta.uiFont.lineHeight
            + FuelTypography.screenTitle.uiFont.lineHeight

        #expect(drawnHeight > FuelMetrics.Control.minimumHitTarget)
    }
}

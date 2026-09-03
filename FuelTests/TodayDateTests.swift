import Foundation
import Testing

@testable import Fuel

// MARK: - Fixtures

/// The day the export draws on both Today screens: 2 September 2025, midday
/// UTC. Midday rather than midnight so the instant is unambiguous, and the zone
/// is named at every call site rather than left to the machine.
private nonisolated let drawnDay = Date(timeIntervalSince1970: 1_756_814_400)

private nonisolated let berlin = TimeZone(identifier: "Europe/Berlin")!

// MARK: - Eyebrow date

@Suite("Today · the date eyebrow")
struct TodayDateTests {

    @Test("the eyebrow is built in English whatever the device is set to")
    func eyebrowIgnoresTheDeviceLocale() {
        let pinned = TodayFormat.eyebrowDate(drawnDay, timeZone: berlin)
        let german = TodayFormat.eyebrowDate(
            drawnDay,
            locale: Locale(identifier: "de_DE"),
            timeZone: berlin
        )

        #expect(pinned == TodayFormat.eyebrowDate(drawnDay, locale: .init(identifier: "en"), timeZone: berlin))
        #expect(pinned != german)
    }

    /// The two things the German rendering got wrong, named one at a time so a
    /// failure says which came back.
    @Test("English drops the German ordinal dot and keeps the drawn comma")
    func eyebrowPunctuation() {
        let eyebrow = TodayFormat.eyebrowDate(drawnDay, timeZone: berlin)

        #expect(eyebrow.contains(","))
        #expect(!eyebrow.contains("2."))
    }

    /// The field set is the drawn one — abbreviated weekday, day, wide month —
    /// even though English orders month and day the other way round.
    @Test("the drawn fields are all there, and only those")
    func eyebrowFields() {
        let eyebrow = TodayFormat.eyebrowDate(drawnDay, timeZone: berlin)

        #expect(eyebrow == "Tue, September 2")
    }

    /// The day is read in the zone it is asked for, not in the machine's. A
    /// date is filed by calendar day everywhere else in Fuel, and the eyebrow
    /// names that day.
    @Test("the eyebrow follows the time zone it is given")
    func eyebrowFollowsItsTimeZone() {
        let auckland = TimeZone(identifier: "Pacific/Auckland")!

        #expect(TodayFormat.eyebrowDate(drawnDay, timeZone: auckland) == "Wed, September 3")
    }
}

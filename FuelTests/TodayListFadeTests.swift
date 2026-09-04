import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Where the day list stops being visible

/// The two bands that take Today's list out at the edges of the screen, and the
/// one thing both of them are for: content that has scrolled past the ends of
/// the screen stops being drawn before it reaches anything that is standing
/// still there.
///
/// **Rendered rather than asserted, for the reason `MealResultFooterTests` is.**
/// Every value behind the bottom band was right and the screen was still wrong:
/// a band aligned to the safe area ends where the safe area does, which is 34
/// points above the frame's own bottom edge, and the list ran on underneath it
/// at full contrast. What the owner saw was a row drawn *brighter* than the
/// dimmed row above it, with a visible edge between them. No arithmetic over
/// `FuelMetrics.ListFade` can see that; the drawn screen can.
///
/// **The profile is taken over several scroll positions and combined**, which is
/// what makes it a measurement of the band rather than of the list. At any one
/// position a scanline can fall in the gap between two rows and read as
/// background whether or not anything is covering it, so a run of blanks would
/// pass a test about a band that had been deleted. A height reads as background
/// here only if nothing managed to show there at any of the positions.
@Suite("Today · the list fades at both edges", .serialized)
@MainActor
struct TodayListFadeTests {

    // MARK: - Fixtures

    /// Light, so the ink the rows are drawn in stands as far from the ground as
    /// it ever does, and blue, so the add button is findable. The same pair
    /// `MealResultFooterTests` measures against.
    private static let palette = FuelPalette(theme: .light, accent: .blue)

    private static let date = Calendar.current.startOfDay(
        for: Date(timeIntervalSince1970: 1_756_771_200)
    )

    /// A day far longer than the screen, so there is list above and below both
    /// bands at every position sampled.
    private static var day: [NutritionEntry] {
        let labels: [MealLabel] = [.breakfast, .lunch, .snack, .dinner]
        return (0..<16).map { index in
            NutritionEntry(
                title: "Row number \(index + 1)",
                kilocalories: 120 + index,
                macros: MacroTotals(protein: 10, carbs: 20, fat: 5),
                loggedAt: date.addingTimeInterval(Double(index) * 3_000 + 25_000),
                source: .photo,
                label: labels[index % labels.count]
            )
        }
    }

    /// Goal mode, which is the screen the owner reported both times.
    private func screen() -> some View {
        TodayView(
            presentation: TodayPresentation(entries: Self.day, mode: .goal(.default), date: Self.date),
            navigation: TodayDayNavigation(
                showing: Self.date,
                now: Self.date,
                firstEntry: Calendar.current.date(byAdding: .day, value: -14, to: Self.date),
                calendar: .current
            ),
            isTravellingBackward: false,
            gettingStarted: TodayGettingStarted(
                hasChosenTheme: true,
                hasChosenAccent: true,
                hasLoggedMeal: true
            ),
            onOpenSettings: {},
            onAddEntry: {},
            onOpenMeal: { _ in },
            onShowPreviousDay: {},
            onShowNextDay: {},
            onShowDay: { _ in }
        )
    }

    private func hosted() throws -> HostedScreen {
        try HostedScreen(screen(), palette: Self.palette)
    }

    // MARK: - Measuring

    /// How many scroll positions the profile is taken over, and how far apart
    /// they stand.
    ///
    /// Eight steps of 14 cover 98 points, which is more than the 68 a row of
    /// this list occupies, so no gap between two rows can sit at the same height
    /// in every reading.
    private static let positions = 8
    private static let positionStep: CGFloat = 14

    /// The most any content managed to show at each height of the window.
    ///
    /// The positions stop a whole clearance short of the end — the padding under
    /// the last row plus the scroll view's own bottom inset — so real rows still
    /// cross both bands rather than the empty space that holds them off.
    ///
    /// Only the leading half of each row is read. The add button is drawn in the
    /// accent on top of the bottom band, and it is meant to be: it stands over
    /// the fade rather than under it, so counting its pixels as content showing
    /// through would measure the wrong thing entirely.
    private func fadeProfile(of hosted: HostedScreen) throws -> [Int] {
        let list = try #require(hosted.scrollView)
        let end = list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom
        let clearance = FuelMetrics.ListFade.height + list.adjustedContentInset.bottom
        let background = DrawnPixels.Channels(Self.palette.background)
        let height = Int(hosted.window.bounds.height)
        var profile = [Int](repeating: .zero, count: height)

        for step in 0..<Self.positions {
            list.setContentOffset(
                CGPoint(x: .zero, y: end - clearance - CGFloat(step) * Self.positionStep),
                animated: false
            )
            hosted.settle()

            let drawing = try #require(hosted.drawing)
            let leading = 0..<(Int(drawing.size.width) / 2)
            for y in 0..<height {
                profile[y] = max(profile[y], drawing.peakDeviation(fromColour: background, y: y, x: leading))
            }
        }

        return profile
    }

    /// The most anything showed within a distance of one edge of the frame.
    private func peak(of profile: [Int], within depth: CGFloat, of edge: VerticalEdge) -> Int {
        heights(of: profile, from: .zero, to: depth, of: edge).reduce(.zero) { max($0, profile[$1]) }
    }

    /// A band cut into three, reported from the frame's edge inward.
    ///
    /// Three rather than more: a slice has to be wider than the tallest run of
    /// background between two rows, or it reads zero for want of content rather
    /// than because something covered it.
    private func slices(of profile: [Int], across band: CGFloat, from edge: VerticalEdge) -> [Int] {
        let depth = band / 3
        return (0..<3).map { step in
            heights(
                of: profile,
                from: CGFloat(step) * depth,
                to: CGFloat(step + 1) * depth,
                of: edge
            )
            .reduce(.zero) { max($0, profile[$1]) }
        }
    }

    private func heights(
        of profile: [Int],
        from near: CGFloat,
        to far: CGFloat,
        of edge: VerticalEdge
    ) -> Range<Int> {
        switch edge {
        case .top: Int(near)..<Int(far)
        case .bottom: (profile.count - Int(far))..<(profile.count - Int(near))
        }
    }

    /// A band gets less visible the closer it comes to the edge, and never the
    /// other way about.
    ///
    /// The slack is `DrawnPixels.tolerance`, the same one that decides whether a
    /// pixel is the background at all: under an opaque part of a band the
    /// readings sit at nought or one, and a slice reading one beside a slice
    /// reading nought is not a reversal. The reversal this exists to catch put
    /// 250 below 1.
    private func expectDarkensTowardTheEdge(
        _ measured: [Int],
        _ edge: VerticalEdge,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for step in 1..<measured.count {
            #expect(
                measured[step - 1] <= measured[step] + DrawnPixels.tolerance,
                "\(edge) slices \(measured) brighten toward the edge",
                sourceLocation: sourceLocation
            )
        }
    }

    // MARK: - The bottom

    /// The band the design writes down, and the two things that were wrong about
    /// where it stood.
    ///
    /// `ListFade.opaqueStop` of `ListFade.height` is the part of it that is the
    /// background and nothing else — 55 points of the 120. Measured from the
    /// frame's own bottom edge, that is a strip in which the list cannot be
    /// visible at all. It was: the band ended at the safe area, and the 34
    /// points below it drew rows at full contrast.
    @Test("the list fades out into the bottom edge and never back in")
    func bottomBand() throws {
        let profile = try fadeProfile(of: hosted())
        let opaque = FuelMetrics.ListFade.height * FuelMetrics.ListFade.opaqueStop

        #expect(
            peak(of: profile, within: opaque, of: .bottom) <= DrawnPixels.tolerance,
            "the list shows \(peak(of: profile, within: opaque, of: .bottom)) levels through the \(opaque) points the band is opaque for"
        )
        expectDarkensTowardTheEdge(
            slices(of: profile, across: FuelMetrics.ListFade.height, from: .bottom),
            .bottom
        )
    }

    // MARK: - The top

    /// The other end, and the strip that matters there: the one the system draws
    /// its clock, its indicators and its island into, which is the top safe area.
    ///
    /// The owner reported the day's total travelling up into it and being drawn
    /// straight through the time. `FuelListTopFade` is opaque across exactly that
    /// strip, which is why the claim here is stated against the window's own
    /// inset rather than against a fraction of a band.
    @Test("the list fades out into the top edge and never back in")
    func topBand() throws {
        let hosted = try hosted()
        let reserved = hosted.window.safeAreaInsets.top
        let profile = try fadeProfile(of: hosted)

        #expect(
            peak(of: profile, within: reserved, of: .top) <= DrawnPixels.tolerance,
            "the list shows \(peak(of: profile, within: reserved, of: .top)) levels through the \(reserved) points the system reserves"
        )
        expectDarkensTowardTheEdge(
            slices(of: profile, across: reserved + FuelMetrics.Space.s26, from: .top),
            .top
        )
    }

    /// The condition on the top band: it is there for content passing under the
    /// header, not for the header.
    ///
    /// The header does not move when the list scrolls — it is the first thing in
    /// the list — so where it comes to rest is where it stays, and a band that
    /// reached it would wash out the date, the title and all three controls for
    /// as long as the screen was up. Stated as the geometry rather than as a
    /// colour: at rest nothing at all is drawn above the band's bottom edge, so
    /// there is nothing there for it to dim.
    @Test("the top band is gone before the header it comes to rest above")
    func headerAtRest() throws {
        let hosted = try hosted()
        let drawing = try #require(hosted.drawing)
        let background = DrawnPixels.Channels(Self.palette.background)
        let band = hosted.window.safeAreaInsets.top + FuelMetrics.Space.s26

        let first = (0..<Int(drawing.size.height)).first { y in
            drawing.peakDeviation(fromColour: background, y: y, x: 0..<Int(drawing.size.width))
                > DrawnPixels.tolerance
        }

        #expect(
            CGFloat(try #require(first)) >= band,
            "the first thing drawn stands at \(first ?? 0) with the band reaching \(band)"
        )
    }

    // MARK: - What stands over the band

    /// The add button is the thing the bottom band exists to clear a way under,
    /// and it does not move for it.
    ///
    /// Both bands are laid out by taking the frame's own edge rather than the
    /// safe area's, and the button is not: the export's 32 is a distance above
    /// the home indicator, which is what `Control.addButtonBottomInset` says and
    /// why it is larger than the inset at the side. This is here so a later hand
    /// cannot bring the button along with the band.
    ///
    /// Only the bottom-trailing quarter of the screen is searched. The ring and
    /// the macro bars are drawn in the accent too, and they are at the top.
    @Test("the add button keeps the inset the export draws it at")
    func addButtonIsUnmoved() throws {
        let hosted = try hosted()
        let drawing = try #require(hosted.drawing)
        let corner = CGRect(
            x: drawing.size.width / 2,
            y: drawing.size.height / 2,
            width: drawing.size.width / 2,
            height: drawing.size.height / 2
        )
        let box = try #require(
            drawing.box(ofColour: DrawnPixels.Channels(Self.palette.accentColor), in: corner)
        )

        expect(box.right, isTheDrawn: FuelMetrics.Control.addButtonTrailingInset)
        expect(
            box.bottom,
            isTheDrawn: hosted.window.safeAreaInsets.bottom + FuelMetrics.Control.addButtonBottomInset
        )
    }
}

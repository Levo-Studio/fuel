import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Settings chrome

/// What the two-segment control draws, and what it answers a finger in.
///
/// The two are deliberately not the same number and this is where that is
/// held: the export draws a 13pt label between 11 or 12 points of padding, a
/// box shorter than the 44 a fingertip needs, and the control makes up the
/// difference in a region that overhangs the drawing instead of enlarging it.
///
/// Whether a touch is actually delivered into that region is not observable
/// from a unit test — a hosting view answers `hitTest` for every point inside
/// it, and SwiftUI builds no accessibility element until an assistive client
/// asks for one. What is observable is the geometry the delivery follows from,
/// and it is checked in both halves: the drawn box is still exactly the
/// export's, and an overlay offered that box's height still takes the minimum.
@MainActor
@Suite("Settings chrome")
struct SettingsChromeTests {

    /// The width screens 16 and 17 leave a section: 390 less the 28pt margin on
    /// each side.
    private let sectionWidth: CGFloat = 334

    // MARK: - The drawn box

    /// The control is drawn out of exactly two things, and the hit region is
    /// neither of them. A fix that reached the 44 by growing the box — a
    /// `minHeight` on the pill rather than on an overlay over it — puts the
    /// segment 3.33 points taller than the export draws it and pushes
    /// everything below it down the screen; that is what this goes red for.
    @Test("a segment is the export's label between the export's padding, and nothing else", arguments: [11, 12])
    func aSegmentIsDrawnAsExported(padding: CGFloat) {
        let drawn = height(of: control(padding: padding))
        #expect(drawn == labelHeight + padding * 2)
    }

    /// Why the region exists at all. Both drawn heights — 38.67 with the
    /// provider control's 11 and 40.67 with the 12 every other one uses — are
    /// short of a fingertip.
    @Test("either drawn segment is smaller than a finger", arguments: [11, 12])
    func aSegmentIsDrawnSmallerThanAFinger(padding: CGFloat) {
        #expect(height(of: control(padding: padding)) < FuelMetrics.Control.minimumHitTarget)
    }

    // MARK: - The region over it

    /// The half the drawn box cannot show, and the SwiftUI guarantee the fix
    /// rests on: an overlay is offered its host's size, and one asking for
    /// `minimumHitTarget` takes the minimum instead — while the host, checked
    /// above, keeps the height the export gives it.
    @Test("a region offered a drawn segment still takes a finger's worth", arguments: [11, 12])
    func theRegionReachesTheMinimum(padding: CGFloat) {
        let drawn = height(of: control(padding: padding))
        let region = Color.clear.frame(minHeight: FuelMetrics.Control.minimumHitTarget)

        #expect(height(of: region, proposing: drawn) == FuelMetrics.Control.minimumHitTarget)
    }

    // MARK: - Helpers

    private func control(padding: CGFloat) -> some View {
        SettingsSegmentedControl(
            options: [FuelTheme.light, FuelTheme.dark],
            titleKey: \.settingsSegmentTitle,
            selection: .constant(FuelTheme.dark),
            padding: padding
        )
    }

    /// A bare segment label, so the drawn box is checked against the two things
    /// it is made of rather than against a height typed out here — the line
    /// height of 13pt Plus Jakarta Sans is the text engine's to state, not the
    /// test's.
    private var labelHeight: CGFloat {
        height(of: Text(verbatim: "Light").fuelStyle(FuelTypography.segmentLabel))
    }

    private func height(of view: some View, proposing proposal: CGFloat = .greatestFiniteMagnitude) -> CGFloat {
        UIHostingController(rootView: view).sizeThatFits(
            in: CGSize(width: sectionWidth, height: proposal)
        ).height
    }
}

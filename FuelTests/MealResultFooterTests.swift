import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - The footer's drawn box

/// Where the footer of screens 14 and 15 comes to rest:
/// `Screens2c.dc.html` lines 341 and 381, `left:28;right:28;bottom:34`.
///
/// **Rendered rather than asserted, because the claim is about the screen and
/// not about a constant.** The two numbers in the code are right on their own —
/// `Screen.horizontalPadding` is 28 and `Space.s34` is 34 — and the screen was
/// still wrong: a drawn bottom distance added *above* the safe area is spent
/// twice on a device with a home indicator, and the footer stood 68 from the
/// bottom edge with the list running into it. No arithmetic over `FuelMetrics`
/// can catch that. Hosting the screen and measuring what was drawn can.
///
/// The measurement is a pixel scan for the accent fill, which on these screens
/// belongs to one thing only: the wide footer button. `HostedScreen` puts the
/// screen on a real window and `DrawnPixels` reads it back; the box that comes
/// out is in the export's own units.
///
/// Both screens are here because both stand a footer in this place —
/// `MealResultView`'s own, and `MealDetailView`'s, which is drawn outside that
/// view and reaches for the same ground.
///
/// The last test asks the other half of the same question — not where the
/// footer stands, but where the list under it stops — and takes that from the
/// scroll view rather than from the pixels, because the rows are drawn into the
/// hosting view and leave nothing of their own to measure.
@Suite("Meal result · the footer's drawn box", .serialized)
@MainActor
struct MealResultFooterTests {

    // MARK: - Hosting

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    private func hosted(_ view: some View) throws -> HostedScreen {
        try HostedScreen(view, palette: Self.palette)
    }

    /// The accent-filled button's box: insets from the three edges it is drawn
    /// against, and the y its top edge stands at.
    ///
    /// The whole window is searched, because the pill is the only accent on
    /// either of these screens.
    private func accentBox(of hosted: HostedScreen) throws -> DrawnPixels.Box {
        let drawing = try #require(hosted.drawing)
        return try #require(drawing.box(ofColour: DrawnPixels.Channels(Self.palette.accentColor)))
    }

    // MARK: - Fixtures

    /// More rows than fit, so the screen under test is the one the owner was
    /// looking at: a list long enough to run under the footer.
    private static var longDraft: MealResultDraft {
        MealResultDraft(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
            advice: nil,
            items: (1...9).map { index in
                RecognisedItem(
                    name: "Row number \(index)",
                    kilocalories: 90 + index,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            },
            label: .dinner,
            isLabelUserSet: false,
            isFavourite: false
        )
    }

    /// The same list on a meal that is already in the store, with a tenth row
    /// nobody has priced.
    ///
    /// The added row is what puts the accent pill in this screen's footer —
    /// `MealDetailView` draws two small corner controls until the breakdown
    /// carries an edit — and that pill is the only accent on the screen, which
    /// is what makes it findable. The store is not held here because the model
    /// holds it.
    private func loggedMeal() throws -> MealDetailModel {
        let store = try FuelStore(inMemory: true)
        let entry = try store.log(
            title: "Salmon with polenta",
            kilocalories: 460,
            macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
            loggedAt: Date(),
            source: .photo,
            items: (1...9).map { index in
                RecognisedItem(
                    name: "Row number \(index)",
                    kilocalories: 90 + index,
                    note: .photo(confidence: .confident, approximateGrams: 150)
                )
            }
        )
        let model = try #require(
            MealDetailModel(entryID: entry.entryID, store: store, client: ScriptedClient(), keys: StoredKey())
        )
        model.addItem("A row the model has not read")
        return model
    }

    // MARK: - The scan result

    /// No leading control, so the filled button starts at the drawn left inset
    /// and all three distances are the export's own.
    @Test("the scan result's footer sits in the box the export draws")
    func scanResultFooter() throws {
        let view = PhotoResultView(
            draft: Self.longDraft,
            photo: nil,
            onBack: {},
            onCycleLabel: {},
            onToggleFavourite: {},
            onRemoveItem: { _ in },
            onEditItem: { _, _ in },
            onAddItem: { _ in },
            onReanalyse: {},
            onDiscard: nil,
            commit: MealResultAction(title: MealResultCopy.add, perform: {})
        )

        let box = try accentBox(of: hosted(view))

        expect(box.left, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        expect(box.right, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        expect(box.bottom, isTheDrawn: FuelMetrics.Space.s34)
    }

    // MARK: - The logged meal

    /// The same box on the screen whose footer is drawn outside
    /// `MealResultView`. It draws the accent pill once the breakdown carries an
    /// edit nobody has priced, which is why the fixture adds a row.
    @Test("a logged meal's footer sits in the same box")
    func mealDetailFooter() throws {
        let box = try accentBox(of: hosted(MealDetailView(model: try loggedMeal(), onClose: {})))

        expect(box.left, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        expect(box.right, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        expect(box.bottom, isTheDrawn: FuelMetrics.Space.s34)
    }

    // MARK: - What the list keeps clear

    /// The other half of the same arrangement, and the half a footer's box
    /// cannot see: the list ends where the footer begins.
    ///
    /// `MealResultView.breakdown` reaches for `mealResultFooter` only where it
    /// has a footer of its own to draw, and that branch is what is under test
    /// here. `MealDetailView` stands its footer by applying the same modifier
    /// from outside, and the modifier strips the container's bottom inset from
    /// everything beneath it — the outer footer's own contribution included.
    /// Applied a second time inside, with nothing to draw, it takes the list's
    /// clearance of that footer away with it and the last row comes to rest
    /// under the trash mark.
    ///
    /// Neither test above can see that. Both measure the pill, and the pill
    /// stands in its drawn box either way.
    ///
    /// The list is dragged to its end first, because the clearance is only
    /// visible where the content stops: unscrolled, the last row is off the
    /// bottom of the screen in both arrangements.
    @Test("a logged meal's breakdown comes to rest above its footer")
    func mealDetailBreakdownClearsTheFooter() throws {
        let screen = try hosted(MealDetailView(model: try loggedMeal(), onClose: {}))
        let list = try #require(screen.scrollView)

        // `scrollRectToVisible` rather than an offset worked out here: it stops
        // at whatever the scroll view's own bottom inset allows, and that inset
        // is the thing being measured rather than something this test may
        // assume.
        list.scrollRectToVisible(
            CGRect(x: .zero, y: list.contentSize.height - 1, width: 1, height: 1),
            animated: false
        )
        screen.settle()

        let footer = try accentBox(of: screen)
        let listBottom = list.convert(CGPoint(x: .zero, y: list.contentSize.height), to: screen.window).y

        // One point of slack, the same one `expect(_:isTheDrawn:)` allows and
        // for the same reason: the pill's top is a curve, and a scan of it can
        // land a point either side of the drawn edge. What this catches is the
        // last row a whole footer's height too low, and no antialiasing
        // accounts for that.
        #expect(
            listBottom <= CGFloat(footer.top) + 1,
            "the list ends at \(listBottom) with the footer drawn from \(footer.top)"
        )
    }
}

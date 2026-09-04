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
/// belongs to one thing only: the wide footer button. The renderer is asked for
/// the standard range at scale 1, so a pixel index is a point and the distances
/// below are the export's own units.
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

    /// Draws the view in a window on the test host's own scene, at the size and
    /// with the safe area the device actually has.
    private func render(_ view: some View) throws -> (image: UIImage, size: CGSize) {
        drawing(of: try host(view))
    }

    /// Stands the view on a window and hands the window back.
    ///
    /// Separate from the drawing because one of the questions here is not about
    /// pixels: where the list comes to rest is a property of the scroll view
    /// under the rows, and that view has to be reachable to be asked.
    private func host(_ view: some View) throws -> UIWindow {
        // The test host's own scene, so the window comes up at the device's
        // size with the device's safe area rather than a frame a test made up.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(
            rootView: view.environment(\.fuelPalette, Self.palette)
        )
        window.makeKeyAndVisible()
        // Long enough for SwiftUI to lay the screen out and for the window to
        // have something to draw.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        window.layoutIfNeeded()
        return window
    }

    private func drawing(of window: UIWindow) -> (image: UIImage, size: CGSize) {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return (image, window.bounds.size)
    }

    /// The breakdown's own scroll view, out of the hosted hierarchy.
    ///
    /// The rows are drawn into the hosting view rather than into views of their
    /// own, so there is no row to measure — but the scroll view they are drawn
    /// inside is a real one, and where its content comes to rest is the whole
    /// question. `MealResultView.list` is the only one either screen has.
    private func breakdownScrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let found = subview as? UIScrollView { return found }
            if let nested = breakdownScrollView(in: subview) { return nested }
        }
        return nil
    }

    // MARK: - Measuring

    private struct Box {
        var left = 0
        var right = 0
        var bottom = 0

        /// The one edge the button is not drawn against, and so a y rather than
        /// an inset: where the footer begins, which is where the list above it
        /// has to stop.
        var top = 0
    }

    /// The accent-filled button's box: insets from the three edges it is drawn
    /// against, and the y its top edge stands at.
    ///
    /// A tolerance of a few levels per channel rather than an exact match:
    /// the pill is drawn at `Radius.pill`, so every edge is a curve, and the
    /// outermost row and column of it are blended with the ground behind. What
    /// this finds is the last fully painted pixel, which puts each of the three
    /// insets one point outside the drawn one — see `expect(_:isTheDrawn:)`.
    /// `top` is the same reading taken from the other side, so it can land a
    /// point in either direction.
    private func accentBox(in image: UIImage, size: CGSize) -> Box? {
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data else { return nil }
        let bytes = CFDataGetBytePtr(data)!
        var accent = (red: CGFloat.zero, green: CGFloat.zero, blue: CGFloat.zero, alpha: CGFloat.zero)
        UIColor(Self.palette.accentColor).getRed(&accent.red, green: &accent.green, blue: &accent.blue, alpha: &accent.alpha)
        let tolerance = 6

        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min

        for y in 0..<cgImage.height {
            for x in 0..<cgImage.width {
                // BGRA, which is what the renderer hands back on this platform.
                let pixel = bytes + y * cgImage.bytesPerRow + x * 4
                guard
                    abs(Int(pixel[2]) - Int(accent.red * 255)) <= tolerance,
                    abs(Int(pixel[1]) - Int(accent.green * 255)) <= tolerance,
                    abs(Int(pixel[0]) - Int(accent.blue * 255)) <= tolerance
                else {
                    continue
                }
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX else { return nil }
        return Box(
            left: minX,
            right: Int(size.width) - maxX - 1,
            bottom: Int(size.height) - maxY - 1,
            top: minY
        )
    }

    /// A measured distance against a drawn one, to the point.
    ///
    /// One point of slack, and only one: the scan reports the last fully
    /// painted pixel of a curved edge, so a footer standing exactly where the
    /// export draws it measures 28 or 29 rather than 28 alone. The mistake this
    /// suite exists to catch was a footer 34 points out of place, which no
    /// amount of antialiasing accounts for.
    private func expect(
        _ measured: Int,
        isTheDrawn drawn: CGFloat,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(abs(CGFloat(measured) - drawn) <= 1, "measured \(measured) against a drawn \(drawn)", sourceLocation: sourceLocation)
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

        let drawn = try render(view)
        let box = try #require(accentBox(in: drawn.image, size: drawn.size))

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
        let drawn = try render(MealDetailView(model: try loggedMeal(), onClose: {}))
        let box = try #require(accentBox(in: drawn.image, size: drawn.size))

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
        let window = try host(MealDetailView(model: try loggedMeal(), onClose: {}))
        let list = try #require(breakdownScrollView(in: window))

        // `scrollRectToVisible` rather than an offset worked out here: it stops
        // at whatever the scroll view's own bottom inset allows, and that inset
        // is the thing being measured rather than something this test may
        // assume.
        list.scrollRectToVisible(
            CGRect(x: .zero, y: list.contentSize.height - 1, width: 1, height: 1),
            animated: false
        )
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        window.layoutIfNeeded()

        let drawn = drawing(of: window)
        let footer = try #require(accentBox(in: drawn.image, size: drawn.size))
        let listBottom = list.convert(CGPoint(x: .zero, y: list.contentSize.height), to: window).y

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

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
@Suite("Meal result · the footer's drawn box", .serialized)
@MainActor
struct MealResultFooterTests {

    // MARK: - Hosting

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    /// Draws the view in a window the size of the device's own screen, so the
    /// safe area under the footer is a real one rather than a number a test
    /// made up.
    private func render(_ view: some View) -> (image: UIImage, size: CGSize) {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = UIScreen.main.bounds
        window.rootViewController = UIHostingController(
            rootView: view.environment(\.fuelPalette, Self.palette)
        )
        window.makeKeyAndVisible()
        // Long enough for SwiftUI to lay the screen out and for the window to
        // have something to draw.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        window.layoutIfNeeded()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return (image, window.bounds.size)
    }

    // MARK: - Measuring

    private struct Box {
        var left = 0
        var right = 0
        var bottom = 0
    }

    /// The accent-filled button's box, as insets from the three edges it is
    /// drawn against.
    ///
    /// A tolerance of a few levels per channel rather than an exact match:
    /// the pill is drawn at `Radius.pill`, so every edge is a curve, and the
    /// outermost row and column of it are blended with the ground behind. What
    /// this finds is the last fully painted pixel, which puts each distance
    /// one point outside the drawn one — see `expect(_:isTheDrawn:)`.
    private func accentBox(in image: UIImage, size: CGSize) -> Box? {
        guard let cgImage = image.cgImage, let data = cgImage.dataProvider?.data else { return nil }
        let bytes = CFDataGetBytePtr(data)!
        var accent = (red: CGFloat.zero, green: CGFloat.zero, blue: CGFloat.zero, alpha: CGFloat.zero)
        UIColor(Self.palette.accentColor).getRed(&accent.red, green: &accent.green, blue: &accent.blue, alpha: &accent.alpha)
        let tolerance = 6

        var minX = Int.max
        var maxX = Int.min
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
                maxY = max(maxY, y)
            }
        }

        guard minX <= maxX else { return nil }
        return Box(left: minX, right: Int(size.width) - maxX - 1, bottom: Int(size.height) - maxY - 1)
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

        let drawn = render(view)
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

        let drawn = render(MealDetailView(model: model, onClose: {}))
        let box = try #require(accentBox(in: drawn.image, size: drawn.size))

        expect(box.left, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        expect(box.right, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        expect(box.bottom, isTheDrawn: FuelMetrics.Space.s34)
    }
}

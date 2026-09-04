import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - A screen on a real window

/// A Fuel screen stood on the test host's own scene, so it comes up at the
/// device's size with the device's safe area rather than in a frame a test made
/// up.
///
/// **Rendered rather than asserted, because the claims it serves are about the
/// screen and not about a constant.** Two of them have gone wrong here with
/// every value behind them right: a drawn bottom distance added *above* the safe
/// area is spent twice and stands a footer 34 points too high, and a fade band
/// aligned to the safe area stops 34 points short of the edge and leaves the
/// list showing under it. No arithmetic over `FuelMetrics` can catch either.
/// Hosting the screen and measuring what was drawn can.
///
/// The window comes from the scene rather than from `UIWindow(frame:)`, which
/// iOS 26 deprecates, and which would have made up a safe area as well as a
/// size.
@MainActor
struct HostedScreen {

    let window: UIWindow

    init(_ view: some View, palette: FuelPalette) throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(
            rootView: view.environment(\.fuelPalette, palette)
        )
        window.makeKeyAndVisible()
        // Long enough for SwiftUI to lay the screen out and for the window to
        // have something to draw.
        settle(for: 0.6)
    }

    /// Lets the run loop reach the layout, which is what a fresh window and a
    /// moved scroll view both need before anything is worth measuring.
    func settle(for seconds: TimeInterval = 0.2) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
        window.layoutIfNeeded()
    }

    /// The screen's own scroll view.
    ///
    /// Rows are drawn into the hosting view rather than into views of their own,
    /// so there is no row to measure — but the scroll view they are drawn inside
    /// is a real one, and where its content comes to rest, and where it can be
    /// dragged to, is the whole question in both suites that ask for it. The
    /// screens here have one apiece.
    var scrollView: UIScrollView? { Self.scrollView(in: window) }

    private static func scrollView(in view: UIView) -> UIScrollView? {
        for subview in view.subviews {
            if let found = subview as? UIScrollView { return found }
            if let nested = scrollView(in: subview) { return nested }
        }
        return nil
    }

    /// What stands on the screen now, in pixels.
    var drawing: DrawnPixels? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        return DrawnPixels(image)
    }
}

// MARK: - The pixels that came out

/// One drawn frame, read back a pixel at a time.
///
/// The renderer is asked for the standard range at scale 1, so a pixel index is
/// a point and every distance a scan reports is in the export's own units.
@MainActor
struct DrawnPixels {

    /// How far off a colour a pixel may be and still count as that colour.
    ///
    /// A few levels per channel rather than an exact match, because nothing
    /// measured through this type has a hard edge: a pill drawn at `Radius.pill`
    /// blends its outermost row and column into the ground behind it, and a
    /// gradient laid over the background settles a level or two off it. What a
    /// scan finds is therefore the last fully painted pixel rather than the
    /// geometric edge, which puts an inset a point outside the drawn one. The
    /// mistakes these suites exist to catch are 34 points wide.
    static let tolerance = 6

    let size: CGSize

    private let image: CGImage

    /// Held because the pointer below belongs to it: `CFDataGetBytePtr` hands
    /// back a borrowed pointer, and letting the data go would leave it dangling.
    private let data: CFData

    private let bytes: UnsafePointer<UInt8>

    init?(_ drawn: UIImage) {
        guard
            let image = drawn.cgImage,
            let data = image.dataProvider?.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            return nil
        }
        self.image = image
        self.data = data
        self.bytes = bytes
        size = CGSize(width: image.width, height: image.height)
    }

    /// A palette colour in the bytes the renderer hands back.
    struct Channels {

        let red: Int
        let green: Int
        let blue: Int

        init(_ colour: Color) {
            var components = (red: CGFloat.zero, green: CGFloat.zero, blue: CGFloat.zero, alpha: CGFloat.zero)
            UIColor(colour).getRed(&components.red, green: &components.green, blue: &components.blue, alpha: &components.alpha)
            red = Int(components.red * 255)
            green = Int(components.green * 255)
            blue = Int(components.blue * 255)
        }
    }

    /// Where something drawn stands, as insets from the three edges it is drawn
    /// against and the y its top edge reaches.
    struct Box {

        var left = 0
        var right = 0
        var bottom = 0

        /// The one edge a footer control is not drawn against, and so a y rather
        /// than an inset: where it begins, which is where the list above it has
        /// to stop.
        var top = 0
    }

    /// How far the pixel at a point stands from a colour, on its furthest
    /// channel.
    func deviation(fromColour colour: Channels, x: Int, y: Int) -> Int {
        // BGRA, which is what the renderer hands back on this platform.
        let pixel = bytes + y * image.bytesPerRow + x * 4
        return max(
            abs(Int(pixel[2]) - colour.red),
            abs(Int(pixel[1]) - colour.green),
            abs(Int(pixel[0]) - colour.blue)
        )
    }

    /// The same reading taken across one row of the drawing, kept at its
    /// furthest: how much of anything at all is showing at that height.
    func peakDeviation(fromColour colour: Channels, y: Int, x range: Range<Int>) -> Int {
        range.reduce(.zero) { peak, x in
            max(peak, deviation(fromColour: colour, x: x, y: y))
        }
    }

    /// The tightest box around everything drawn in a colour, or nothing if the
    /// colour is not on the screen.
    ///
    /// `region` narrows the search to a part of the window, for a screen that
    /// draws the colour in more than one place.
    func box(ofColour colour: Channels, in region: CGRect? = nil) -> Box? {
        let searched = region ?? CGRect(origin: .zero, size: size)
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min

        for y in Int(searched.minY)..<Int(searched.maxY) {
            for x in Int(searched.minX)..<Int(searched.maxX) {
                guard deviation(fromColour: colour, x: x, y: y) <= Self.tolerance else { continue }
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
}

// MARK: - Against what was drawn

/// A measured distance against a drawn one, to the point.
///
/// One point of slack, and only one: a scan reports the last fully painted pixel
/// of a curved edge, so a control standing exactly where the export draws it
/// measures 28 or 29 rather than 28 alone. The mistakes these suites exist to
/// catch are 34 points wide, which no amount of antialiasing accounts for.
func expect(
    _ measured: Int,
    isTheDrawn drawn: CGFloat,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        abs(CGFloat(measured) - drawn) <= 1,
        "measured \(measured) against a drawn \(drawn)",
        sourceLocation: sourceLocation
    )
}

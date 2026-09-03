import SwiftUI

// MARK: - Check

/// The check the export draws on screen 03, on a completed key-test step:
/// `d="M4 10.5l4 4L16 6"` in the twenty-unit glyph box. It is also the mark a
/// done row of Today's get-started checklist carries.
///
/// It lives in the design layer rather than beside one of its call sites
/// because two screens now draw it — the key test on screen 03, and the
/// get-started checklist that stands in for an empty day on Today — and a mark
/// copied into a second feature is a mark that can be corrected in one place
/// and left wrong in the other.
///
/// The three points are the path's own coordinates, which is why they sit here
/// as numbers rather than in `FuelMetrics`: they describe the shape of a mark,
/// not a distance in the app's layout. `FuelMetrics.Line.Glyph` supplies the
/// box they are authored in and the stroke they are drawn with, and a call site
/// states both — the weight is not folded in here, because a `Shape` has no
/// stroke of its own and pretending otherwise would hide the one value the
/// design does state about this mark.
///
/// Scaled by the frame so the glyph follows its slot instead of assuming the
/// two are the same size. A system checkmark does not stand in for it: a
/// symbol's weight is a design of its own, and a symbol scaled to fill the slot
/// is half again the size of the drawn mark, which spans only x 4→16 and
/// y 6→14.5 of the twenty.
struct FuelCheckGlyph: Shape {

    private static let points: [CGPoint] = [
        CGPoint(x: 4, y: 10.5),
        CGPoint(x: 8, y: 14.5),
        CGPoint(x: 16, y: 6)
    ]

    nonisolated func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / FuelMetrics.Line.Glyph.viewBox
        var path = Path()
        for (position, point) in Self.points.enumerated() {
            let scaled = CGPoint(x: point.x * scale, y: point.y * scale)
            if position == 0 {
                path.move(to: scaled)
            } else {
                path.addLine(to: scaled)
            }
        }
        return path
    }
}

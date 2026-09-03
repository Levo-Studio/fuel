import SwiftUI
import UIKit

// MARK: - Motion

/// The curves and durations, and the one place *Reduce Motion* is handled.
///
/// The export is a static render: it draws seventeen states, not the way one
/// becomes the next, and it carries no `transition`, no `animation` and no
/// `cubic-bezier`. The values below are therefore the only thing in the design
/// layer that the design does not dictate. They live here rather than at a call
/// site so that when the owner does specify motion, there is one file to change
/// and no feature to hunt through.
///
/// `resolve` is the reason this type exists at all. Reduce Motion honoured at a
/// hundred call sites is Reduce Motion forgotten at ninety of them, so no view
/// ever reads the accessibility flag: it asks for a curve and gets back what is
/// appropriate for the device it is running on.
nonisolated enum FuelMotion {

    // MARK: - Reduced behaviour

    /// What a curve becomes when the user has asked for less motion.
    ///
    /// Apple's guidance is that Reduce Motion means *less movement*, not *no
    /// change*: a state that swaps instantly is harder to follow than one that
    /// fades. So most curves keep a short cross-fade, and only the ones whose
    /// whole point is travel across the screen are dropped.
    enum ReducedBehaviour: Sendable {

        /// Replaced by a short linear fade.
        case crossFade

        /// Dropped entirely — the change is applied without animation.
        case none
    }

    // MARK: - Curve

    /// A duration and a cubic bézier, kept as data so `resolve` can decide what
    /// to build from it.
    struct Curve: Equatable, Sendable {

        let duration: TimeInterval
        let controlPoint1: UnitPoint
        let controlPoint2: UnitPoint
        let reducedBehaviour: ReducedBehaviour

        fileprivate var animation: Animation {
            .timingCurve(
                controlPoint1.x,
                controlPoint1.y,
                controlPoint2.x,
                controlPoint2.y,
                duration: duration
            )
        }
    }

    // MARK: - Curves

    /// The default: a control reacting to a tap — a segment moving, a swatch
    /// taking its ring, a chip filling. Fast enough that the finger is still
    /// down when it finishes.
    static let standard = Curve(
        duration: 0.28,
        controlPoint1: UnitPoint(x: 0.2, y: 0),
        controlPoint2: UnitPoint(x: 0, y: 1),
        reducedBehaviour: .crossFade
    )

    /// Slower and softer, for something arriving or leaving: a sheet, the
    /// result screen after an analysis, a group appearing in the day list.
    static let emphasised = Curve(
        duration: 0.45,
        controlPoint1: UnitPoint(x: 0.32, y: 0.72),
        controlPoint2: UnitPoint(x: 0, y: 1),
        reducedBehaviour: .none
    )

    /// A value counting to a new figure — the ring's offset, a macro bar's
    /// fill, the day total after a log. Longer, because the eye is following a
    /// quantity rather than acknowledging a tap.
    static let value = Curve(
        duration: 0.6,
        controlPoint1: UnitPoint(x: 0.25, y: 0.1),
        controlPoint2: UnitPoint(x: 0.25, y: 1),
        reducedBehaviour: .crossFade
    )

    /// The analysis progress bar and the key-test spinner. Linear, because both
    /// stand in for elapsed time and an eased progress bar reads as a stalling
    /// one.
    static let progress = Curve(
        duration: 0.35,
        controlPoint1: UnitPoint(x: 0, y: 0),
        controlPoint2: UnitPoint(x: 1, y: 1),
        reducedBehaviour: .crossFade
    )

    /// The duration a cross-fade gets when a curve is reduced. One value for
    /// all of them: under Reduce Motion the differences between the curves stop
    /// meaning anything, and a fade that varies in length by origin is just
    /// inconsistency.
    static let reducedFadeDuration: TimeInterval = 0.15

    /// Every curve above, so a test can hold the whole set to one rule rather
    /// than to four restated ones.
    static let allCurves: [Curve] = [standard, emphasised, value, progress]

    // MARK: - Paced sequences

    /// How long one of the four analysis steps is held before the next.
    ///
    /// Not a curve, because nothing is being interpolated: the steps are a
    /// sequence of four states, and this is the dwell between them. It lives
    /// here for the same reason the curves do — the export draws the four
    /// analysis frames and says nothing about their timing, which is precisely
    /// the case that sends a missing value to the design layer rather than to
    /// the call site that first needed one.
    ///
    /// The whole walk is four holds, and the last one is cut short the moment
    /// the estimate arrives, so this is a pace rather than a floor on how long
    /// a scan takes.
    static let analysisStepHold: Duration = .milliseconds(700)

    // MARK: - Resolution

    /// Turns a curve into the animation to actually run.
    ///
    /// The `Bool` is passed in rather than read from `UIAccessibility` so that
    /// this stays a pure function and both branches are testable without a
    /// simulator setting. Views get it from the environment through
    /// `fuelAnimation(_:value:)` and never touch the flag themselves.
    static func resolve(_ curve: Curve, reduceMotion: Bool) -> Animation? {
        guard reduceMotion else { return curve.animation }
        switch curve.reducedBehaviour {
        case .crossFade: return .linear(duration: reducedFadeDuration)
        case .none: return nil
        }
    }

    /// The same decision for imperative code that is not inside a `body` and so
    /// has no environment to read. Main-actor because `UIAccessibility` is.
    @MainActor
    static func resolve(_ curve: Curve) -> Animation? {
        resolve(curve, reduceMotion: UIAccessibility.isReduceMotionEnabled)
    }

    /// A curve that runs until something stops it — the key-test spinner is the
    /// only one Fuel draws.
    ///
    /// `resolve` cannot answer this, and that is not an oversight in the caller:
    /// `ReducedBehaviour` describes what replaces a *transition*, and neither
    /// answer fits a loop. `.crossFade` hands back a 0.15s linear curve, and
    /// `.repeatForever` on that spins the ring roughly twice as fast as the
    /// design draws it — the opposite of reducing motion. `.none` returns nil,
    /// which stops the spinner but leaves the row looking pending forever.
    ///
    /// So a repeating curve is its own question with its own answer: run it,
    /// or return nil and let the caller draw the still state. A view must not
    /// improvise this by reading the accessibility flag itself — that is the
    /// rule this function exists to keep true.
    static func resolveRepeating(_ curve: Curve, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return curve.animation.repeatForever(autoreverses: false)
    }
}

// MARK: - Applying a curve

private struct FuelAnimationModifier<Value: Equatable>: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let curve: FuelMotion.Curve
    let value: Value

    func body(content: Content) -> some View {
        content.animation(FuelMotion.resolve(curve, reduceMotion: reduceMotion), value: value)
    }
}

extension View {

    /// Animates a change with one of the curves above, already reduced if the
    /// user asked for that.
    ///
    /// This is the only animation entry point a feature file uses. `.animation`
    /// with a hand-written curve is a design-layer bypass and a Reduce Motion
    /// bug in one line.
    func fuelAnimation<Value: Equatable>(_ curve: FuelMotion.Curve, value: Value) -> some View {
        modifier(FuelAnimationModifier(curve: curve, value: value))
    }
}

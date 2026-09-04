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

    /// Today changing to the day beside it — by a swipe, by an arrow in the
    /// header, or by a jump from the date picker.
    ///
    /// **The same duration and the same bézier as `emphasised`**, taken from it
    /// rather than restated, because a day arriving *is* the thing that curve
    /// describes: a screenful of content coming in from one side while the
    /// previous one leaves at the other. Nothing about the travel differs, so
    /// nothing about the timing does.
    ///
    /// What differs is the one thing a curve carries beyond its shape. Reduce
    /// Motion drops `emphasised` entirely, which is right for a sheet: the
    /// screen underneath is still there and the change is legible without it.
    /// A day change replaces everything under the header at once, and a cut
    /// with no cue at all is the case Apple's guidance names — a state that
    /// swaps instantly is harder to follow than one that fades. So this one
    /// cross-fades where `emphasised` is dropped, and `resolveDayTransition`
    /// below is what the fade is applied to.
    static let dayChange = Curve(
        duration: emphasised.duration,
        controlPoint1: emphasised.controlPoint1,
        controlPoint2: emphasised.controlPoint2,
        reducedBehaviour: .crossFade
    )

    /// The duration a cross-fade gets when a curve is reduced. One value for
    /// all of them: under Reduce Motion the differences between the curves stop
    /// meaning anything, and a fade that varies in length by origin is just
    /// inconsistency.
    static let reducedFadeDuration: TimeInterval = 0.15

    /// Every curve above, so a test can hold the whole set to one rule rather
    /// than to four restated ones.
    static let allCurves: [Curve] = [standard, emphasised, value, progress, dayChange]

    // MARK: - Press feedback

    /// How much a control shrinks under a finger, and the spring it snaps back
    /// with when the finger lifts.
    ///
    /// **Undrawn, like the curves above — more so.** The export renders states
    /// and says nothing about the travel between them, but at least draws every
    /// state on both ends of that travel. It draws no pressed frame for any
    /// control at all: there is no fifteenth swatch, no depressed pill, nothing
    /// to read a value off. `scale` and the spring constants below are chosen
    /// rather than found, against one brief — this is a tracker opened perhaps
    /// ten times a day, not a game, so the finger should feel answered without
    /// the interface feeling loose. A shrink small enough that the drawn
    /// geometry is never mistaken for having moved permanently, sprung back
    /// briskly enough that letting go reads as release rather than as a bounce.
    enum Press {

        /// The scale a pressed control is drawn at. Close enough to 1 that
        /// nothing drawn appears to change size at rest — only while a finger
        /// is actually down.
        static let scale: CGFloat = 0.96

        /// How quickly the spring answers a change — the down-stroke, and the
        /// release both use it, so a control neither lags the finger nor
        /// overshoots on the way back.
        static let springResponse: TimeInterval = 0.22

        /// How much the spring's oscillation is damped. Comfortably short of 1
        /// so the release still reads as a spring and not a hard stop, and far
        /// enough from a wobble that it never overshoots past the resting size.
        static let springDamping: Double = 0.7
    }

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

    /// How long one example is held in the empty text field before the next.
    ///
    /// The second dwell in the app and the same kind of value as the one above
    /// — a sequence of states rather than an interpolation — so it sits beside
    /// it rather than in the feature that first needed one.
    ///
    /// **No drawn screen specifies it.** The export draws screen 12's field
    /// with a sentence already in it and nothing rotating, so this is chosen
    /// against what the example is for: it has to be readable at a glance and
    /// gone before it becomes furniture. Two and a half seconds is long enough
    /// to read a short line without hurrying and to notice it change, and far
    /// longer than the analysis dwell, which paces work rather than reading.
    static let placeholderExampleHold: Duration = .milliseconds(2500)

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

    /// How a day change moves, kept as data for the reason `Curve` is: so the
    /// decision can be made by a pure function and tested, and only then turned
    /// into something SwiftUI can apply.
    ///
    /// `resolve` cannot answer this, for the reason `resolveRepeating` cannot
    /// answer its own question. A `Curve` says how long and how eased; this
    /// says *what moves*, which is the other half of the same decision. Leaving
    /// it at the call site would put a direction — and the Reduce Motion branch
    /// that replaces it — in a feature file.
    enum DayTravel: Equatable, Sendable {

        /// The day arrives from one edge while the one it replaces leaves at
        /// the other. `isBackward` is a move to an *earlier* day.
        case sideways(isBackward: Bool)

        /// Reduce Motion: the travel is dropped and the two days cross-fade in
        /// place, which is `dayChange`'s `.crossFade` applied to the thing that
        /// would otherwise move.
        case fade

        /// Backwards, the day arrives from the leading edge — the direction a
        /// page turns back — and forwards is that reversed.
        ///
        /// Combined with a fade rather than a bare slide: the day list has no
        /// opaque card behind it, so two of them sliding across each other
        /// would overlap mid-travel and read as one screen of doubled text.
        fileprivate var transition: AnyTransition {
            switch self {
            case .fade:
                return .opacity
            case .sideways(let isBackward):
                return .asymmetric(
                    insertion: .move(edge: isBackward ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: isBackward ? .trailing : .leading).combined(with: .opacity)
                )
            }
        }
    }

    /// Which way a day change travels, and whether it travels at all.
    ///
    /// **The direction is the whole point of it existing.** Three controls
    /// change the day: a horizontal drag, an arrow in the header, and a jump
    /// from the picker. They are three gestures and one movement, and they read
    /// as one only if a move to an earlier day travels the same way whichever
    /// of them made it.
    static func resolveDayTravel(isBackward: Bool, reduceMotion: Bool) -> DayTravel {
        reduceMotion ? .fade : .sideways(isBackward: isBackward)
    }

    /// Whether a sequence that advances on its own should advance at all, and
    /// how long it holds each state when it does.
    ///
    /// The same question `resolveRepeating` answers, for the case where nothing
    /// is being interpolated: text that swaps itself on a timer is not a
    /// transition with a curve, it is a loop with a dwell. `ReducedBehaviour`
    /// has no answer that fits — a cross-fade would keep the rotation and only
    /// soften each swap, which is not less motion, it is the same motion
    /// blurred.
    ///
    /// So `nil` means **do not advance**, and the caller shows the state it is
    /// already on. Text that rewrites itself while someone is reading it is
    /// close to the centre of what Reduce Motion is asked for, and a rotating
    /// example loses nothing by standing still: one example teaches the same
    /// thing as four.
    static func resolvePacing(_ hold: Duration, reduceMotion: Bool) -> Duration? {
        reduceMotion ? nil : hold
    }

    /// What a control is drawn at while a finger is down on it.
    ///
    /// `1` under Reduce Motion rather than `Press.scale` held without a spring:
    /// a size change applied with no animation is not a smaller motion, it is
    /// the same motion with the easing removed, and a control that silently
    /// jumps a size and back is closer to a glitch than to feedback. Dropping
    /// it is the `.none` branch `resolve` already has for travel — this is
    /// exactly that kind of motion and not a state transition, so there is
    /// nothing to keep by softening it.
    static func resolvePressScale(isPressed: Bool, reduceMotion: Bool) -> CGFloat {
        guard isPressed, !reduceMotion else { return 1 }
        return Press.scale
    }

    /// The spring behind that scale, or nothing to animate at all once it is
    /// suppressed.
    static func resolvePress(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .spring(response: Press.springResponse, dampingFraction: Press.springDamping)
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

// MARK: - Travelling between days

/// Applies the day transition, with the accessibility flag read here rather
/// than at the call site — the same reason `FuelAnimationModifier` exists.
private struct FuelDayTransitionModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isBackward: Bool

    func body(content: Content) -> some View {
        content.transition(
            FuelMotion.resolveDayTravel(isBackward: isBackward, reduceMotion: reduceMotion).transition
        )
    }
}

// MARK: - Pacing a sequence

/// Advances a sequence on a timer for as long as the view is on screen — and
/// not at all when the user has asked for less motion.
///
/// It is `FuelAnimationModifier`'s counterpart for the case with no curve in
/// it, and it exists for the same reason: the accessibility flag is read here,
/// once, rather than at whichever call site happens to want a rotation. A
/// feature file that read it itself would be one `if` away from a rotation that
/// keeps running under Reduce Motion.
private struct FuelPacingModifier: ViewModifier {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let hold: Duration
    let isActive: Bool
    let advance: () -> Void

    /// What the loop is keyed on. Both inputs restart it: switching Reduce
    /// Motion on has to stop a rotation that is already running, and a sequence
    /// that has become irrelevant — a field with something in it — has to stop
    /// waking up to advance something nobody can see.
    private struct Key: Equatable {

        let isActive: Bool
        let reduceMotion: Bool
    }

    func body(content: Content) -> some View {
        content.task(id: Key(isActive: isActive, reduceMotion: reduceMotion)) {
            guard
                isActive,
                let hold = FuelMotion.resolvePacing(hold, reduceMotion: reduceMotion)
            else {
                return
            }
            // The first state is already showing, so the wait comes before the
            // advance rather than after it.
            while !Task.isCancelled {
                try? await Task.sleep(for: hold)
                guard !Task.isCancelled else { return }
                advance()
            }
        }
    }
}

extension View {

    /// Advances something on a dwell from the design layer, honouring Reduce
    /// Motion without the call site knowing about it.
    ///
    /// `isActive` is for a sequence that has stopped mattering rather than
    /// stopped moving — the rotation behind a field the user has typed into.
    func fuelPacing(
        _ hold: Duration,
        isActive: Bool = true,
        advance: @escaping () -> Void
    ) -> some View {
        modifier(FuelPacingModifier(hold: hold, isActive: isActive, advance: advance))
    }

    /// Travels to the day beside this one, in the direction the move was made.
    ///
    /// The only transition entry point a feature file uses. `.transition` with
    /// a hand-written edge is a design-layer bypass and a Reduce Motion bug in
    /// one line — the same two things `fuelAnimation` prevents.
    func fuelDayTransition(isBackward: Bool) -> some View {
        modifier(FuelDayTransitionModifier(isBackward: isBackward))
    }

    /// Animates a change with one of the curves above, already reduced if the
    /// user asked for that.
    ///
    /// This is the only animation entry point a feature file uses. `.animation`
    /// with a hand-written curve is a design-layer bypass and a Reduce Motion
    /// bug in one line.
    func fuelAnimation<Value: Equatable>(_ curve: FuelMotion.Curve, value: Value) -> some View {
        modifier(FuelAnimationModifier(curve: curve, value: value))
    }

    /// Every scrolling surface in Fuel, and the one decision they share: a drag
    /// is always answered, even where the content already fits.
    ///
    /// **Owner's ruling, not a drawn value.** The export is a set of still
    /// frames and says nothing about what a finger does to them. Left to
    /// `.basedOnSize` — which is what each of these four surfaces used to carry
    /// — a short screen is inert under a drag, and Fuel has several: a Today
    /// with two entries, a result with three items, Recent on a fresh install,
    /// Settings on a short phone. Nothing moves, and the screen reads as frozen
    /// rather than as full. A bounce answers the finger and costs no drawn
    /// geometry and no visible affordance.
    ///
    /// It lives here, beside the curves, for the reason Reduce Motion does: at
    /// four call sites a rule is remembered at three of them, and the fourth is
    /// the one the owner finds. A `ScrollView` in this app takes this modifier
    /// and does not write a bounce behaviour of its own.
    func fuelScrolling() -> some View {
        scrollBounceBehavior(.always)
    }
}

// MARK: - Press feedback

/// Springs a control to `FuelMotion.Press.scale` while a finger is down on it,
/// and back when it lifts.
///
/// One button style rather than a `.scaleEffect` at each call site, for the
/// reason `fuelAnimation` exists: Reduce Motion honoured at every button is
/// Reduce Motion forgotten at most of them. `ButtonStyle` rather than a plain
/// `ViewModifier` because `isPressed` is the state — SwiftUI already tracks the
/// touch down and the touch up, and a gesture recogniser added beside it would
/// be a second, competing answer to "is a finger on this".
///
/// Applied as `.buttonStyle(FuelPressButtonStyle())`, not through a `.plain`-
/// style static member: SwiftUI's own `.buttonStyle(_:)` is overloaded on both
/// `ButtonStyle` and `PrimitiveButtonStyle`, and at a couple of call sites with
/// a large label view the compiler resolved a `where Self ==` static member
/// against the wrong one of the two and failed to find it. A direct
/// initialiser leaves nothing to resolve.
struct FuelPressButtonStyle: ButtonStyle {

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                FuelMotion.resolvePressScale(
                    isPressed: configuration.isPressed,
                    reduceMotion: reduceMotion
                )
            )
            .animation(
                FuelMotion.resolvePress(reduceMotion: reduceMotion),
                value: configuration.isPressed
            )
    }
}


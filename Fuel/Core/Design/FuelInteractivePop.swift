import SwiftUI
import UIKit

// MARK: - Interactive pop

/// What makes a horizontal drag anywhere on a pushed screen go back, in two
/// parts: a hint to the system's own back gestures, and a gesture of Fuel's own
/// underneath it that does not depend on the hint being taken.
///
/// **The hint came first and is kept, because when it works it is the better
/// answer.** `tie(from:)` gives `UINavigationController`'s two back gestures
/// the first claim on the drag, and what they do with it is the transition iOS
/// has always had — the page follows the finger off to the right, the screen
/// underneath comes forward, and letting go part-way completes or springs back.
/// That is the animation the owner asked for by name, and nothing hand-built
/// reproduces it.
///
/// **What it is not is something Fuel can stand behind.** Measured on the real
/// screen, hosted on a window, with the meal pushed: both pops are enabled,
/// both delegates approve them beginning, nothing covers the leading edge — a
/// hit test at x = 5 lands in the breakdown's scroll view, whose ancestors
/// include the view both pops are attached to — and the breakdown's pan reports
/// `must-fail = { edgeSwipe, contentSwipe }`, which is exactly the requirement
/// `tie(from:)` sets out to state. Popping that navigation controller by hand
/// shrinks the stack and leaves the shell's model holding no meal, so the
/// transition and the model hand-off both work. Every part of the theory is in
/// place, and the gesture was still reported dead three times.
///
/// The reason that can happen and cannot be chased is that a failure
/// requirement is a *hint into an arbitration Fuel does not run*. Whether
/// either pop begins is decided inside `_UIParallaxTransitionPanGestureRecognizer`
/// and `_UINavigationInteractiveTransition` — private objects Fuel cannot see,
/// drive, or assert against. Everything provable about the hint is structural,
/// which is precisely why three rounds of structural evidence kept saying the
/// gesture was fixed while the screen said otherwise.
///
/// **So the screen carries a gesture of Fuel's as well**, and the race stops
/// mattering because both of its outcomes are now a pop. `arm(from:)` puts a
/// pan on the pushed screen whose delegate, whose recognition rule and whose
/// action are all Fuel's, and which pops the navigation controller itself. It
/// deliberately does **not** wait for either system pop: waiting is what put
/// the outcome back in UIKit's hands, and an edge pan stays undecided for the
/// length of a drag that starts at the edge, so waiting for it would kill this
/// exactly where the gesture is reported dead. At the leading edge the system's
/// pan is quicker off the mark and normally wins, which is the ordering worth
/// having — the parallax when it is there, a pop either way.
///
/// `FuelBackSwipe` next to this file is the third thing: a hand-built drag for
/// screens the system offers no gesture for at all, which is a cover rather
/// than a push. The two share their geometry and nothing else.
enum FuelInteractivePop {

    // MARK: - Tying the two together

    /// Makes every scroll view on this view's screen wait for both of the
    /// navigation controller's back gestures, once.
    ///
    /// **`require(toFail:)` and not the delegate methods UIKit prefers, because
    /// the delegate methods are not Fuel's to answer.** That documentation
    /// steers a requirement which is set up lazily or across view hierarchies —
    /// both true here — to `gestureRecognizer(_:shouldRequireFailureOf:)`, which
    /// is asked once per attempt to recognise and so can never go stale. It is
    /// the better mechanism and Fuel cannot reach it: the two delegates it would
    /// have to stand in for are the scroll view, which is SwiftUI's own and
    /// relies on that delegate for how it scrolls, and the back gestures' own,
    /// which is the navigation controller's interactive transition — the object
    /// that drives the animation, and one shared with Today rather than
    /// belonging to this screen. Replacing either would put Fuel in the middle
    /// of a conversation it has no part in, and the second would reach a screen
    /// this has no business touching.
    ///
    /// So the requirement is stated directly, and what the delegate form would
    /// have given for free — being asked again rather than remembered — is
    /// bought back by `keepTied(from:)`, which restates it. `require(toFail:)`
    /// is idempotent, so restating costs one walk of the screen's views and
    /// leaves one entry however many times it runs.
    ///
    /// **Both back gestures, and the second one is the whole point.** iOS 26
    /// publishes a second pop recogniser beside the edge pan:
    /// `interactiveContentPopGestureRecognizer`, which the SDK header describes
    /// as recognising *"on the entire content area of the navigation controller
    /// in cases that are not covered by the interactive pop gesture
    /// recognizer"*. Tying only the edge pan left that one still swallowed by
    /// the list, so the back swipe worked in the leading strip and nowhere else
    /// — and the owner, drawing an arrow straight across the empty space under
    /// the breakdown, has said it must be there on the whole screen. The two
    /// requirements together are what make it so: the edge one for a drag that
    /// starts in the strip, the content one for a drag that starts in the
    /// middle or in that empty space.
    ///
    /// **The second requirement is not free, and this is the screen that can
    /// afford it.** Unlike the edge pan, the content pop has not already failed
    /// when a touch lands away from the edge, so a vertical drag waits for it
    /// to give up before the list moves. What it waits for is UIKit deciding
    /// the pan is not horizontal, which is settled from the first few points of
    /// movement rather than after a timeout — and the meal screen is short,
    /// frequently one or two breakdown rows above a lot of nothing, so the list
    /// this delays is a list with barely anywhere to go. That is a judgement
    /// about this screen, not a general one, which is the other reason the
    /// modifier is applied here and nowhere else.
    ///
    /// **It reaches one screen and stops.** The search starts at the view
    /// controller this view belongs to, which on a navigation stack is the
    /// pushed screen and nothing else. Today is a different controller, so its
    /// day swipe is untouched — and on the root neither pop can begin anyway,
    /// there being nothing to pop. A sheet is its own presentation with
    /// its own controller, so what is inside one is out of reach here.
    static func tie(from view: UIView) {
        guard
            let screen = view.fuelOwningViewController,
            let navigation = screen.navigationController,
            let content = screen.viewIfLoaded
        else {
            return
        }

        // Whichever of the two the controller is holding, rather than both
        // demanded: a navigation controller is free to publish neither, and a
        // screen that got one requirement is better off than one that got none
        // because the other was missing.
        let pops = [
            navigation.interactivePopGestureRecognizer,
            navigation.interactiveContentPopGestureRecognizer,
        ].compactMap { $0 }

        for scroll in scrollViews(in: content) {
            for pop in pops {
                scroll.panGestureRecognizer.require(toFail: pop)
            }
        }
    }

    /// Ties the screen now, and arranges for it to be tied again on every touch
    /// that lands on it.
    ///
    /// **The repetition is the point, and finding a moment that actually
    /// arrives took two tries.** A requirement is made against the scroll view
    /// that exists when it is stated, and SwiftUI is free to build a new one
    /// under a screen that never left the stack — `MealResultView` puts a
    /// branch directly above its list, so a screen whose footer became
    /// conditional would get a new scroll view and the gesture would go quiet
    /// again, silently. The obvious hooks do not cover that: a view with no size
    /// and no subviews is never laid out, so `layoutSubviews` never runs a
    /// second time, and a representable with no stored properties is never
    /// updated, so `updateUIView` runs once at attach. Both were measured
    /// firing zero times on the real screen rather than assumed to work.
    ///
    /// A touch is the moment that does arrive, and it is the right one: it is
    /// the event the requirement exists to govern, and it lands before the race
    /// it settles, since a pan is decided when the finger moves rather than when
    /// it touches down. Whatever scroll view is on the screen at that instant is
    /// the one tied.
    static func keepTied(from view: UIView) {
        guard
            let screen = view.fuelOwningViewController,
            let content = screen.viewIfLoaded
        else {
            return
        }

        tie(from: content)

        let isWatched = content.gestureRecognizers?.contains { $0 is FuelInteractivePopWatch } ?? false
        guard isWatched == false else { return }
        content.addGestureRecognizer(
            FuelInteractivePopWatch { [weak content] in
                guard let content else { return }
                tie(from: content)
            }
        )
    }

    // MARK: - The gesture Fuel owns

    /// Puts Fuel's own back gesture on this view's screen, once.
    ///
    /// **On the screen's own view, which is what scopes it.** The pushed
    /// controller's view is torn down with the screen, so the gesture goes with
    /// it: Today is a different controller and never carries one, which is what
    /// keeps this off `FuelDaySwipe` — and a sheet is a presentation of its own,
    /// out of reach for the same reason the tie above is.
    ///
    /// Idempotent, because the carrier calls it from more than one moment and a
    /// screen with two of these would pop twice.
    static func arm(from view: UIView) {
        guard
            let screen = view.fuelOwningViewController,
            let content = screen.viewIfLoaded,
            (content.gestureRecognizers ?? []).contains(where: { $0 is FuelBackPopGesture }) == false
        else {
            return
        }
        content.addGestureRecognizer(FuelBackPopGesture())
    }

    /// Whether a back gesture may begin on this view's screen at all.
    ///
    /// Three conditions, and each is a way the gesture would otherwise be wrong
    /// rather than merely useless: there has to be something under this screen
    /// to go back to, this has to be the screen on top of the stack — a drag on
    /// a screen mid-transition must not pop the one above it — and nothing may
    /// be presented over it, which is what holds the gesture off while the
    /// conversation sheet is up.
    static func canPop(from view: UIView) -> Bool {
        guard
            let screen = view.fuelOwningViewController,
            let navigation = screen.navigationController,
            navigation.viewControllers.count > 1,
            navigation.viewControllers.last === screen,
            screen.presentedViewController == nil
        else {
            return false
        }
        return true
    }

    /// Pops the screen this view is on when the drag that just ended meant
    /// *back*, and answers whether it did.
    ///
    /// **`popViewController` and not a write to the shell's path**, which is the
    /// hand-off worth being explicit about. SwiftUI's `NavigationStack` watches
    /// the navigation controller it built and writes its path binding when the
    /// stack shrinks, so a pop made here arrives at `RootShell.mealDetailPath`
    /// as the system's own pop would — and therefore at the discard
    /// confirmation standing in front of it. Measured, not assumed: popping the
    /// hosted controller by hand leaves the shell's model holding no meal, and
    /// leaves it holding the meal when there are edits to ask about.
    ///
    /// `animated: true` is the platform's push-pop, which honours *Reduce
    /// Motion* on its own account — the same reason `RootShell` hands the stack
    /// no curve of Fuel's for the push and the pop themselves.
    @discardableResult
    static func popIfDragMeansBack(translation: CGSize, from view: UIView) -> Bool {
        // Asked again rather than trusted from the moment the drag began: a
        // sheet can arrive over the screen while a finger is still down.
        guard
            canPop(from: view),
            FuelBackSwipe.isLeaving(translation: translation),
            let navigation = view.fuelOwningViewController?.navigationController
        else {
            return false
        }
        navigation.popViewController(animated: true)
        return true
    }

    /// Every scroll view in this subtree, the nested ones included.
    ///
    /// Not "the first one": the meal screen has one list today, and a screen
    /// that grew a second would otherwise get the gesture on half of itself.
    static func scrollViews(in view: UIView) -> [UIScrollView] {
        var found: [UIScrollView] = []
        if let scroll = view as? UIScrollView {
            found.append(scroll)
        }
        for subview in view.subviews {
            found.append(contentsOf: scrollViews(in: subview))
        }
        return found
    }
}

// MARK: - Noticing a touch

/// A recogniser that recognises nothing, and exists only to be told when a
/// finger arrives.
///
/// It fails itself in the same breath as it is offered the touch, which is what
/// makes it safe to put on a screen this file otherwise argues should not carry
/// a second recogniser: a recogniser in `failed` prevents nothing, delays
/// nothing, and satisfies anything that might be waiting on it immediately.
/// Touches are neither delayed nor cancelled on the way to the views underneath,
/// so the list scrolls and the buttons press exactly as they did.
final class FuelInteractivePopWatch: UIGestureRecognizer {

    private let onTouch: () -> Void

    init(onTouch: @escaping () -> Void) {
        self.onTouch = onTouch
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        state = .failed
        onTouch()
    }
}

// MARK: - Fuel's own back gesture

/// The pan Fuel puts on a pushed screen so that a horizontal drag across it
/// goes back whether or not the system's pops answered first.
///
/// It is its own delegate's and its own target's owner rather than either of
/// them: `delegate` is weak and an action target is not something to leave to
/// whoever happens to be holding the screen, so the one object both roles need
/// is stored here and lives exactly as long as the recogniser does.
final class FuelBackPopGesture: UIPanGestureRecognizer {

    private let handler = FuelBackPopHandler()

    init() {
        super.init(target: nil, action: nil)
        addTarget(handler, action: #selector(FuelBackPopHandler.handle(_:)))
        delegate = handler
        // The list underneath keeps its taps and its scroll until this actually
        // begins, and beginning is already gated on a drag that is going
        // sideways and going right.
        cancelsTouchesInView = true
        delaysTouchesBegan = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FuelBackPopGesture is never loaded from a nib.")
    }
}

/// What decides whether the pan begins, what it takes precedence over, and what
/// happens when it ends.
///
/// Split from the recogniser so that all three answers are plain functions over
/// a view and a translation, which is what lets a test drive a whole drag —
/// down to the navigation stack shrinking and the shell releasing the meal —
/// without a simulator having to synthesise a touch.
final class FuelBackPopHandler: NSObject, UIGestureRecognizerDelegate {

    @objc
    func handle(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, let view = gesture.view else { return }
        let travelled = gesture.translation(in: view)
        FuelInteractivePop.popIfDragMeansBack(
            // UIKit reports a drag as a point and Fuel measures one as a size,
            // which is what `DragGesture` hands `FuelBackSwipe` on the covered
            // screens. Converted here, at the one place the two meet, so the
            // rule itself is stated once for both.
            translation: CGSize(width: travelled.x, height: travelled.y),
            from: view
        )
    }

    // MARK: - Arbitration

    /// **The half of the drag that has to be decided before it has finished.**
    /// A pan is asked this the moment it clears its slop, so the translation
    /// here is a few points rather than the sixty a finished back swipe needs —
    /// the question is only which way the finger is going, and how far it went
    /// is asked again at the end.
    ///
    /// Rightward and squarely sideways, so a vertical scroll is never taken
    /// from the list underneath and a drag to the left is not a way out of a
    /// screen the user is arriving at.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard
            let pan = gesture as? UIPanGestureRecognizer,
            let view = pan.view,
            FuelInteractivePop.canPop(from: view)
        else {
            return false
        }
        let travelled = pan.translation(in: view)
        return FuelBackSwipe.isLeavingDirection(
            translation: CGSize(width: travelled.x, height: travelled.y)
        )
    }

    /// **This is the mechanism, and it is the one the previous rounds could not
    /// reach.** UIKit asks both recognisers of a pair about a failure
    /// requirement and takes the union, so "the list waits for the back
    /// gesture" can be stated from either side — and Fuel owns this side. It
    /// never has to stand in for SwiftUI's scroll-view delegate, which is the
    /// objection that sent the earlier fix to `require(toFail:)` instead.
    ///
    /// What that buys is the thing a stated requirement cannot have: this is
    /// asked afresh on every attempt to recognise, against whatever list is on
    /// the screen at that instant. A requirement recorded once goes stale the
    /// moment SwiftUI rebuilds the list under a screen that never left the
    /// stack, silently, with nothing to notice it.
    ///
    /// Scoped to the screen this is attached to, for the reason the tie is: a
    /// scroll view somewhere else in the app is not this screen's to delay.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldBeRequiredToFailBy other: UIGestureRecognizer
    ) -> Bool {
        guard
            let view = gesture.view,
            let scroll = other.view as? UIScrollView,
            // Its pan and nothing else it carries. A scroll view's delayed-touch
            // and knob recognisers are how it delivers taps and how it drags its
            // indicator, and making either wait would take something from the
            // list that this has no quarrel with.
            other === scroll.panGestureRecognizer,
            scroll.isDescendant(of: view)
        else {
            return false
        }
        return true
    }

    /// Nothing runs beside this. A drag that has been read as *back* is not
    /// also a scroll, and the screen is on its way out either way.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        false
    }
}

// MARK: - The view that carries it

/// A view with no size, no colour and no touches, whose only job is to be
/// somewhere inside the screen so the tie above has a place to start from.
///
/// It is a `UIView` and not a piece of SwiftUI because the two recognisers being
/// introduced to each other are UIKit's, and SwiftUI exposes neither of them.
/// Both moments below are the same moment — the screen arriving — rather than
/// two chances at it; what happens after that is the watch's, not theirs.
private final class FuelInteractivePopCarrier: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FuelInteractivePopCarrier is never loaded from a nib.")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

    /// Nothing to attach while the screen is off the window: there is no
    /// navigation controller to reach and no scroll view laid out to reach it
    /// from.
    func attach() {
        guard window != nil else { return }
        FuelInteractivePop.keepTied(from: self)
        FuelInteractivePop.arm(from: self)
    }
}

private struct FuelInteractivePopCarrierView: UIViewRepresentable {

    func makeUIView(context: Context) -> UIView {
        FuelInteractivePopCarrier()
    }

    /// Runs once, at attach, and that is all it is relied on for — a
    /// representable carrying no value is never handed a second update. It is
    /// kept because attaching is exactly when there is something to do, and
    /// doing it twice costs nothing.
    func updateUIView(_ view: UIView, context: Context) {
        (view as? FuelInteractivePopCarrier)?.attach()
    }
}

// MARK: - Applying it

private struct FuelInteractivePopModifier: ViewModifier {

    func body(content: Content) -> some View {
        content.background {
            FuelInteractivePopCarrierView()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}

extension View {

    /// Makes a horizontal drag anywhere on this screen go back.
    ///
    /// Two mechanisms, and the file above says at length why it takes two: the
    /// system's own back gestures are given the first claim on the drag,
    /// because what they do with it is the transition that follows the finger,
    /// and a gesture of Fuel's own sits underneath them so the screen goes back
    /// whether they took the claim or not.
    ///
    /// **Apply it to a screen that is pushed on a navigation stack.** On a
    /// screen presented some other way there is nothing to pop and this does
    /// nothing at all — which is the honest outcome, not a silent failure: a
    /// covered screen has no stack to shrink, and `fuelBackSwipe` is what those
    /// screens use instead.
    ///
    /// **And apply it deliberately, screen by screen.** Both halves put every
    /// vertical scroll on the screen behind a horizontal gesture that has to
    /// fail first, which `tie(from:)` argues is a fair price on a screen this
    /// short and does not argue anywhere else.
    func fuelInteractivePop() -> some View {
        modifier(FuelInteractivePopModifier())
    }
}

// MARK: - Finding the screen

private extension UIView {

    /// The view controller this view is drawn inside.
    ///
    /// Walked up the responder chain rather than taken from a parent reference,
    /// because a SwiftUI view has no parent reference to take: the chain is the
    /// only thing that crosses from a hosted view to the controller holding it.
    var fuelOwningViewController: UIViewController? {
        var responder: UIResponder? = next
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}

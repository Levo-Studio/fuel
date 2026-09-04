import SwiftUI
import UIKit

// MARK: - Interactive pop

/// Gives the navigation controller's own back gesture the first claim on a drag
/// that begins at the leading edge of a pushed screen.
///
/// **This draws nothing and is not a gesture of Fuel's.** It restores the one
/// iOS has always had — the page follows the finger off to the right, the screen
/// underneath comes forward, and letting go part-way completes or springs back
/// — which is the animation the owner asked for by name. `FuelBackSwipe` next to
/// this file is the other thing: a hand-built drag that dismisses a screen the
/// system offers no gesture for, and it is deliberately *not* what the pushed
/// meal screen uses.
///
/// **Why anything is needed at all.** The system gesture is not disabled here —
/// measured on the hosted screen, `interactivePopGestureRecognizer` is enabled,
/// its delegate approves it beginning, and the navigation controller installs no
/// custom animator that could swallow the transition. What it does not have is
/// any relationship with the recogniser it has to share the screen with. The
/// meal screen is a scroll view from edge to edge, and the same measurement says
/// the two are strangers: the scroll view answers neither
/// `gestureRecognizer(_:shouldRequireFailureOf:)` nor
/// `gestureRecognizer(_:shouldBeRequiredToFailBy:)` about the edge pan, and each
/// recogniser reports it can prevent the other. Two recognisers that can each
/// prevent the other and have no failure requirement between them are settled by
/// whichever recognises first — and a scroll view claims a touch as soon as it
/// moves. So the drag becomes a scroll that goes nowhere, on a list that has
/// nowhere sideways to go, and the screen stays.
///
/// The tie below is the remedy `UINavigationController`'s own documentation
/// describes for exactly this: *"Use this property to retrieve the gesture
/// recognizer and tie it to the behavior of other gesture recognizers in your
/// user interface."* It costs nothing away from the edge, because a screen-edge
/// pan fails the moment a touch begins outside its strip, and a requirement on a
/// recogniser that has already failed delays nothing.
enum FuelInteractivePop {

    // MARK: - Tying the two together

    /// Makes every scroll view on this view's screen wait for the navigation
    /// controller's edge pan, once.
    ///
    /// **`require(toFail:)` and not the delegate methods UIKit prefers, because
    /// the delegate methods are not Fuel's to answer.** That documentation
    /// steers a requirement which is set up lazily or across view hierarchies —
    /// both true here — to `gestureRecognizer(_:shouldRequireFailureOf:)`, which
    /// is asked once per attempt to recognise and so can never go stale. It is
    /// the better mechanism and Fuel cannot reach it: the two delegates it would
    /// have to stand in for are the scroll view, which is SwiftUI's own and
    /// relies on that delegate for how it scrolls, and the edge pan's, which is
    /// the navigation controller's interactive transition — the object that
    /// drives the animation, and one shared with Today rather than belonging to
    /// this screen. Replacing either would put Fuel in the middle of a
    /// conversation it has no part in, and the second would reach a screen this
    /// has no business touching.
    ///
    /// So the requirement is stated directly, and what the delegate form would
    /// have given for free — being asked again rather than remembered — is
    /// bought back by `keepTied(from:)`, which restates it. `require(toFail:)`
    /// is idempotent, so restating costs one walk of the screen's views and
    /// leaves one entry however many times it runs.
    ///
    /// **Only the edge pan, never `interactiveContentPopGestureRecognizer`.**
    /// iOS 26 added a second pop gesture that reads a horizontal pan anywhere in
    /// the content, and its documentation says it exists to have failure
    /// requirements set up with it — so tying it here would be its sanctioned
    /// use, not a misuse. It is still not what this screen wants: that pan is
    /// not confined to a strip, so every vertical scroll on the screen would
    /// have to wait for it to fail rather than only a drag that starts at the
    /// edge, and UIKit already has the content pan wait for the edge pan.
    /// **The consequence is worth naming rather than leaving to be found: on
    /// this screen the mid-content back swipe iOS 26 offers stays swallowed by
    /// the list, and only the edge one works.** That is the trade the bug was
    /// reported as — a swipe from the edge — and widening it is a question for
    /// the owner rather than something to take here.
    ///
    /// **It reaches one screen and stops.** The search starts at the view
    /// controller this view belongs to, which on a navigation stack is the
    /// pushed screen and nothing else. Today is a different controller, so its
    /// day swipe is untouched — and on the root the edge pan cannot begin
    /// anyway, there being nothing to pop. A sheet is its own presentation with
    /// its own controller, so what is inside one is out of reach here.
    static func tie(from view: UIView) {
        guard
            let screen = view.fuelOwningViewController,
            let navigation = screen.navigationController,
            let edge = navigation.interactivePopGestureRecognizer,
            let content = screen.viewIfLoaded
        else {
            return
        }

        for scroll in scrollViews(in: content) {
            scroll.panGestureRecognizer.require(toFail: edge)
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
        keepTied()
    }

    /// Nothing to tie while the screen is off the window: there is no navigation
    /// controller to reach and no scroll view laid out to reach it from.
    func keepTied() {
        guard window != nil else { return }
        FuelInteractivePop.keepTied(from: self)
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
        (view as? FuelInteractivePopCarrier)?.keepTied()
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

    /// Lets the system's interactive pop win a drag that starts at the leading
    /// edge of this screen, ahead of any scroll view on it.
    ///
    /// **Apply it to a screen that is pushed on a navigation stack.** On a
    /// screen presented some other way there is nothing to pop and this does
    /// nothing at all — which is the honest outcome, not a silent failure: a
    /// covered screen has no system gesture to give priority to, and
    /// `fuelBackSwipe` is what those screens use instead.
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

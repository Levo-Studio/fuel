import CoreHaptics
import UIKit

// MARK: - Haptics

/// The four things Fuel says through the Taptic Engine, and the one place the
/// question "should this device feel anything at all" is asked.
///
/// **Nothing here is drawn, and nothing here could be.** A haptic has no
/// geometry, no colour and no duration a 390×844 render can carry, so this
/// whole type stands where `FuelMotion`'s curves stand: outside what the export
/// dictates, in the design layer rather than at a call site, so that when the
/// owner does have an opinion there is one file to change.
///
/// **The event list is short on purpose.** Fuel is opened ten times a day, and
/// a tracker that buzzes at every tap is a tracker whose haptics get switched
/// off wholesale — at which point the two that matter go with them. So there is
/// no feedback for opening a screen, for typing, for scrolling, or for a tap
/// whose result is already visible under the finger. What is left is the four
/// moments where the interface knows something the eye does not yet:
///
/// - a selection stepping to the next of a small set of values, where the click
///   is what makes a stepper read as a stepper;
/// - a destructive action going through, which is the one place a confirmation
///   deserves a heavier answer than the screen changing;
/// - a scan that succeeded, and one that did not — the two outcomes a user
///   waits several seconds for and routinely looks away from.
///
/// `resolve` is the reason this is a type and not four call sites, and it is
/// `FuelMotion.resolve`'s counterpart exactly: a device gate honoured at a
/// hundred call sites is a device gate forgotten at ninety of them.
nonisolated enum FuelHaptics {

    // MARK: - Events

    /// What happened, named by meaning rather than by the generator it ends up
    /// using. A call site says what occurred; the mapping below is this type's
    /// business, and changing it must not mean touching a feature file.
    enum Event: Equatable, Sendable, CaseIterable {

        /// A control stepping to the next of a small set of values.
        case selectionChanged

        /// A destructive action the user confirmed, once it has actually
        /// happened.
        case destructiveConfirmed

        /// An estimate arrived.
        case scanSucceeded

        /// An estimate did not.
        case scanFailed
    }

    // MARK: - Feedback

    /// What an event becomes, kept as data so `resolve` stays a pure function
    /// and both of its branches are testable without a device.
    ///
    /// It is Fuel's own enum rather than `UINotificationFeedbackGenerator`'s,
    /// because that one is nested inside a main-actor class and dragging it in
    /// here would isolate a value that has no reason to be isolated.
    enum Feedback: Hashable, Sendable {

        case selection
        case success
        case warning
        case error
    }

    // MARK: - Availability

    /// Whether this device has an engine to drive at all.
    ///
    /// `CHHapticEngine`'s hardware capability is the only public answer to that
    /// question, and it is the one Apple's own guidance points at. The settings
    /// a *user* turns haptics off with — System Haptics under Sounds & Haptics,
    /// Vibration under Accessibility → Touch, and Low Power Mode — are not
    /// readable by an app at all: UIKit applies them underneath
    /// `UIFeedbackGenerator`, so a suppressed device silently plays nothing and
    /// there is nothing here to mirror. This gate therefore answers the
    /// hardware question only, and is `false` on the simulator, which has no
    /// Taptic Engine to be right about.
    ///
    /// Read once. It describes the hardware, which does not change while the
    /// process is running.
    static let isAvailable: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    // MARK: - Resolution

    /// Turns an event into the feedback to actually play, or into nothing.
    ///
    /// The `Bool` is passed in rather than read from `isAvailable` for the
    /// reason `FuelMotion.resolve` takes its flag: it keeps this pure, and it
    /// is what lets a test hold the suppressed branch to the same rule as the
    /// playing one without a device under it.
    static func resolve(_ event: Event, hapticsAvailable: Bool) -> Feedback? {
        guard hapticsAvailable else { return nil }
        switch event {
        case .selectionChanged:
            return .selection
        // `warning` rather than `success`: a meal that has just been deleted is
        // not a thing to congratulate someone for, and the heavier double tap
        // is what makes an irreversible action feel like one.
        case .destructiveConfirmed:
            return .warning
        case .scanSucceeded:
            return .success
        case .scanFailed:
            return .error
        }
    }

    // MARK: - Playing

    /// The entry point a feature file uses. Main-actor because
    /// `UIFeedbackGenerator` is.
    ///
    /// A call site never asks whether haptics are available and never builds a
    /// generator of its own. Both would be the design-layer bypass this type
    /// exists to prevent.
    @MainActor
    static func play(_ event: Event) {
        guard let feedback = resolve(event, hapticsAvailable: isAvailable) else { return }
        switch feedback {
        case .selection:
            selection.selectionChanged()
        case .success:
            notification.notificationOccurred(.success)
        case .warning:
            notification.notificationOccurred(.warning)
        case .error:
            notification.notificationOccurred(.error)
        }
    }

    /// Held rather than built per call: a generator that is already alive is
    /// the difference between a click under the finger and one that arrives
    /// after it has lifted.
    @MainActor private static let selection = UISelectionFeedbackGenerator()

    @MainActor private static let notification = UINotificationFeedbackGenerator()
}

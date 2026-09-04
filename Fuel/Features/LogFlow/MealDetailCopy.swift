import Foundation

// MARK: - Copy

/// The four words the result screen needs when it is opened on a meal that is
/// already in the store.
///
/// Everything else it says is `MealResultCopy`'s, because it is the same
/// screen. What is here is only what a stored meal answers differently: the
/// label top right, the heading over the breakdown, and the footer's verb with
/// its confirmation.
///
/// **None of it is drawn.** The export has no screen for a logged meal, so
/// every key below is marked `Not in the export.` in the catalog.
nonisolated enum MealDetailCopy {

    // MARK: - Header

    /// The label top right, where screen 14 draws `Photo entry` and screen 15
    /// `Text entry`.
    ///
    /// Neither of those is true here. That label says which flow the user is
    /// in, and a meal opened from Today is in no flow — it is already logged.
    /// Naming the mode it was originally logged by would also leave a meal
    /// repeated from the Recent list with nothing to say, since the export
    /// draws no third label.
    static var flow: String {
        String(localized: "detail.flow")
    }

    /// The heading over the breakdown.
    ///
    /// Screen 15's word rather than screen 14's: what a stored meal carries is
    /// the breakdown it was logged with, whatever produced it, and `Recognised`
    /// claims a photo was read.
    static var itemsHeading: String {
        String(localized: "detail.items.heading")
    }

    // MARK: - Footer

    /// What VoiceOver calls the trash mark in the leading corner of the
    /// footer. It is the only thing this word is used for — the control it
    /// names draws a symbol and no label, and the question it raises carries
    /// its own three words below.
    static var delete: String {
        String(localized: "detail.delete")
    }

    static var deleteTitle: String {
        String(localized: "detail.delete.title")
    }

    static var deleteConfirm: String {
        String(localized: "detail.delete.confirm")
    }

    static var deleteCancel: String {
        String(localized: "detail.delete.cancel")
    }

    // MARK: - Leaving with edits

    /// What the confirmation in front of `‹ Back` says here.
    ///
    /// Not `MealResultCopy.discardConfirmation`, and the difference is not a
    /// nicety. On screens 14 and 15 that dialog is true: nothing has been
    /// written down, and answering it discards the estimate. Here it would be
    /// false twice — nothing is discarded, and the meal is in the store and
    /// stays there whichever button is pressed. What is actually at stake is
    /// the breakdown edits the user has just made and has not had priced.
    static var discardEditsConfirmation: FuelDialogCopy {
        FuelDialogCopy(
            title: String(localized: "detail.discardEdits.title"),
            confirm: String(localized: "detail.discardEdits.confirm"),
            cancel: String(localized: "detail.discardEdits.cancel")
        )
    }
}

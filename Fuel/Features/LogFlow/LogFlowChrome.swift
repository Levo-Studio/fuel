import SwiftUI

// MARK: - Chrome scheme

/// Which appearance the system chrome — the status bar above all — takes while
/// the log flow is up.
///
/// The export refuses to let the status bar follow the theme everywhere in this
/// flow. Seven frames hard-code the status-bar ink `#fafafa` over their dark
/// surface: screen 07, the four analysis states 08 to 11, screen 12 and screen
/// 13. Every other frame in the file draws it `color:var(--ink)`, and this
/// flow's two result screens are among them — 14 and 15 sit on `var(--bg)` and
/// carry `‹ Back` rather than `✕ Cancel`, because they are results rather than
/// flow chrome. A light-theme user must therefore get a dark status bar there
/// and a light one everywhere else in the flow.
///
/// This reads the two AI models' stages rather than a flag kept beside them, so
/// there is no second copy of the flow's state to drift: a stage that starts
/// drawing a different surface changes what this returns in the same commit.
nonisolated enum LogFlowChrome {

    /// The scheme forced over the whole flow.
    ///
    /// A result screen is the only thing here that follows the theme, and only
    /// one of the two modes can have an overlay up at a time — while one does,
    /// the tab bar the other would be reached from is off screen — so either
    /// model reaching `.result` is enough.
    ///
    /// The failure states are not in the export and draw on the camera surface
    /// like the analysis states they replace, so they stay light-inked with
    /// them rather than being listed separately.
    static func colorScheme(
        camera: CameraLogModel.Stage,
        text: TextLogModel.Stage,
        theme: FuelTheme
    ) -> ColorScheme {
        if camera == .result || text == .result {
            return theme.colorScheme
        }
        return .dark
    }

    // MARK: - Keyboard

    /// Whether the text tab's field is still on a screen the user can see.
    ///
    /// `LogFlowView` keeps the scaffold — and with it the text tab — in the
    /// hierarchy underneath the analysis and result overlays, which is what
    /// lets the flow cross-fade rather than swap. The cost is that a field left
    /// focused down there goes on holding the keyboard up over screens 08 to
    /// 11, 14 and 15, none of which draws a field at all. So focus is released
    /// by the state change rather than by the user tapping somewhere, and this
    /// is the rule that says when: the field is only reachable while the text
    /// mode is showing its entry screen and the text tab is the selected one.
    ///
    /// A rule rather than a condition written at the call site, for the same
    /// reason `colorScheme` is one — it is read off the state that already
    /// exists, so a stage that stops drawing a field changes what this returns
    /// in the same commit, and it can be checked without a simulator.
    ///
    /// `noKey` is not the entry screen: that tab draws the keyless notice, and
    /// a key removed in Settings while the field is open is exactly the case a
    /// clock-free rule has to catch.
    static func canHoldTextFocus(stage: TextLogModel.Stage, tab: LogFlowTab) -> Bool {
        stage == .entry && tab == .text
    }
}

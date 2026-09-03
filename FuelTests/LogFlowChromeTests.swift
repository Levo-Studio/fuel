import SwiftUI
import Testing

@testable import Fuel

// MARK: - Log flow chrome

/// Which appearance the log flow forces on the system chrome.
///
/// The whole question is the export's status-bar ink: seven frames hard-code
/// `#fafafa` — screen 07, the analysis states 08 to 11, screen 12 and screen 13
/// — and the two result screens, 14 and 15, draw `color:var(--ink)` like every
/// ordinary screen. So a light-theme user must see a dark status bar on the
/// results and a light one everywhere else in the flow, and that is what these
/// check, once for the camera half and once for the text half.
@Suite("Log flow chrome")
struct LogFlowChromeTests {

    // MARK: - Flow chrome and analysis

    @Test("the flow's own screens force a light status bar in either theme", arguments: [FuelTheme.light, .dark])
    func flowChromeIsAlwaysDark(theme: FuelTheme) {
        #expect(LogFlowChrome.colorScheme(camera: .viewfinder, text: .entry, theme: theme) == .dark)
    }

    @Test("a camera analysis state forces a light status bar in either theme", arguments: [FuelTheme.light, .dark])
    func cameraAnalysisIsAlwaysDark(theme: FuelTheme) {
        let scheme = LogFlowChrome.colorScheme(
            camera: .analysing(.identifyingIngredients),
            text: .entry,
            theme: theme
        )
        #expect(scheme == .dark)
    }

    @Test("a text analysis state forces a light status bar in either theme", arguments: [FuelTheme.light, .dark])
    func textAnalysisIsAlwaysDark(theme: FuelTheme) {
        let scheme = LogFlowChrome.colorScheme(
            camera: .viewfinder,
            text: .analysing(.estimatingAmounts),
            theme: theme
        )
        #expect(scheme == .dark)
    }

    /// Not in the export, but it draws on the camera surface the analysis state
    /// it replaces, so it inks with that state and not with the results.
    @Test("a failed scan stays with the analysis states")
    func failureIsDark() {
        #expect(LogFlowChrome.colorScheme(camera: .failed(.retry), text: .entry, theme: .light) == .dark)
    }

    // MARK: - Results

    @Test("the photo result follows the theme")
    func photoResultFollowsTheTheme() {
        #expect(LogFlowChrome.colorScheme(camera: .result, text: .entry, theme: .light) == .light)
        #expect(LogFlowChrome.colorScheme(camera: .result, text: .entry, theme: .dark) == .dark)
    }

    @Test("the text result follows the theme")
    func textResultFollowsTheTheme() {
        #expect(LogFlowChrome.colorScheme(camera: .viewfinder, text: .result, theme: .light) == .light)
        #expect(LogFlowChrome.colorScheme(camera: .viewfinder, text: .result, theme: .dark) == .dark)
    }
}

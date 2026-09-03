import AppIntents

// MARK: - Scan

/// The "Scan" shortcut: opens Fuel on the camera.
///
/// It draws nothing. The destination is the one the plus control on screens 05
/// and 06 already reaches — the log flow on the tab the export captions
/// `Log · camera (default)` — and this type's whole job is to say so from
/// outside the app. Everything that decides what "open the camera" means when
/// something is already presented lives in `RootShellModel.requestScan`, where
/// it can be tested without an intent invocation.
///
/// **It touches no key and sends no request.** A scan needs a key, but this is
/// not where that question is asked: the camera half asks the Keychain when
/// its tab appears, and screen 07 has a state for the answer being no. Reading
/// a key here would put a secret on a path that has no use for one.
struct ScanMealIntent: AppIntent {

    /// Both of these are shown to the user — this is how the shortcut is named
    /// and explained in the Shortcuts app — so both are catalog keys rather
    /// than literals, like every other visible string in Fuel.
    ///
    /// Not in Spotlight: an intent is offered where a user goes looking for
    /// one, and it is `AppShortcutsProvider` that makes the system volunteer a
    /// shortcut unasked. Fuel declares none, because a phrase cannot be a
    /// catalog key — it has to be a literal carrying `\(.applicationName)` —
    /// and because it would need an icon the export does not draw.
    static let title: LocalizedStringResource = "intent.scan.title"

    static let description = IntentDescription("intent.scan.description")

    /// The point of the shortcut. Fuel logs a meal by looking through the
    /// camera, so there is nothing this could do in the background — the
    /// result of running it is that the user is standing in front of screen
    /// 07.
    static let openAppWhenRun = true

    /// `perform` witnesses a `nonisolated` requirement, so the hop to the main
    /// actor the router lives on is written out rather than inherited from the
    /// file's default isolation.
    func perform() async throws -> some IntentResult {
        await ScanRouter.shared.requestScan()
        return .result()
    }
}

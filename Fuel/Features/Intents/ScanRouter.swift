import Foundation

// MARK: - Router

/// Where a scan request from outside the app is handed to the running shell.
///
/// It exists because the two ends of that hand-off cannot see each other. The
/// system builds an `AppIntent` on its own and hands it nothing, while the
/// shell model is created by the view that presents it and is reachable from
/// nowhere else. One object both ends know by name is the smallest thing that
/// joins them, and it holds no state beyond the two facts below.
///
/// The reference is weak, and nothing about that rests on how long a shell
/// lives: `RootShell` registers the model it is drawing when it appears, so
/// whatever the router holds is a shell in the view hierarchy that has an owner
/// already. A strong reference here would be a second owner, and would keep a
/// shell alive after the thing drawing it had gone — which in a test suite is
/// after every test.
@MainActor
final class ScanRouter {

    /// The one the intent talks to, and the one `RootShell` registers with by
    /// default. Nothing registers implicitly: `adopt` is called from exactly
    /// one place, so a test that names its own router is the only shell that
    /// router ever sees.
    static let shared = ScanRouter()

    private weak var shell: RootShellModel?

    /// A request that arrived before there was anything to hand it to.
    ///
    /// This is the cold-launch case and it is the reason the router is not a
    /// plain forwarding call. `openAppWhenRun` starts the app and runs the
    /// intent, and the shell registers when the window's content first appears
    /// — the two are not ordered, so a request can genuinely land first. Dropping it there would make the shortcut work only when Fuel
    /// happened to be running already.
    ///
    /// One flag rather than a queue: the shortcut asks for a screen, and two
    /// requests before the first frame ask for the same screen.
    private var isPending = false

    /// Called by `RootShell` when it appears, with the model it is drawing.
    /// The comment at that call site says why it is not done in the model's
    /// initialiser.
    func adopt(_ shell: RootShellModel) {
        self.shell = shell

        guard isPending else { return }
        // Cleared before the request is made rather than after, so a shell
        // adopted a second time in one process cannot replay it.
        isPending = false
        shell.requestScan()
    }

    func requestScan() {
        guard let shell else {
            isPending = true
            return
        }
        shell.requestScan()
    }
}

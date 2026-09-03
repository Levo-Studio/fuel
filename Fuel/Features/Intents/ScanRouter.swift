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
/// The reference is weak. The shell model is owned by the view for the life of
/// the process, so there is nothing here to keep alive, and a strong reference
/// would outlive a shell that went away — in the app it never does, in a test
/// suite it does after every test.
@MainActor
final class ScanRouter {

    /// The one the intent talks to. Tests build their own rather than reaching
    /// for this, so a suite never depends on which shell registered last.
    static let shared = ScanRouter()

    private weak var shell: RootShellModel?

    /// A request that arrived before there was anything to hand it to.
    ///
    /// This is the cold-launch case and it is the reason the router is not a
    /// plain forwarding call. `openAppWhenRun` starts the app and runs the
    /// intent, and the shell model is built when the window's content is first
    /// evaluated — the two are not ordered, so a request can genuinely land
    /// first. Dropping it there would make the shortcut work only when Fuel
    /// happened to be running already.
    ///
    /// One flag rather than a queue: the shortcut asks for a screen, and two
    /// requests before the first frame ask for the same screen.
    private var isPending = false

    /// The shell registers itself as it is created.
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

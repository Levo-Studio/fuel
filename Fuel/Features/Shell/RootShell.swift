import SwiftUI

// MARK: - Root shell

/// The single window's content.
///
/// The shell decides what the app opens on: the onboarding flow until a goal
/// has been chosen, the Today screen afterwards. Both of those arrive with
/// their own features; until then it stands empty so the target builds and the
/// scheme runs.
struct RootShell: View {

    var body: some View {
        EmptyView()
    }
}

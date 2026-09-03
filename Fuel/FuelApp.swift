import SwiftUI

// MARK: - App

@main
struct FuelApp: App {

    /// One store for the whole process, created once and handed down.
    ///
    /// What makes it once is that `@main` instantiates this struct a single
    /// time — **not** the property wrapper. A `@State`'s default expression
    /// runs on every initialisation of the struct holding it and `State` keeps
    /// only the first value it is handed, so the same line on a `View` would
    /// open a container per construction and throw all but one away. Here a
    /// plain `let` would behave identically; the wrapper is used because the
    /// store outlives every view below it and SwiftUI, rather than this struct,
    /// is what should own it.
    @State private var store = FuelApp.openStore()

    var body: some Scene {
        WindowGroup {
            RootShell(store: store, validator: ProviderKeyValidator())
        }
    }

    /// Opening the on-device store is the one thing Fuel cannot do without.
    ///
    /// There is no drawn state for "the database will not open", and the
    /// tempting fallback — an in-memory container — would give the user a
    /// working-looking app that silently discards every meal they log. Stopping
    /// here is the honest outcome.
    ///
    /// The error is interpolated into the crash report because the reasons this
    /// call fails are worth telling apart: a schema mismatch after an update —
    /// the likeliest of them in the field — a full disk, or protected data
    /// still locked at launch all read as the same crash without it. It carries
    /// nothing the no-logging rule protects: no key, no photo, no typed text,
    /// no model reply. None of those exist yet at this point in the launch.
    private static func openStore() -> FuelStore {
        do {
            return try FuelStore()
        } catch {
            fatalError("The Fuel store could not be opened: \(error)")
        }
    }
}

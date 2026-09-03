import SwiftUI

// MARK: - App

@main
struct FuelApp: App {

    /// One store for the whole process, created once and handed down.
    ///
    /// It is `@State` rather than a plain property because SwiftUI owns the
    /// storage behind a `@State`: the container is opened on the first
    /// evaluation and never again, where a `let` on a struct SwiftUI is free to
    /// re-create would risk opening it twice.
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
    /// here is the honest outcome. The message carries nothing about the user
    /// or their data.
    private static func openStore() -> FuelStore {
        do {
            return try FuelStore()
        } catch {
            fatalError("The Fuel store could not be opened.")
        }
    }
}

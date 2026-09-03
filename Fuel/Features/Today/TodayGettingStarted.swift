import Foundation

// MARK: - Step

/// The three things a new user still has ahead of them, in the order they are
/// drawn.
///
/// Two rules decide what is on this list, and both are exclusions.
///
/// **Nothing onboarding already answered.** The key is screens 01–03 and cannot
/// be skipped; goal-or-count-only is screen 04. Both are settled before Today
/// is reachable at all, so a row asking for either would be asking for
/// something the user did a minute ago. What is left is customisation — the
/// choices screen 16 offers and nobody is made to make — and the first use of
/// the app.
///
/// **Nothing whose done state Fuel cannot establish.** A checklist that shows a
/// tick for something it can only guess at is a lie, and there is no drawn
/// design to hide behind here: the export draws no empty state at all, so this
/// list is built with more restraint than a drawn screen, not less.
nonisolated enum TodayGettingStartedStep: CaseIterable, Hashable, Sendable, Identifiable {

    /// Done when the theme differs from the one Fuel opens on.
    ///
    /// Screen 16 draws Light and Dark as a two-segment control of its own, so
    /// this is a choice in its own right rather than half of an "appearance"
    /// row invented here.
    case theme

    /// Done when the accent differs from `mono`, which is the one the app
    /// ships with. Screen 16 draws the five swatches as their own section.
    case accent

    /// Done when any entry exists in the store, on any day — not when today has
    /// one. An entry today would un-tick itself at midnight, which for a row
    /// that says "your first meal" is absurd.
    ///
    /// It is also the row that ends the list: see `TodayGettingStarted`'s
    /// `isOffered`. A user never sees this one ticked, because the moment it
    /// would be, the checklist is gone.
    case firstMeal

    var id: Self { self }

    // MARK: - Destination

    /// Where a tap on the row goes.
    ///
    /// Both are destinations Today already has: the gear's and the plus's. The
    /// checklist opens no route of its own, and Settings has no way to be
    /// opened at a particular section, so the two rows it answers land at the
    /// top of it.
    enum Destination: Hashable, Sendable {
        case settings
        case logFlow
    }

    var destination: Destination {
        switch self {
        case .theme, .accent: .settings
        case .firstMeal: .logFlow
        }
    }
}

// MARK: - Item

/// One row: which step it is, and whether it is done.
nonisolated struct TodayGettingStartedItem: Hashable, Sendable, Identifiable {

    let step: TodayGettingStartedStep
    let isDone: Bool

    var id: TodayGettingStartedStep { step }
}

// MARK: - Checklist

/// The get-started checklist Today draws at the beginning of the app.
///
/// A plain value with no store and no view in it, so every rule above can be
/// pinned without a `ModelContainer` and without a simulator. The three answers
/// are worked out by whoever can reach the things that hold them —
/// `RootShellModel` — and handed in.
///
/// It is not in `Fuel/Nutrition/`: none of this is nutrition, and the core
/// there knows about meals and arithmetic rather than about onboarding state.
nonisolated struct TodayGettingStarted: Hashable, Sendable {

    let items: [TodayGettingStartedItem]

    /// Kept, rather than only folded into the meal row, because it answers a
    /// second question the rows cannot: whether there is a checklist at all.
    private let hasLoggedMeal: Bool

    init(
        hasChosenTheme: Bool,
        hasChosenAccent: Bool,
        hasLoggedMeal: Bool
    ) {
        self.hasLoggedMeal = hasLoggedMeal
        let answers: [TodayGettingStartedStep: Bool] = [
            .theme: hasChosenTheme,
            .accent: hasChosenAccent,
            .firstMeal: hasLoggedMeal
        ]
        // Built from `allCases` rather than from the dictionary, so the drawn
        // order is the order the cases are written in and cannot come out of a
        // hash.
        self.items = TodayGettingStartedStep.allCases.map { step in
            TodayGettingStartedItem(step: step, isDone: answers[step] ?? false)
        }
    }

    /// Whether Today offers the checklist at all.
    ///
    /// **The first logged meal retires it for good**, and it is the only thing
    /// that does. Not every row being ticked: an accent the user never touched
    /// would otherwise keep a get-started list alive on someone who has been
    /// logging meals for a week, which is the opposite of what the list is for.
    ///
    /// So the checklist belongs to the beginning of the app rather than to an
    /// empty day. A later empty day is simply an empty day, drawn as it was
    /// before this existed.
    var isOffered: Bool { !hasLoggedMeal }

    func isDone(_ step: TodayGettingStartedStep) -> Bool {
        items.first { $0.step == step }?.isDone ?? false
    }
}

import Foundation

// MARK: - Step

/// The four things a new user still has ahead of them, in the order they are
/// drawn.
///
/// **Every one of them has a done state Fuel can actually establish**, and that
/// is the whole membership rule. A checklist that shows a tick for something it
/// cannot know is a lie, and there is no drawn design to hide behind here — the
/// export draws no empty state at all, so this list is built with more
/// restraint than a drawn screen, not less. Anything whose completion could
/// only be guessed at is left off.
nonisolated enum TodayGettingStartedStep: CaseIterable, Hashable, Sendable, Identifiable {

    /// Done when a key is stored for the provider that is selected.
    ///
    /// Answered through `MealKeyPresence`, which cannot return a key — the tick
    /// is drawn from an item's existence, never from reading a secret to look
    /// at it.
    case key

    /// Done when the counting mode is goal rather than count-only.
    ///
    /// Count-only is a legitimate final answer and not an unfinished state, so
    /// this row stays unticked for a user who meant it. It is an invitation
    /// rather than a scold: the row is worded as an offer, it is one tap from
    /// the control that changes it, and the whole checklist disappears the
    /// moment the day has an entry in it.
    case goal

    /// Done when the theme or the accent differs from what Fuel ships with.
    case appearance

    /// Done when any entry exists in the store, on any day — not when today has
    /// one. An entry today would un-tick itself at midnight, which for a row
    /// that says "your first meal" is absurd.
    case firstMeal

    var id: Self { self }

    // MARK: - Destination

    /// Where a tap on the row goes.
    ///
    /// Both are destinations Today already has: the gear's and the plus's. The
    /// checklist opens no route of its own, and Settings has no way to be
    /// opened at a particular section, so the three rows it answers all land at
    /// the top of it.
    enum Destination: Hashable, Sendable {
        case settings
        case logFlow
    }

    var destination: Destination {
        switch self {
        case .key, .goal, .appearance: .settings
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
/// A plain value with no store, no keychain and no view in it, so every rule
/// above can be pinned without a `ModelContainer` and without a simulator. The
/// four answers are worked out by whoever can reach the things that hold them —
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
        hasProviderKey: Bool,
        isGoalMode: Bool,
        hasCustomisedAppearance: Bool,
        hasLoggedMeal: Bool
    ) {
        self.hasLoggedMeal = hasLoggedMeal
        let answers: [TodayGettingStartedStep: Bool] = [
            .key: hasProviderKey,
            .goal: isGoalMode,
            .appearance: hasCustomisedAppearance,
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

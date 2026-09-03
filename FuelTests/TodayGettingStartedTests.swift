import Foundation
import Testing

@testable import Fuel

// MARK: - Fixtures

/// Every answer false, so a test names only the one it is about.
private nonisolated func checklist(
    hasProviderKey: Bool = false,
    isGoalMode: Bool = false,
    hasCustomisedAppearance: Bool = false,
    hasLoggedMeal: Bool = false
) -> TodayGettingStarted {
    TodayGettingStarted(
        hasProviderKey: hasProviderKey,
        isGoalMode: isGoalMode,
        hasCustomisedAppearance: hasCustomisedAppearance,
        hasLoggedMeal: hasLoggedMeal
    )
}

// MARK: - Suite

/// The get-started checklist's rules, one at a time.
///
/// Each done state is pinned on its own rather than through a single "all four"
/// case, because the failure worth catching is one answer wired to the wrong
/// row — which an all-true and an all-false case would both pass.
@Suite("Today getting started")
struct TodayGettingStartedTests {

    // MARK: - Shape

    @Test("the four steps are drawn in the order they are written")
    func order() {
        #expect(checklist().items.map(\.step) == [.key, .goal, .appearance, .firstMeal])
    }

    @Test("nothing is done on a first run")
    func nothingDone() {
        #expect(checklist().items.allSatisfy { $0.isDone == false })
    }

    // MARK: - One rule per row

    @Test("a stored key ticks the key row and nothing else")
    func keyRow() {
        let list = checklist(hasProviderKey: true)
        #expect(list.isDone(.key))
        #expect(list.isDone(.goal) == false)
        #expect(list.isDone(.appearance) == false)
        #expect(list.isDone(.firstMeal) == false)
    }

    @Test("goal mode ticks the goal row and nothing else")
    func goalRow() {
        let list = checklist(isGoalMode: true)
        #expect(list.isDone(.goal))
        #expect(list.isDone(.key) == false)
        #expect(list.isDone(.appearance) == false)
        #expect(list.isDone(.firstMeal) == false)
    }

    @Test("count-only leaves the goal row open rather than done")
    func countOnlyIsNotDone() {
        #expect(checklist(isGoalMode: false).isDone(.goal) == false)
    }

    @Test("a changed appearance ticks the look row and nothing else")
    func appearanceRow() {
        let list = checklist(hasCustomisedAppearance: true)
        #expect(list.isDone(.appearance))
        #expect(list.isDone(.key) == false)
        #expect(list.isDone(.goal) == false)
        #expect(list.isDone(.firstMeal) == false)
    }

    @Test("a logged meal ticks the meal row and nothing else")
    func mealRow() {
        let list = checklist(hasLoggedMeal: true)
        #expect(list.isDone(.firstMeal))
        #expect(list.isDone(.key) == false)
        #expect(list.isDone(.goal) == false)
        #expect(list.isDone(.appearance) == false)
    }

    // MARK: - Termination

    /// The rule that matters most: **the first logged meal retires the
    /// checklist**, and nothing else does.
    @Test("The checklist is offered until the first meal is logged")
    func offeredUntilTheFirstMeal() {
        #expect(checklist().isOffered)
        #expect(checklist(hasLoggedMeal: true).isOffered == false)
    }

    /// The reading a "tick everything" rule would get wrong in both directions.
    @Test("Every other row being done does not retire the checklist")
    func tickedRowsDoNotRetireIt() {
        #expect(checklist(hasProviderKey: true, isGoalMode: true, hasCustomisedAppearance: true).isOffered)
    }

    @Test("An untouched appearance does not keep the checklist alive")
    func untouchedAppearanceDoesNotKeepItAlive() {
        #expect(checklist(hasLoggedMeal: true).isOffered == false)
        #expect(checklist(hasLoggedMeal: true).isDone(.appearance) == false)
    }

    // MARK: - Destinations

    @Test("the three preference rows open Settings and the meal row opens the log flow")
    func destinations() {
        #expect(TodayGettingStartedStep.key.destination == .settings)
        #expect(TodayGettingStartedStep.goal.destination == .settings)
        #expect(TodayGettingStartedStep.appearance.destination == .settings)
        #expect(TodayGettingStartedStep.firstMeal.destination == .logFlow)
    }
}

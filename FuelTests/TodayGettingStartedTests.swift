import Foundation
import Testing

@testable import Fuel

// MARK: - Fixtures

/// Every answer false, so a test names only the one it is about.
private nonisolated func checklist(
    hasChosenTheme: Bool = false,
    hasChosenAccent: Bool = false,
    hasLoggedMeal: Bool = false
) -> TodayGettingStarted {
    TodayGettingStarted(
        hasChosenTheme: hasChosenTheme,
        hasChosenAccent: hasChosenAccent,
        hasLoggedMeal: hasLoggedMeal
    )
}

// MARK: - Suite

/// The get-started checklist's rules, one at a time.
///
/// Each done state is pinned on its own rather than through a single "all
/// three" case, because the failure worth catching is one answer wired to the
/// row — which an all-true and an all-false case would both pass.
@Suite("Today getting started")
struct TodayGettingStartedTests {

    // MARK: - Shape

    @Test("the three steps are drawn in the order they are written")
    func order() {
        #expect(checklist().items.map(\.step) == [.theme, .accent, .firstMeal])
    }

    /// The list asks for nothing onboarding has already settled, so there is no
    /// row for the key and none for the counting mode.
    @Test("no step asks for something onboarding already answered")
    func noSetupSteps() {
        #expect(TodayGettingStartedStep.allCases.count == 3)
    }

    @Test("nothing is done on a first run")
    func nothingDone() {
        #expect(checklist().items.allSatisfy { $0.isDone == false })
    }

    // MARK: - One rule per row

    @Test("a chosen theme ticks the theme row and nothing else")
    func themeRow() {
        let list = checklist(hasChosenTheme: true)
        #expect(list.isDone(.theme))
        #expect(list.isDone(.accent) == false)
        #expect(list.isDone(.firstMeal) == false)
    }

    @Test("a chosen accent ticks the accent row and nothing else")
    func accentRow() {
        let list = checklist(hasChosenAccent: true)
        #expect(list.isDone(.accent))
        #expect(list.isDone(.theme) == false)
        #expect(list.isDone(.firstMeal) == false)
    }

    /// Two rows rather than one, because screen 16 draws two controls. A single
    /// "appearance" row would tick on either and say neither.
    @Test("the theme and the accent are answered apart from each other")
    func themeAndAccentAreSeparate() {
        #expect(checklist(hasChosenTheme: true).isDone(.accent) == false)
        #expect(checklist(hasChosenAccent: true).isDone(.theme) == false)
    }

    @Test("a logged meal ticks the meal row and nothing else")
    func mealRow() {
        let list = checklist(hasLoggedMeal: true)
        #expect(list.isDone(.firstMeal))
        #expect(list.isDone(.theme) == false)
        #expect(list.isDone(.accent) == false)
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
        #expect(checklist(hasChosenTheme: true, hasChosenAccent: true).isOffered)
    }

    @Test("An untouched appearance does not keep the checklist alive")
    func untouchedAppearanceDoesNotKeepItAlive() {
        #expect(checklist(hasLoggedMeal: true).isOffered == false)
        #expect(checklist(hasLoggedMeal: true).isDone(.theme) == false)
        #expect(checklist(hasLoggedMeal: true).isDone(.accent) == false)
    }

    // MARK: - Destinations

    @Test("the two preference rows open Settings and the meal row opens the log flow")
    func destinations() {
        #expect(TodayGettingStartedStep.theme.destination == .settings)
        #expect(TodayGettingStartedStep.accent.destination == .settings)
        #expect(TodayGettingStartedStep.firstMeal.destination == .logFlow)
    }
}

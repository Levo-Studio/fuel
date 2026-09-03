import Foundation

// MARK: - The two segments

/// Which segment of the counting control is selected.
///
/// It is not `CountingMode`. That type carries the targets with it, which is
/// exactly what a control must not do: the numbers survive a switch to
/// count-only and come back with the user, so the segment is the choice alone
/// and the targets are held beside it.
nonisolated enum CountingChoice: Hashable, CaseIterable, Sendable {

    case withGoal
    case countOnly
}

// MARK: - The four target fields

/// The four rows the counting section expands to, in the order screen 17 draws
/// them.
///
/// Written out rather than derived from `DailyTargets`, because the order is a
/// promise to the design and a reordering of that struct's stored properties
/// must not quietly reorder the screen.
nonisolated enum GoalTarget: CaseIterable, Hashable, Sendable {

    case calories
    case protein
    case carbs
    case fat

    /// Where the row's value lives.
    var keyPath: WritableKeyPath<DailyTargets, Int> {
        switch self {
        case .calories: \.kilocalories
        case .protein: \.protein
        case .carbs: \.carbs
        case .fat: \.fat
        }
    }
}

// MARK: - Model

/// Holds the counting mode and the four targets for screen 17, and writes both
/// through `FuelStore`.
///
/// **Switching to count-only does not throw the numbers away.** The mode and
/// the targets are separate pieces of state here for the same reason they are
/// separate columns on `GoalSettings`: a user who counts for a week and then
/// wants their goal back gets their own numbers, not the defaults. Nothing in
/// this type clears a target, and the store's count-only write leaves the
/// columns standing.
///
/// The targets are read with `storedTargets()` rather than out of
/// `countingMode()`, which is the same point from the other side — in
/// count-only mode that call returns a case with no targets in it, and a model
/// that fell back to `.default` there would show 2400/160/240/70 to a user
/// whose goal is something else the moment they switch back.
@Observable
final class CountingSettingsModel {

    // MARK: - State

    var choice: CountingChoice {
        didSet { persist() }
    }

    /// The four numbers, whichever mode is selected.
    private(set) var targets: DailyTargets

    @ObservationIgnored private let store: FuelStore

    // MARK: - Creation

    init(store: FuelStore) throws {
        self.store = store
        self.choice = try store.countingMode().targets == nil ? .countOnly : .withGoal
        self.targets = try store.storedTargets()
    }

    // MARK: - Editing a target

    func value(for target: GoalTarget) -> Int {
        targets[keyPath: target.keyPath]
    }

    /// Takes what is in the field and stores what it now means.
    ///
    /// A cleared field keeps the value it had rather than becoming zero — see
    /// `GoalFieldInput`, which is where that rule was written after a lost
    /// edit — and the digit filter is the same one the onboarding field uses,
    /// so a pasted `2,400` cannot land here as something the number pad would
    /// never have produced.
    func setValue(from typed: String, for target: GoalTarget) {
        targets[keyPath: target.keyPath] = GoalFieldInput.value(
            from: typed,
            previous: value(for: target)
        )
        persist()
    }

    // MARK: - Writing

    /// The mode as the store takes it.
    private var mode: CountingMode {
        switch choice {
        case .withGoal: .goal(targets)
        case .countOnly: .countOnly
        }
    }

    /// Writes the choice and the targets.
    ///
    /// A failed write is swallowed: the design draws no state for a local save
    /// that did not land, and inventing one would be a deviation. What it must
    /// not do is take the value off the screen — the user's edit stands in this
    /// model either way, so the row keeps reading what they typed.
    private func persist() {
        try? store.setCountingMode(mode)
    }
}

import Foundation
import Testing

@testable import Fuel

// MARK: - Analysis walk

/// The captions an analysis prints while it runs, and the rules they are held
/// to: the order, the ceiling on how long one may be scheduled to stand, and
/// what Reduce Motion is answered with.
///
/// **Every sequence assertion here is spelled out rather than derived.** The
/// obvious way to test a walk is to compare it against `AnalysisStep.allCases`,
/// and that tests nothing at all — reordering the enum reorders both sides and
/// the suite stays green. So the expected order is written down as literal
/// cases, and the stages a log model actually passes through are recorded from
/// the model rather than read off the type it reads.
@Suite("Analysis walk")
@MainActor
struct AnalysisWalkTests {

    // MARK: - Recording

    /// The captions a model passed through while an estimate was out.
    ///
    /// `walkSteps` awaits `pace()` and *then* writes the next stage, so a pace
    /// that samples the model records the caption each one replaces; the one it
    /// finishes on is read after the walk. Together that is the whole sequence,
    /// taken from the model's own behaviour.
    private final class StageLog: @unchecked Sendable {
        private(set) var steps: [AnalysisStep] = []

        func record(_ step: AnalysisStep?) {
            guard let step, steps.last != step else { return }
            steps.append(step)
        }
    }

    private func step(of model: TextLogModel) -> AnalysisStep? {
        if case .analysing(let step) = model.stage { return step }
        return nil
    }

    /// Runs one analysis to the end of its narration and returns the captions
    /// it printed, in order.
    ///
    /// The client never answers, so the walk is observed to its end rather than
    /// cut short by a result — which is the ordinary case and is covered
    /// elsewhere. The pace is instant: the dwell is for the eye, and pinning it
    /// here would make every test in this suite wait seconds.
    private func captions(reduceMotion: Bool) async throws -> [AnalysisStep] {
        let log = StageLog()
        let box = ModelBox()

        let model = TextLogModel(
            store: try FuelStore(inMemory: true, calendar: testCalendar),
            client: SilentClient(),
            keys: StoredKey(),
            provider: .claude,
            now: { at(19, 20) },
            pace: { [weak log, weak box] in
                guard let log, let box else { return }
                await MainActor.run { log.record(box.currentStep) }
            },
            reduceMotion: { reduceMotion }
        )
        box.model = model
        model.typedText = "porridge with an apple"

        model.analyse()
        log.record(step(of: model))
        for _ in 0..<300 { await Task.yield() }
        log.record(step(of: model))

        model.cancelEstimate()
        return log.steps
    }

    /// Lets the `@Sendable` pace closure reach a main-actor model without
    /// capturing it.
    @MainActor private final class ModelBox: @unchecked Sendable {
        weak var model: TextLogModel?

        var currentStep: AnalysisStep? {
            if case .analysing(let step) = model?.stage { return step }
            return nil
        }
    }

    // MARK: - Order

    @Test("the walk names the six captions in the order the work happens")
    func theWalkIsInOrder() async throws {
        // Written out rather than taken from `allCases`: this is the claim, and
        // a claim compared against its own source is not a claim.
        #expect(
            try await captions(reduceMotion: false) == [
                .sendingRequest,
                .analysingMeal,
                .identifyingIngredients,
                .estimatingAmounts,
                .calculatingNutrition,
                .waitingForModel,
            ]
        )
    }

    @Test("an analysis begins on the caption anchored to the request going out")
    func itBeginsOnSending() throws {
        let model = TextLogModel(
            store: try FuelStore(inMemory: true, calendar: testCalendar),
            client: SilentClient(),
            keys: StoredKey(),
            provider: .claude,
            now: { at(19, 20) },
            pace: {},
            reduceMotion: { false }
        )
        model.typedText = "porridge with an apple"

        model.analyse()

        // No yielding: this is the caption the tap itself sets, before any
        // pacing can run. It is the one anchored to something the model can
        // see rather than to the clock.
        #expect(step(of: model) == .sendingRequest)
        model.cancelEstimate()
    }

    @Test("the walk ends on the one caption that is still true after a minute")
    func itEndsOnWaiting() {
        // The last caption is not scheduled — it stands until the answer
        // arrives, which is unbounded. So it has to be one that does not become
        // a lie while it is on screen, and that is what this pins.
        #expect(AnalysisStep.walk(reduceMotion: false).last == .waitingForModel)
        #expect(AnalysisStep.walk(reduceMotion: true).last == .waitingForModel)
    }

    // MARK: - The ceiling

    @Test("no caption is scheduled to stand longer than the ceiling")
    func theDwellIsUnderTheCeiling() {
        // The owner's rule is about what is *scheduled*. Only the paced
        // captions are, and they share one dwell, so this is the whole of it:
        // raise the dwell past the ceiling and this goes red.
        #expect(FuelMotion.analysisStepHold <= FuelMotion.pacedStepCeiling)
        #expect(FuelMotion.pacedStepCeiling == .seconds(2))
    }

    @Test("only the caption the walk ends on is left unscheduled")
    func onlyTheLastIsUnscheduled() {
        // The ceiling only means something if the sequence really does schedule
        // everything except its end. `walkSteps` paces once per step it walks.
        let walk = AnalysisStep.walk(reduceMotion: false)

        #expect(walk.dropLast().allSatisfy { $0 != .waitingForModel })
        #expect(walk.count == 5)
    }

    // MARK: - Reduce Motion

    @Test("Reduce Motion goes from the request to the waiting and says nothing between")
    func reduceMotionSkipsTheMiddle() async throws {
        // One change, not five: what is being done, then what is being waited
        // for. The four between are the ones that rewrite themselves under a
        // reader's eyes, which is what Reduce Motion objects to.
        #expect(try await captions(reduceMotion: true) == [.sendingRequest, .waitingForModel])
    }

    @Test("the pacing rule lives in the design layer, not at the call site")
    func theRuleLivesInMotion() {
        #expect(FuelMotion.resolvePacedNarration(reduceMotion: false))
        #expect(!FuelMotion.resolvePacedNarration(reduceMotion: true))
    }

    // MARK: - Words

    @Test("every caption has its own words")
    func everyStepIsWritten() {
        let written = AnalysisStep.allCases.map(AnalysisCopy.step)

        #expect(written.allSatisfy { !$0.isEmpty })
        // Distinct, because six captions that read alike would be a bar moving
        // under one sentence — the screen the owner asked to replace.
        #expect(Set(written).count == AnalysisStep.allCases.count)
        // Not a key that failed to resolve: a missing entry returns its own key.
        #expect(written.allSatisfy { !$0.hasPrefix("logFlow.") })
    }

    // MARK: - The bar

    @Test("the bar never goes backwards, and the added captions take no share")
    func theBarOnlyFills() {
        let shares = AnalysisStep.allCases.map(\.progress)

        #expect(zip(shares, shares.dropFirst()).allSatisfy { $1 >= $0 })
        // The two captions added either side of the export's four borrow their
        // neighbours' fill rather than displacing it, so every drawn frame
        // still stands where it is drawn. `CameraLogTests` pins the four
        // figures themselves against the export.
        #expect(AnalysisStep.sendingRequest.progress == 0)
        #expect(AnalysisStep.waitingForModel.progress == AnalysisStep.calculatingNutrition.progress)
    }
}

// MARK: - Stand-in

/// A client whose estimate never answers, so a walk runs to its end instead of
/// being cut short by a result.
///
/// `ScriptedClient` answers at once, which is the right shape for every other
/// test and the wrong one here: the captions after the first exist precisely
/// for the time a request is still out.
private struct SilentClient: AIClient {

    let provider: AIProvider = .claude

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .failed(.cancelled) }

    func estimate(photo: MealPhoto, context: String?) async throws -> MealEstimate {
        try await never()
    }

    func estimate(text: String) async throws -> MealEstimate {
        try await never()
    }

    func adjust(
        _ meal: AdjustableMeal,
        history: [MealChatTurn],
        message: String
    ) -> AsyncThrowingStream<MealChatEvent, any Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError.cancelled) }
    }

    /// Suspends until the test cancels the estimate, which every test here does.
    private func never() async throws -> MealEstimate {
        try await Task.sleep(for: .seconds(3600))
        throw AIError.cancelled
    }
}

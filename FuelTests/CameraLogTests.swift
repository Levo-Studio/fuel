import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Camera log

/// The camera half of the log flow: the keyless tab, the scan, the failure
/// mapping and the edits the result screen allows.
///
/// **Nothing here reaches a network or a camera.** Both are injected — a
/// `ScriptedClient` that answers from memory and a `MealCamera` that hands back
/// a one-pixel image — so every test runs on the same evidence whatever the
/// machine's connection or hardware is doing. `NoKeys`/`StoredKey` answer the
/// Keychain question without a keychain-access group, which is also why no test
/// here needs one.
@Suite("Camera log")
@MainActor
struct CameraLogTests {

    // MARK: - Fixtures

    private func makeStore() throws -> FuelStore {
        try FuelStore(inMemory: true, calendar: testCalendar)
    }

    private func makeModel(
        store: FuelStore,
        client: ScriptedClient,
        keys: any MealKeyPresence = StoredKey(),
        camera: any MealCamera = StubCamera(),
        at moment: Date = at(19, 20)
    ) -> CameraLogModel {
        CameraLogModel(
            store: store,
            client: client,
            camera: camera,
            keys: keys,
            provider: .claude,
            now: { moment },
            // The four analysis steps are paced for the eye, not for the
            // request. Walking them instantly keeps the tests about outcomes.
            pace: {}
        )
    }

    private static let estimate = MealEstimate(
        title: "Salmon with polenta",
        kilocalories: 460,
        macros: MacroTotals(protein: 34, carbs: 28, fat: 23),
        items: [
            RecognisedItem(
                name: "Salmon fillet, pan-fried",
                kilocalories: 240,
                note: .photo(confidence: .confident, approximateGrams: 150)
            ),
            RecognisedItem(
                name: "Leaf spinach",
                kilocalories: 70,
                note: .photo(confidence: .unsure, approximateGrams: 90)
            ),
        ]
    )

    // MARK: - No key

    @Test("with no key stored the tab is disabled and no request is made")
    func noKeyDisablesTheTab() throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client, keys: NoKeys())

        model.refreshAvailability()
        #expect(model.stage == .noKey)

        // The shutter is not drawn in this state, but the model must refuse the
        // scan anyway: the key can go away between the draw and the tap.
        model.analyse(pixel())

        #expect(model.stage == .noKey)
        #expect(client.requests == 0)
        #expect(model.photo == nil)
    }

    @Test("a key appearing enables the tab again")
    func aKeyEnablesTheTab() throws {
        let keys = MutableKeys(hasKey: false)
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            keys: keys
        )

        model.refreshAvailability()
        #expect(model.stage == .noKey)

        keys.hasKey = true
        model.refreshAvailability()
        #expect(model.stage == .viewfinder)
    }

    // MARK: - A successful scan

    @Test("a successful estimate produces the result state with its items")
    func successfulScan() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client)

        await model.scanning(pixel())

        #expect(model.stage == .result)
        #expect(client.requests == 1)
        let draft = try #require(model.draft)
        #expect(draft.title == "Salmon with polenta")
        #expect(draft.kilocalories == 460)
        #expect(draft.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
        #expect(draft.items.map(\.name) == ["Salmon fillet, pan-fried", "Leaf spinach"])
        #expect(draft.items.map(\.note) == [
            .photo(confidence: .confident, approximateGrams: 150),
            .photo(confidence: .unsure, approximateGrams: 90),
        ])
    }

    @Test("the scan walks all four analysis steps in the drawn order")
    func stepsRunInOrder() {
        #expect(AnalysisStep.allCases == [
            .analysingMeal,
            .identifyingIngredients,
            .estimatingAmounts,
            .calculatingNutrition,
        ])
        // Quarters, one per step, exactly as the export fills the 120×2 bar.
        #expect(AnalysisStep.allCases.map(\.progress) == [0.25, 0.5, 0.75, 1])
    }

    @Test("the result's label is the one the day rule gives that moment")
    func provisionalLabel() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        let model = makeModel(store: try makeStore(), client: client, at: at(19, 20))

        await model.scanning(pixel())

        #expect(model.draft?.label == .dinner)
        #expect(model.draft?.isLabelUserSet == false)
    }

    // MARK: - Failures

    @Test("each provider error maps to the state that is drawn for it", arguments: [
        (AIError.invalidKey, AnalysisFailure.invalidKey),
        (AIError.missingKey, AnalysisFailure.invalidKey),
        (AIError.network, AnalysisFailure.retry),
        (AIError.malformedResponse, AnalysisFailure.retry),
        (AIError.imageTooLarge, AnalysisFailure.retry),
    ])
    func errorMapping(error: AIError, expected: AnalysisFailure) async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(error)))

        await model.scanning(pixel())

        #expect(model.stage == .failed(expected))
    }

    @Test("an exhausted balance carries the provider's own billing page")
    func noCreditCarriesItsLink() async throws {
        let error = AIError.noCredit(for: .claude)
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(error)))

        await model.scanning(pixel())

        #expect(model.stage == .failed(.noCredit(billingPage: AIError.billingPage(for: .claude))))
    }

    @Test("a cancelled scan is silent, not a retry prompt")
    func cancelledScanIsSilent() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .failure(.cancelled)))

        await model.scanning(pixel())

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        // The frame is released with the scan. Nothing of it outlives the tap.
        #expect(model.photo == nil)
    }

    @Test("no failure state can be built from a cancellation")
    func cancellationHasNoDrawnState() {
        #expect(AnalysisFailure(.cancelled) == nil)
    }

    @Test("a camera that cannot deliver a frame is a retry, not silence")
    func failedCaptureIsARetry() async throws {
        let model = makeModel(
            store: try makeStore(),
            client: ScriptedClient(answer: .success(Self.estimate)),
            camera: FailingCamera()
        )

        await model.capture()

        #expect(model.stage == .failed(.retry))
    }

    // MARK: - Editing the result

    @Test("the stepper moves ten kilocalories a tap and floors at zero")
    func stepperFloorsAtZero() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.adjustKilocalories(by: CameraLogModel.calorieStep)
        #expect(model.draft?.kilocalories == 470)

        model.adjustKilocalories(by: -CameraLogModel.calorieStep)
        #expect(model.draft?.kilocalories == 460)

        for _ in 0..<50 {
            model.adjustKilocalories(by: -CameraLogModel.calorieStep)
        }
        #expect(model.draft?.kilocalories == 0)

        // And it comes back up from the floor rather than sticking there.
        model.adjustKilocalories(by: CameraLogModel.calorieStep)
        #expect(model.draft?.kilocalories == 10)
    }

    @Test("the label pill cycles breakfast, lunch, snack, dinner and wraps")
    func labelPillCycles() async throws {
        let client = ScriptedClient(answer: .success(Self.estimate))
        // 08:10 on an empty day, so the first label is breakfast and the cycle
        // starts where the design's list does.
        let model = makeModel(store: try makeStore(), client: client, at: at(8, 10))
        await model.scanning(pixel())

        #expect(model.draft?.label == .breakfast)

        model.cycleLabel()
        #expect(model.draft?.label == .lunch)
        #expect(model.draft?.isLabelUserSet == true)

        model.cycleLabel()
        #expect(model.draft?.label == .snack)

        model.cycleLabel()
        #expect(model.draft?.label == .dinner)

        model.cycleLabel()
        #expect(model.draft?.label == .breakfast)
    }

    @Test("the favourite toggle goes both ways")
    func favouriteToggles() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        #expect(model.draft?.isFavourite == false)
        model.toggleFavourite()
        #expect(model.draft?.isFavourite == true)
        model.toggleFavourite()
        #expect(model.draft?.isFavourite == false)
    }

    // MARK: - Committing

    @Test("committing writes an entry whose macros and items match the estimate")
    func commitWritesTheEstimate() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.adjustKilocalories(by: CameraLogModel.calorieStep)
        model.toggleFavourite()
        #expect(model.commit())

        let entries = try store.entries(on: at(19, 20))
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.title == "Salmon with polenta")
        // The stepper's tap is part of what is written, not a display-only
        // adjustment.
        #expect(entry.kilocalories == 470)
        #expect(entry.macros == MacroTotals(protein: 34, carbs: 28, fat: 23))
        #expect(entry.isFavourite)
        #expect(entry.source == .photo)
        #expect(entry.items.map(\.name) == ["Salmon fillet, pan-fried", "Leaf spinach"])
        #expect(entry.items.map(\.kilocalories) == [240, 70])
        #expect(entry.items.map(\.note) == [
            .photo(confidence: .confident, approximateGrams: 150),
            .photo(confidence: .unsure, approximateGrams: 90),
        ])
    }

    @Test("a label the user picked survives the commit as theirs")
    func commitKeepsTheUsersLabel() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)), at: at(19, 20))
        await model.scanning(pixel())

        #expect(model.draft?.label == .dinner)
        model.cycleLabel()
        #expect(model.commit())

        let entry = try #require(try store.entries(on: at(19, 20)).first)
        #expect(entry.label == .breakfast)
        #expect(entry.isLabelUserSet)
    }

    @Test("a label the user left alone is the store's to derive")
    func commitLeavesADerivedLabelAlone() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)), at: at(19, 20))
        await model.scanning(pixel())

        #expect(model.commit())

        let entry = try #require(try store.entries(on: at(19, 20)).first)
        #expect(entry.label == .dinner)
        #expect(!entry.isLabelUserSet)
    }

    @Test("committing returns to the viewfinder and lets the frame go")
    func commitClearsTheScan() async throws {
        let model = makeModel(store: try makeStore(), client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        #expect(model.commit())

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        #expect(model.photo == nil)
    }

    @Test("walking away from a result writes nothing")
    func discardWritesNothing() async throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))
        await model.scanning(pixel())

        model.discard()

        #expect(model.stage == .viewfinder)
        #expect(model.draft == nil)
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }

    @Test("a commit with nothing to commit reports failure rather than writing")
    func commitWithoutADraft() throws {
        let store = try makeStore()
        let model = makeModel(store: store, client: ScriptedClient(answer: .success(Self.estimate)))

        #expect(!model.commit())
        #expect(try store.entries(on: at(19, 20)).isEmpty)
    }
}

// MARK: - Driving a scan

private extension CameraLogModel {

    /// Starts a scan and waits for it to settle.
    ///
    /// `analyse` deliberately returns before the request does — the interface
    /// has to draw the first analysis step immediately — so a test needs a way
    /// to wait. Polling the stage rather than exposing the task keeps the
    /// production type free of a hook that exists only for tests.
    func scanning(_ image: UIImage) async {
        analyse(image)
        while case .analysing = stage {
            await Task.yield()
        }
    }
}

// MARK: - Stand-ins

/// Answers one estimate, from memory, and counts how often it was asked.
///
/// The count is the point of `noKeyDisablesTheTab`: a disabled tab that still
/// sent the request would pass a test that only looked at the stage.
private final class ScriptedClient: AIClient, @unchecked Sendable {

    let provider: AIProvider = .claude

    private let answer: Result<MealEstimate, AIError>
    private(set) var requests = 0

    init(answer: Result<MealEstimate, AIError>) {
        self.answer = answer
    }

    func checkKey(_ key: APIKey) async -> KeyCheckResult { .passed }

    func estimate(photo: MealPhoto) async throws -> MealEstimate {
        requests += 1
        return try answer.get()
    }

    func estimate(text: String) async throws -> MealEstimate {
        requests += 1
        return try answer.get()
    }
}

/// No key for any provider.
private struct NoKeys: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { false }
}

/// A key for every provider.
private struct StoredKey: MealKeyPresence {

    func hasKey(for provider: AIProvider) -> Bool { true }
}

/// A key that can be added or taken away between two questions, which is what
/// Settings does while the app is running.
private final class MutableKeys: MealKeyPresence, @unchecked Sendable {

    var hasKey: Bool

    init(hasKey: Bool) {
        self.hasKey = hasKey
    }

    func hasKey(for provider: AIProvider) -> Bool { hasKey }
}

/// A camera that hands back the smallest possible frame.
@MainActor
private final class StubCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage { pixel() }
}

/// A camera that fires and delivers nothing.
@MainActor
private final class FailingCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage {
        throw MealCameraError.captureFailed
    }
}

/// One opaque pixel.
///
/// Small enough that `MealPhotoCompressor` passes it through untouched, so the
/// tests are about the flow rather than about compression, which has its own
/// suite.
@MainActor
private func pixel() -> UIImage {
    let size = CGSize(width: 1, height: 1)
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        context.fill(CGRect(origin: .zero, size: size))
    }
}

// MARK: - Hatch

/// The direction the hatch's bands run.
///
/// It has its own suite because it is the one thing about `PhotoHatch` a reader
/// cannot check by eye in a diff: the angle, the band and the two tones are all
/// correct transcriptions of the export whichever way the bands are stacked,
/// and stacking them the wrong way turns the whole hatch a quarter turn while
/// leaving every number in the file right. That is a mistake a review cannot
/// see, so it is pinned here instead.
@Suite("Hatch")
@MainActor
struct PhotoHatchTests {

    /// Edge of every rendering below. Several band periods across, so a
    /// direction has something to be measured against.
    private static let edge: CGFloat = 80

    /// How far a sample is taken from its neighbour, on both axes at once.
    ///
    /// `band / √2` on each axis is one whole band width along the hatch's
    /// normal, which is the shift that lands squarely in the neighbouring
    /// stripe. Rounded to whole pixels so no sample needs interpolating.
    private static var step: Int {
        Int((FuelMetrics.Hatch.band / 2.0.squareRoot()).rounded())
    }

    @Test("the bands run bottom-left to top-right, as the export draws them")
    func bandsRunAlongTheDrawnDiagonal() throws {
        let hatch = try #require(
            render(PhotoHatch(base: .black, stripe: .white))
        )

        let downRight = meanDifference(in: hatch, dx: Self.step, dy: Self.step)
        let upRight = meanDifference(in: hatch, dx: Self.step, dy: -Self.step)

        // The buffer's row order relative to the view's is a property of the
        // drawing pipeline, not something to assume. A plain top-to-bottom
        // gradient rendered the same way answers it outright.
        let topDown = try #require(bufferRunsTopDown())

        // In view coordinates a "/" band runs (1, -1): x rises as y falls. A
        // flipped buffer swaps which measured diagonal that is.
        let alongTheBand = topDown ? upRight : downRight
        let acrossTheBands = topDown ? downRight : upRight

        #expect(alongTheBand < acrossTheBands)
        // Not merely smaller — a uniform fill would satisfy that. The bands
        // have to actually be there.
        #expect(acrossTheBands > 64)
        #expect(alongTheBand < 8)
    }

    // MARK: - Measuring

    /// Mean absolute difference between each pixel and the one `dx`, `dy` away.
    private func meanDifference(in image: GrayImage, dx: Int, dy: Int) -> Double {
        var total = 0.0
        var count = 0
        for y in 0..<image.height where y + dy >= 0 && y + dy < image.height {
            for x in 0..<image.width where x + dx >= 0 && x + dx < image.width {
                let here = Double(image[x, y])
                let there = Double(image[x + dx, y + dy])
                total += abs(here - there)
                count += 1
            }
        }
        return count == 0 ? 0 : total / Double(count)
    }

    /// Whether row zero of a rendered buffer is the top of the view.
    ///
    /// Measured rather than assumed, through the same renderer the hatch goes
    /// through, so whatever the pipeline does to one it does to the other.
    private func bufferRunsTopDown() -> Bool? {
        let gradient = LinearGradient(
            colors: [.black, .white],
            startPoint: .top,
            endPoint: .bottom
        )
        guard let image = render(gradient) else { return nil }

        var firstRow = 0.0
        var lastRow = 0.0
        for x in 0..<image.width {
            firstRow += Double(image[x, 0])
            lastRow += Double(image[x, image.height - 1])
        }
        return firstRow < lastRow
    }

    /// Renders a view to an 8-bit grey buffer at scale 1.
    private func render(_ content: some View) -> GrayImage? {
        let renderer = ImageRenderer(
            content: content.frame(width: Self.edge, height: Self.edge)
        )
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)
        pixels.withUnsafeMutableBytes { buffer in
            guard
                let base = buffer.baseAddress,
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width,
                    space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGImageAlphaInfo.none.rawValue
                )
            else {
                return
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return GrayImage(pixels: pixels, width: width, height: height)
    }
}

/// An 8-bit grey rendering, addressed by column and row.
private struct GrayImage {

    let pixels: [UInt8]
    let width: Int
    let height: Int

    subscript(x: Int, y: Int) -> UInt8 {
        pixels[y * width + x]
    }
}

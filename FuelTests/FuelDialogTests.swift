import SwiftUI
import Testing
import UIKit

@testable import Fuel

// MARK: - Reaching into what came up

/// The parts of a dialog a test can get hold of once it is on the screen.
///
/// **Everything here is measured, and none of it is pressed.** A SwiftUI
/// control cannot be activated in process: the hosting view publishes no
/// accessibility elements while no assistive technology is attached — measured,
/// `accessibilityElementCount()` is zero on every view of a hosted screen — and
/// there is no public way to hand it a touch. So what these suites prove about
/// a button is what it draws and where, and what they prove about an answer is
/// proved by running the answer. The field is the exception, and it is a real
/// one: a `TextField` is backed by a `UITextView` that is in the hierarchy and
/// takes text through `UITextInput`, so what the user types can actually be
/// typed.
@MainActor
extension HostedScreen {

    /// The sheet standing over the screen, if one is up.
    var sheet: UIView? {
        window.rootViewController?.presentedViewController?.view
    }

    /// The field the sheet has up, for a test that has to type into it.
    var editor: UITextView? {
        guard let sheet else { return nil }
        return Self.textView(in: sheet)
    }

    private static func textView(in view: UIView) -> UITextView? {
        if let found = view as? UITextView { return found }
        for subview in view.subviews {
            if let found = textView(in: subview) { return found }
        }
        return nil
    }
}

// MARK: - Words on the screen

/// Where a drawing has something on it, read as bands and runs rather than as
/// one box.
///
/// **This is what it takes to assert that a word reached the screen.** A colour
/// box says a pill was filled; it says nothing about what is written on it, and
/// three separate mutations of `FuelDialog` — dropping the title, dropping the
/// line under it, and putting the wrong one of the two words on the filled pill
/// so it reads `Keep` and deletes — passed every test in this file while it was
/// only reading boxes. Text cannot be read back from pixels, but its extent
/// can: a longer word is a wider run, and a second paragraph is a second band.
/// Both change when the wrong string is drawn, and neither changes when the
/// right one is.
@MainActor
extension DrawnPixels {

    /// The bands of rows in `region` that have anything drawn on them, top
    /// first. A line of text is one band; a title over a hint is two.
    func bands(over ground: Channels, in region: CGRect) -> [Range<Int>] {
        var found: [Range<Int>] = []
        var start: Int?
        for y in Int(region.minY)..<Int(region.maxY) {
            let inked = peakDeviation(fromColour: ground, y: y, x: Int(region.minX)..<Int(region.maxX)) > Self.tolerance
            switch (inked, start) {
            case (true, nil):
                start = y
            case (false, .some(let from)):
                found.append(from..<y)
                start = nil
            default:
                break
            }
        }
        if let start { found.append(start..<Int(region.maxY)) }
        return found
    }

    /// The tightest column range in `region` with anything drawn in it, or
    /// nothing where the region is empty.
    func inked(over ground: Channels, in region: CGRect) -> Range<Int>? {
        var first: Int?
        var last: Int?
        for x in Int(region.minX)..<Int(region.maxX) {
            let inked = (Int(region.minY)..<Int(region.maxY)).contains { y in
                deviation(fromColour: ground, x: x, y: y) > Self.tolerance
            }
            guard inked else { continue }
            first = first ?? x
            last = x
        }
        guard let first, let last else { return nil }
        return first..<(last + 1)
    }

    /// The longest run of columns painted solidly in `colour` on one row.
    ///
    /// A fill and a label are the same colour on the mono accent, where the
    /// accent *is* the ink — so nothing that only asks "is this colour on the
    /// screen" can tell the filled pill from the words above it. A solid run
    /// can: a pill is painted across its whole width and a letter is not.
    func solidRun(ofColour colour: Channels, y: Int, x range: Range<Int>) -> Int {
        var longest = 0
        var run = 0
        for x in range {
            if deviation(fromColour: colour, x: x, y: y) <= Self.tolerance {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }
}

/// Whether a question is up, held outside the screen that raises it so a test
/// can raise it the way a tap does — after the screen underneath has been laid
/// out — rather than at the same instant the screen is built.
@MainActor
@Observable
final class DialogPresentation {
    var isUp = false
}

// MARK: - Nothing asks in the platform's words

/// The one dialog rule, swept over the app: no screen in Fuel raises a question
/// in iOS's own drawing.
///
/// **A sweep rather than four tests, for the reason `FuelMetrics.allDrawnValues`
/// is a roster.** Pinning the four call sites that were replaced proves nothing
/// about the fifth; what is being kept out is a whole mechanism, and the only
/// way to keep one out is to look everywhere every time.
///
/// **A view's own structure, not its source.** `some View` resolves to a
/// concrete type that names every modifier applied inside the body, so a screen
/// that raises a system dialog carries `AlertModifier` or
/// `ConfirmationDialogModifier` in the name of its `Body` and one that raises
/// Fuel's carries `FuelDialogModifier`. Reading it off the type needs no
/// fixture, no render and no instance — which also means it cannot trip over a
/// screen whose model is expensive to build.
///
/// Reading the source instead was the first attempt and cannot work from here:
/// the test host runs in the simulator and macOS refuses it the repository at
/// all when the repository is under `~/Desktop` — `NSCocoaErrorDomain 257`,
/// "you don't have permission to view it".
///
/// What the sweep cannot see is a `private` view's body, since a name it cannot
/// write is a type it cannot ask about. Every screen that presents anything is
/// public to the module and is on the list below.
@Suite("Dialog · nothing asks in the platform's words")
@MainActor
struct FuelDialogSweepTests {

    /// Every screen in the app that owns a body a dialog could be raised from.
    private static let screens: [(name: String, body: Any.Type)] = [
        ("RootShell", RootShell.Body.self),
        ("TodayView", TodayView.Body.self),
        ("TodaySummaryView", TodaySummaryView.Body.self),
        ("TodayDayList", TodayDayList.Body.self),
        ("TodayGettingStartedView", TodayGettingStartedView.Body.self),
        ("SettingsScreen", SettingsScreen.Body.self),
        ("AIModelSection", AIModelSection.Body.self),
        ("AppearanceSection", AppearanceSection.Body.self),
        ("AccentSection", AccentSection.Body.self),
        ("CountingSection", CountingSection.Body.self),
        ("AutomaticLabelsSection", AutomaticLabelsSection.Body.self),
        ("OnboardingFlow", OnboardingFlow.Body.self),
        ("APIKeyScreen", APIKeyScreen.Body.self),
        ("KeyTestScreen", KeyTestScreen.Body.self),
        ("GoalScreen", GoalScreen.Body.self),
        ("LogFlowView", LogFlowView.Body.self),
        ("CameraTabView", CameraTabView.Body.self),
        ("TextTabView", TextTabView.Body.self),
        ("RecentMealsView", RecentMealsView.Body.self),
        ("AnalysisView", AnalysisView.Body.self),
        ("AnalysisFailureView", AnalysisFailureView.Body.self),
        ("MealDetailView", MealDetailView.Body.self),
        ("MealChatSheet", MealChatSheet.Body.self),
        ("MealResultView", MealResultView<MealPhotoLede>.Body.self),
        ("PhotoResultView", PhotoResultView.Body.self),
        ("TextResultView", TextResultView.Body.self),
    ]

    @Test("no screen in Fuel raises a system dialog")
    func noSystemDialogs() {
        let platformsOwn = ["AlertModifier", "ConfirmationDialogModifier"]
        let asking = Self.screens.filter { screen in
            let structure = String(describing: screen.body)
            return platformsOwn.contains { structure.contains($0) }
        }

        #expect(asking.map(\.name) == [])
    }

    /// The other half of the same claim: the four questions the app asks are
    /// still asked, on the three screens that ask them.
    @Test("every question the app asks is Fuel's own", arguments: [
        ("MealDetailView", 1),
        ("MealResultView", 2),
        ("RootShell", 1),
    ])
    func questionsAreFuelsOwn(_ screen: String, _ expected: Int) throws {
        let body = try #require(Self.screens.first { $0.name == screen }?.body)
        let structure = String(describing: body)
        let raised = structure.components(separatedBy: "FuelDialogModifier").count - 1

        #expect(raised == expected, "\(screen) raises \(raised) of its own questions")
    }
}

// MARK: - Which answer was taken

/// The decision behind the app's only irreversible action, run without a
/// screen.
///
/// **A thin test of a `guard`, and deliberately so.** What is worth pinning is
/// not the branch — a `Bool` read is not where a bug hides — but the order:
/// the flag goes down *before* the answer is handed back, so a question
/// answered once cannot answer again. Left standing, it would make the next
/// dismissal of the next question raised from the same screen report a press
/// nobody made, and on the meal screen what that runs is a delete.
///
/// It is here rather than inside the modifier because inside the modifier it
/// could not be run at all: a sheet's dismissal transition never completes in a
/// test host — driven four ways, every route reported the sheet still up and
/// neither branch reached — so assertions about it passed by never happening.
@Suite("Dialog · which answer was taken")
struct FuelDialogAnswerTests {

    @Test("the confirm button's flag is the only thing that goes ahead")
    func confirmGoesAhead() {
        var confirmed = true

        #expect(FuelDialogAnswer.taken(from: &confirmed) == .wentAhead)
    }

    @Test("every other way out changes nothing")
    func everythingElseCancels() {
        var confirmed = false

        #expect(FuelDialogAnswer.taken(from: &confirmed) == .changedNothing)
        #expect(confirmed == false)
    }

    /// The one that matters: a question answered once does not answer again.
    @Test("a question that went ahead does not go ahead a second time")
    func theFlagGoesDownOnTheWayPast() {
        var confirmed = true

        #expect(FuelDialogAnswer.taken(from: &confirmed) == .wentAhead)
        #expect(confirmed == false, "the flag was left standing")
        #expect(FuelDialogAnswer.taken(from: &confirmed) == .changedNothing)
    }
}

// MARK: - What a dialog draws

/// The dialog Fuel asks its questions on: the words it puts on the screen and
/// where it stands.
///
/// **Rendered rather than asserted, for the reason `MealResultFooterTests`
/// gives.** That `FuelDialogCopy` holds the strings it was handed is not a
/// claim worth a test. That the question is drawn, that the line under it is
/// drawn only when there is one, that the answer that destroys something is
/// drawn apart from the one that does not, and that each word is on the pill it
/// belongs to — none of that is visible in a constant, and all of it is what
/// this branch claims.
@Suite("Dialog · what it draws", .serialized)
@MainActor
struct FuelDialogDrawingTests {

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    /// The delete question's own shape: one sentence, a destructive verb, and
    /// a way out.
    private static func question(
        title: String = "Do you really want to delete this entry?",
        hint: String? = nil,
        confirm: String = "Delete",
        cancel: String = "Keep",
        destroys: Bool = true
    ) -> FuelDialogCopy {
        FuelDialogCopy(title: title, hint: hint, confirm: confirm, cancel: cancel, destroys: destroys)
    }

    // MARK: - Hosting

    private func hosted(_ copy: FuelDialogCopy, palette: FuelPalette = palette) throws -> Drawn {
        let screen = try HostedScreen(
            FuelDialog(copy: copy, entry: nil, onConfirm: {}, onCancel: {})
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                // The ground under the whole window, safe areas included, and
                // the dialog standing on the window's own bottom edge. Both
                // matter to a scan: what these call ink is anything that is not
                // the ground, so the hosting controller's own white showing
                // through at the top would read as a line of text, and a
                // dialog held off the bottom by the home indicator's strip puts
                // its answers where the scans below do not look for them.
                .background(palette.background)
                .ignoresSafeArea(),
            palette: palette
        )
        let drawing = try #require(screen.drawing)
        return Drawn(pixels: drawing, palette: palette, size: screen.window.bounds.size)
    }

    /// One rendered dialog, with the regions its parts stand in.
    private struct Drawn {

        let pixels: DrawnPixels

        let palette: FuelPalette

        let size: CGSize

        var ground: DrawnPixels.Channels { DrawnPixels.Channels(palette.background) }

        /// The band the answer row stands in.
        ///
        /// **The lowest band with anything drawn on it**, rather than a region
        /// measured down from the bottom of the screen. The answers are the last
        /// thing on the dialog, so the lowest band is always them — while a
        /// region guessed at a hundred points tall reached the question's own
        /// descenders on a short dialog, and then reported the answer row as
        /// starting at the bottom of the title.
        func answerRow() throws -> CGRect {
            let whole = CGRect(origin: .zero, size: size)
            let band = try #require(pixels.bands(over: ground, in: whole).last)
            return CGRect(
                x: 0,
                y: CGFloat(band.lowerBound),
                width: size.width,
                height: CGFloat(band.count)
            )
        }

        /// The filled pill, which is the one thing on that row painted in a
        /// colour of its own.
        ///
        /// Searched inside the row rather than the screen: on the mono accent
        /// the fill *is* the ink, and a scan of the whole drawing would find the
        /// question's own letters as well.
        func answers() throws -> DrawnPixels.Box {
            try #require(
                pixels.box(ofColour: DrawnPixels.Channels(palette.accentColor), in: try answerRow())
            )
        }

        /// Everything above the answer row, which is the question and the line
        /// under it where there is one.
        func aboveTheAnswers() throws -> CGRect {
            CGRect(x: 0, y: 0, width: size.width, height: try answerRow().minY)
        }
    }

    // MARK: - The words

    /// The question is drawn, at the inset every body of a screen sits in, and
    /// what is drawn is the question rather than something the same size.
    @Test("the question is on the screen, and it is the question that was asked")
    func theQuestionIsDrawn() throws {
        let short = try hosted(Self.question(title: "Delete?"))
        let long = try hosted(Self.question(title: "Delete this?"))

        let shortBands = short.pixels.bands(over: short.ground, in: try short.aboveTheAnswers())
        #expect(shortBands.count == 1, "the question drew \(shortBands.count) lines")

        let shortInk = try #require(short.pixels.inked(over: short.ground, in: try short.aboveTheAnswers()))
        let longInk = try #require(long.pixels.inked(over: long.ground, in: try long.aboveTheAnswers()))

        expect(shortInk.lowerBound, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        #expect(
            longInk.count > shortInk.count,
            "a longer question drew \(longInk.count) points against \(shortInk.count)"
        )
    }

    /// The line under the question is drawn where there is one and nothing
    /// stands there where there is not — which is the difference between the
    /// delete question, one sentence by the owner's ruling, and the item field,
    /// which says how to fill itself in.
    @Test("the line under the question is drawn only when the question has one")
    func theLineUnderTheQuestion() throws {
        let alone = try hosted(Self.question())
        let withLine = try hosted(Self.question(hint: "Write the item as you would say it."))

        let aloneBands = alone.pixels.bands(over: alone.ground, in: try alone.aboveTheAnswers())
        let withLineBands = withLine.pixels.bands(over: withLine.ground, in: try withLine.aboveTheAnswers())

        #expect(withLineBands.count == aloneBands.count + 1, "a hint added \(withLineBands.count - aloneBands.count) bands")
    }

    /// The word on the filled pill is the way out, not the verb that goes
    /// ahead — which is the whole of the owner's ruling on emphasis, and the
    /// difference between a pill that reads `Keep` and one that reads `Keep`
    /// and deletes.
    @Test("the filled answer carries the way out")
    func theFilledAnswerCarriesTheWayOut() throws {
        let plain = try hosted(Self.question())
        let longerWayOut = try hosted(Self.question(cancel: "Keep this entry"))
        let longerVerb = try hosted(Self.question(confirm: "Delete this entry"))

        #expect(
            try label(inTheFilledPillOf: longerWayOut) > label(inTheFilledPillOf: plain),
            "a longer way out did not widen the label on the filled pill"
        )
        #expect(
            try label(inTheFilledPillOf: longerVerb) == label(inTheFilledPillOf: plain),
            "a longer destructive verb changed the label on the filled pill"
        )
    }

    /// And the verb that goes ahead is on the pill that hugs it, which is the
    /// other half of the same claim: it grows with its own word and not with
    /// the other one.
    @Test("the answer that goes ahead hugs its own label")
    func theVerbHugsItsLabel() throws {
        let plain = try hosted(Self.question())
        let longerVerb = try hosted(Self.question(confirm: "Delete this entry"))
        let longerWayOut = try hosted(Self.question(cancel: "Keep this entry"))

        // The hugging pill stands at the trailing end, so the filled pill's
        // right-hand inset is what its width costs.
        #expect(
            try longerVerb.answers().right > plain.answers().right,
            "a longer destructive verb did not widen the pill that hugs it"
        )
        #expect(
            try longerWayOut.answers().right == plain.answers().right,
            "a longer way out widened the pill that hugs the other word"
        )
    }

    /// How wide the label on the filled pill is drawn, measured against the
    /// fill it sits on.
    ///
    /// Read across the middle of the pill rather than the whole of it: a
    /// `Radius.pill` end is a semicircle, so near the top and bottom rows the
    /// fill does not reach the pill's own edges and every column there would
    /// count as something drawn on it. Across the middle the fill is solid from
    /// end to end and the only thing interrupting it is the word.
    private func label(inTheFilledPillOf drawn: Drawn) throws -> Int {
        let box = try drawn.answers()
        let row = try drawn.answerRow()
        let middle = CGRect(
            x: CGFloat(box.left) + 2,
            y: row.midY - 8,
            width: drawn.size.width - CGFloat(box.right) - CGFloat(box.left) - 4,
            height: 16
        )
        let ink = try #require(drawn.pixels.inked(over: DrawnPixels.Channels(drawn.palette.accentColor), in: middle))
        return ink.count
    }

    // MARK: - The destructive treatment

    /// The verb that destroys something is drawn in the one colour the design
    /// system keeps for a state gone wrong, and it is the only thing on the
    /// dialog drawn in it.
    @Test("the destructive verb is drawn in the error ink")
    func theDestructiveVerbIsDrawnInTheErrorInk() throws {
        let drawn = try hosted(Self.question())
        let row = try drawn.answerRow()
        let box = try drawn.answers()

        let error = try #require(
            drawn.pixels.box(ofColour: DrawnPixels.Channels(drawn.palette.error)),
            "nothing on the dialog is drawn in the error ink"
        )

        #expect(CGFloat(error.top) >= row.minY, "the error ink is drawn above the answer row")
        #expect(
            error.left > Int(drawn.size.width) - box.right,
            "the error ink is not on the trailing pill"
        )
    }

    /// A question that destroys nothing draws none of it — the item field's
    /// `Done` is not a warning.
    @Test("a question that destroys nothing draws no error ink")
    func aHarmlessQuestionDrawsNoErrorInk() throws {
        let drawn = try hosted(
            Self.question(title: "Item", confirm: "Done", cancel: "Cancel", destroys: false)
        )

        #expect(drawn.pixels.box(ofColour: DrawnPixels.Channels(drawn.palette.error)) == nil)
    }

    /// And it puts its weight the other way round: the filled pill carries the
    /// answer that goes ahead when going ahead only writes something down.
    @Test("a question that destroys nothing fills the answer that goes ahead")
    func aHarmlessQuestionFillsTheAnswerThatGoesAhead() throws {
        let plain = try hosted(Self.question(title: "Item", confirm: "Done", cancel: "Cancel", destroys: false))
        let longerVerb = try hosted(Self.question(title: "Item", confirm: "Done with it", cancel: "Cancel", destroys: false))

        #expect(
            try label(inTheFilledPillOf: longerVerb) > label(inTheFilledPillOf: plain),
            "the filled pill does not carry the answer that goes ahead"
        )
    }

    // MARK: - The pair's geometry

    /// The filled pill stands at the drawn inset on the side the way out keeps.
    @Test("the filled answer stands at the drawn inset")
    func theFilledAnswerStandsAtTheDrawnInset() throws {
        let drawn = try hosted(Self.question())

        expect(try drawn.answers().left, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
    }

    /// `s17` above and below `buttonLabel` is already past a fingertip — but
    /// this row is what an irreversible action is answered on, so the floor is
    /// measured rather than reasoned about.
    @Test("the answers answer a finger")
    func answersAnswerAFinger() throws {
        let drawn = try hosted(Self.question())
        let height = try drawn.answerRow().height

        #expect(height >= FuelMetrics.Control.minimumHitTarget, "the answer row is \(height) tall")
    }

    /// The question at a text size a user with poor sight actually sets.
    ///
    /// **What a fixed panel height would break first is the clearance under the
    /// answers**, and that is asked of the card in
    /// `FuelDialogPresentationTests.aLongerQuestionGrowsTheCard`, because a
    /// text size set in the environment does not reach a sheet in a test host.
    /// What this asks is the half that does apply here: the answers stay whole,
    /// stay at the drawn inset, and stay on the screen when everything around
    /// them grows.
    @Test("the answers survive a larger text size")
    func theAnswersSurviveALargerTextSize() throws {
        let screen = try HostedScreen(
            FuelDialog(copy: Self.question(), entry: nil, onConfirm: {}, onCancel: {})
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .background(Self.palette.background)
                .ignoresSafeArea()
                .dynamicTypeSize(.accessibility3),
            palette: Self.palette
        )
        let pixels = try #require(screen.drawing)
        let drawn = Drawn(pixels: pixels, palette: Self.palette, size: screen.window.bounds.size)

        expect(try drawn.answers().left, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        #expect(try drawn.answerRow().minY > 0, "the answers are drawn off the top of the screen")
        #expect(try drawn.answerRow().height >= FuelMetrics.Control.minimumHitTarget)
    }

    /// Every accent and both themes.
    ///
    /// **A solid run rather than a box**, because on mono the accent is the ink
    /// and a box would find the question's own letters. What this asks is that
    /// a pill's worth of the accent is painted across the row without a break,
    /// which no line of text does.
    @Test("the filled answer is painted in every accent", arguments: FuelAccent.allCases)
    func everyAccent(_ accent: FuelAccent) throws {
        for theme in FuelTheme.allCases {
            let palette = FuelPalette(theme: theme, accent: accent)
            let drawn = try hosted(Self.question(), palette: palette)
            let row = try drawn.answerRow()
            let run = drawn.pixels.solidRun(
                ofColour: DrawnPixels.Channels(palette.accentColor),
                y: Int(row.midY),
                x: 0..<Int(drawn.size.width)
            )

            #expect(
                CGFloat(run) > FuelMetrics.Control.minimumHitTarget,
                "\(accent) on \(theme) painted a run of \(run)"
            )
        }
    }
}

// MARK: - What a dialog does coming up

/// The dialog as it is actually raised: over a screen, on the sheet the chat
/// already uses.
///
/// What this suite asks that the drawing suite cannot — that it comes up at
/// all, that it is as tall as its question rather than as tall as the screen,
/// that it is that tall from the first frame rather than growing under the
/// user's finger, that its answers clear the home indicator at any text size,
/// and that its field is the one the user types into.
///
/// **One thing about a sheet cannot be asked here, and it was tried four
/// ways.** Its dismissal transition never finishes in a test host: a sheet put
/// away by the binding it was raised with stalls mid-animation with the spring
/// still attached after three seconds of run loop. What runs when the user
/// swipes it down is therefore pinned in `FuelDialogAnswerTests`, on the value
/// the decision was moved into, rather than here.
@Suite("Dialog · coming up over a screen", .serialized)
@MainActor
struct FuelDialogPresentationTests {

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    private static let question = FuelDialogCopy(
        title: "Do you really want to delete this entry?",
        confirm: "Delete",
        cancel: "Keep",
        destroys: true
    )

    private static let itemField = FuelDialogCopy(
        title: "Item",
        hint: "Write the item as you would say it, with the amount if you know it.",
        confirm: "Done",
        cancel: "Cancel",
        destroys: false
    )

    @Test("the question comes up over the screen")
    func itComesUp() throws {
        let screen = try raise(Self.question)

        #expect(screen.sheet != nil)
    }

    /// Raises a question the way a control does: over a screen that is already
    /// on the window and has already been laid out.
    ///
    /// **Which is not the same thing as a screen built with its question
    /// already up**, and the difference is the whole of the test below this
    /// one. A dialog raised in the same update that builds the screen is raised
    /// before anything has reported how wide that screen is, so it cannot be
    /// opened at the height its question will need. Nothing in the app does
    /// that: a question arrives on a tap, which is a great many frames after
    /// the screen it is tapped on was laid out.
    private func raise(
        _ copy: FuelDialogCopy,
        wantsField: Bool = false,
        typing: Typing? = nil,
        textSize: DynamicTypeSize = .large
    ) throws -> HostedScreen {
        let presentation = DialogPresentation()
        let screen = try HostedScreen(
            DialogHost(copy: copy, wantsField: wantsField, typing: typing, presentation: presentation)
                .dynamicTypeSize(textSize),
            palette: Self.palette
        )
        presentation.isUp = true
        screen.settle(for: 0.6)
        return screen
    }

    /// A question is as tall as the question. Nothing in the export draws a
    /// height for one, so the sheet is fitted to what it says — and the two
    /// dialogs this app raises are different heights, which is the whole claim.
    ///
    /// `presentationSizing(.fitted)` is the API for this and iOS does not apply
    /// it to a sheet on a phone: with it, both of these came up 812 points tall
    /// on an 874-point screen.
    @Test("it is as tall as what it says, not as tall as the screen")
    func itIsFittedToItsQuestion() throws {
        let plain = try raise(Self.question)
        let plainHeight = try #require(plain.sheet).frame.height

        let withField = try raise(Self.itemField, wantsField: true)
        let fieldHeight = try #require(withField.sheet).frame.height

        #expect(plainHeight < plain.window.bounds.height / 2, "the question came up \(plainHeight) tall")
        #expect(fieldHeight > plainHeight, "a question with a field in it is no taller than one without")
    }

    /// **The height it opens at is the height it stays at.**
    ///
    /// The detent is measured from the question, and a measurement does not
    /// exist until the question has been laid out once — so the first raise
    /// opens at `FuelDialog.shortestQuestion` plus the strip the home indicator
    /// takes. If that seed is not what the question actually measures, the
    /// sheet corrects itself a frame later and every answer on it moves. It is
    /// not a first-run cost: `MealDetailView` is built again on every push, so
    /// it would be what a user sees every time they open a meal and reach for
    /// the trash mark.
    @Test("the height it opens at is the height it settles at")
    func theSeedIsTheSettledHeight() throws {
        let screen = try raise(Self.question)
        let settled = try #require(screen.sheet).frame.height
        let seed = FuelDialog.seed(
            for: Self.question,
            entry: nil,
            on: FuelDialogGround(width: screen.window.bounds.width, inset: screen.window.safeAreaInsets.bottom),
            palette: Self.palette,
            textSize: .large
        )

        #expect(abs(settled - seed) <= 1, "it opens at \(seed) and settles at \(settled)")
    }

    /// The answers stand their own `s18` above the safe area, and the safe area
    /// stands clear of the home indicator — the drawn distance spent once
    /// rather than twice.
    ///
    /// Measured against the card's own bottom edge rather than the screen's,
    /// because the card floats: what the sheet is inset by is the system's and
    /// is not a number this app has any business pinning.
    @Test("the answers clear the home indicator by their own padding")
    func answersClearTheIndicator() throws {
        let screen = try raise(Self.question)

        try expectAnswersClearTheIndicator(on: screen)
    }

    /// A longer question makes a taller card, and its answers still stand
    /// where they are drawn against the card's own bottom edge — which is where
    /// a panel with a height written into it would fail first.
    ///
    /// A longer question rather than a larger text size, and the difference is
    /// the harness rather than the app: a text size set in the environment does
    /// not reach a sheet's own hierarchy in a test host — measured, the card
    /// came up the same 206.67 points at `.accessibility3` as at the default —
    /// because a presented controller takes that from the window's traits.
    /// `FuelDialogDrawingTests.theAnswersSurviveALargerTextSize` asks the type
    /// question where the environment does apply.
    @Test("a longer question makes a taller card without moving its answers")
    func aLongerQuestionGrowsTheCard() throws {
        let ordinary = try raise(Self.question)
        let ordinaryHeight = try #require(ordinary.sheet).frame.height

        let longer = try raise(
            FuelDialogCopy(
                title: "Do you really want to delete this entry, and everything the model wrote down about it?",
                confirm: "Delete",
                cancel: "Keep",
                destroys: true
            )
        )
        let longerHeight = try #require(longer.sheet).frame.height

        #expect(longerHeight > ordinaryHeight, "the card did not grow: \(longerHeight) against \(ordinaryHeight)")
        try expectAnswersClearTheIndicator(on: longer)
    }

    private func expectAnswersClearTheIndicator(
        on screen: HostedScreen,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let drawing = try #require(screen.drawing)
        // The card is the only place the theme's own background is drawn at
        // full strength: everything behind it is under the system's dimming.
        let card = try #require(drawing.box(ofColour: DrawnPixels.Channels(Self.palette.background)))
        let pill = try #require(drawing.box(ofColour: DrawnPixels.Channels(Self.palette.accentColor)))

        // Two points of slack rather than the usual one, and for the usual
        // reason twice over: this is the distance between two curved edges, and
        // a scan reports the last fully painted pixel of each. The mistake it
        // exists to catch is the safe area spent twice, which is 34 wide.
        let measured = CGFloat(pill.bottom - card.bottom)
        let drawn = FuelMetrics.Space.s18 + screen.window.safeAreaInsets.bottom
        #expect(
            abs(measured - drawn) <= 2,
            "measured \(measured) against a drawn \(drawn)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - The field

    /// The field is the one the user types into: what goes into the text view
    /// on the screen comes out of the binding the caller handed in.
    @Test("what is typed into the field is what the caller is given")
    func theFieldWritesBack() throws {
        let typing = Typing()
        let screen = try raise(Self.itemField, wantsField: true, typing: typing)
        let editor = try #require(screen.editor)

        editor.insertText("Polenta 150 g")
        screen.settle()

        #expect(typing.text == "Polenta 150 g")
    }

    /// The field sits in the inset the export puts every body of a screen in,
    /// like everything else on the dialog.
    @Test("the field stands at the drawn inset")
    func theFieldStandsAtTheDrawnInset() throws {
        let screen = try raise(Self.itemField, wantsField: true)
        let editor = try #require(screen.editor)
        let sheet = try #require(screen.sheet)
        let inset = editor.convert(editor.bounds, to: sheet).minX

        expect(Int(inset), isTheDrawn: FuelMetrics.Screen.horizontalPadding)
    }

    // MARK: - Fixtures

    @MainActor
    private final class Typing {
        var text = ""
    }

    /// The smallest screen that can raise a dialog: a ground, and the question
    /// over it.
    @MainActor
    private struct DialogHost: View {

        let copy: FuelDialogCopy

        var wantsField = false

        var typing: Typing?

        let presentation: DialogPresentation

        @Environment(\.fuelPalette) private var palette

        @State private var text = ""

        var body: some View {
            palette.background
                .ignoresSafeArea()
                .fuelDialog(
                    copy,
                    isPresented: raised,
                    entry: wantsField ? FuelDialogEntry(text: written, prompt: "Polenta 150 g", accessibilityLabel: "Item") : nil,
                    onConfirm: {}
                )
        }

        private var raised: Binding<Bool> {
            Binding(get: { presentation.isUp }, set: { presentation.isUp = $0 })
        }

        /// The caller's own binding, so a test can read what the field wrote
        /// without reaching into the view.
        private var written: Binding<String> {
            Binding(
                get: { typing?.text ?? text },
                set: { typed in
                    text = typed
                    typing?.text = typed
                }
            )
        }
    }
}

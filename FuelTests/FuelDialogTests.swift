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
/// a button is where it is drawn and how big it is, and what they prove about
/// an answer is proved by running the answer. The field is the exception, and
/// it is a real one: a `TextField` is backed by a `UITextView` that is in the
/// hierarchy and takes text through `UITextInput`, so what the user types can
/// actually be typed.
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

// MARK: - What a dialog draws

/// The dialog Fuel asks its questions on: what it puts on the screen and where
/// it stands.
///
/// **Rendered rather than asserted, for the reason `MealResultFooterTests`
/// gives.** That `FuelDialogCopy` holds the three strings it was handed is not
/// a claim worth a test. That a question drawn by this app carries an
/// accent-filled answer at the export's own inset, an outlined one hugging its
/// label beside it, and both past a fingertip, is — and none of it is visible
/// in a constant.
@Suite("Dialog · what it draws", .serialized)
@MainActor
struct FuelDialogDrawingTests {

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    private static let copy = FuelDialogCopy(
        title: "Delete this meal?",
        confirm: "Delete",
        cancel: "Keep"
    )

    private func accentBox(_ copy: FuelDialogCopy, palette: FuelPalette = palette) throws -> DrawnPixels.Box {
        let screen = try HostedScreen(dialog(copy), palette: palette)
        let drawing = try #require(screen.drawing)
        return try #require(drawing.box(ofColour: DrawnPixels.Channels(palette.accentColor)))
    }

    // MARK: - The answers

    /// The filled pill is the footer primary screens 14 and 15 draw: it takes
    /// the width that is left and stops at the drawn `28`.
    @Test("the answer that goes ahead is the accent pill, at the drawn inset")
    func confirmIsTheAccentPill() throws {
        expect(try accentBox(Self.copy).right, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
    }

    /// `s17` above and below `buttonLabel`, which is what the export draws on
    /// both pills of that footer, is already past a fingertip — but the pill is
    /// what a destructive answer is pressed on, so the floor is measured rather
    /// than reasoned about.
    @Test("the answer that goes ahead answers a finger")
    func answersAnswerAFinger() throws {
        let box = try accentBox(Self.copy)
        let height = 874 - box.bottom - box.top

        #expect(CGFloat(height) >= FuelMetrics.Control.minimumHitTarget, "the filled answer is \(height) tall")
    }

    /// The way out hugs its label on the leading side and the answer that goes
    /// ahead takes the rest, which is the only two-button row the export draws.
    ///
    /// Measured by giving the way out a longer word: an outlined pill that hugs
    /// its label pushes the filled one further along, and one that does not
    /// leaves it where it was.
    @Test("the way out hugs its label, and the answer beside it takes the rest")
    func theWayOutHugsItsLabel() throws {
        let short = try accentBox(Self.copy)
        let long = try accentBox(
            FuelDialogCopy(title: Self.copy.title, confirm: Self.copy.confirm, cancel: "Keep this meal")
        )

        #expect(CGFloat(short.left) > FuelMetrics.Screen.horizontalPadding, "nothing stands beside the filled answer")
        #expect(long.left > short.left, "the filled answer did not move for a longer word: \(long.left) against \(short.left)")
    }

    /// Every accent and both themes, because the filled answer is the one thing
    /// on a dialog that follows the user's choice.
    @Test("the filled answer follows every accent", arguments: FuelAccent.allCases)
    func everyAccent(_ accent: FuelAccent) throws {
        for theme in FuelTheme.allCases {
            let palette = FuelPalette(theme: theme, accent: accent)
            #expect(throws: Never.self) { try accentBox(Self.copy, palette: palette) }
        }
    }

    /// The largest text size the platform offers without the accessibility
    /// sizes, which is where a fixed-height panel would fail first.
    @Test("the answers stay whole at the largest text size")
    func largestTextSize() throws {
        let screen = try HostedScreen(
            dialog(Self.copy).environment(\.dynamicTypeSize, .accessibility3),
            palette: Self.palette
        )
        let drawing = try #require(screen.drawing)
        let box = try #require(drawing.box(ofColour: DrawnPixels.Channels(Self.palette.accentColor)))

        expect(box.right, isTheDrawn: FuelMetrics.Screen.horizontalPadding)
        #expect(box.top > 0, "the filled answer is drawn off the top of the screen")
    }

    // MARK: - Fixtures

    private func dialog(_ copy: FuelDialogCopy, entry: FuelDialogEntry? = nil) -> some View {
        FuelDialog(copy: copy, entry: entry, onConfirm: {}, onCancel: {})
            .frame(maxHeight: .infinity, alignment: .bottom)
    }
}

// MARK: - What a dialog does coming up

/// The dialog as it is actually raised: over a screen, on the sheet the chat
/// already uses.
///
/// What this suite asks that the drawing suite cannot — that it comes up at
/// all, that it is as tall as its question rather than as tall as the screen,
/// that its answers clear the home indicator, and that its field is the one the
/// user types into.
///
/// **Two things about a sheet cannot be asked here, and both were tried.** Its
/// dismissal transition never finishes in a test host: a sheet put away by the
/// binding it was raised with stalls mid-animation with the spring still
/// attached after three seconds of run loop, so what runs when the user swipes
/// it down is not something this harness can watch. And SwiftUI's focus engine
/// does not engage there either, though UIKit's does — see `FuelDialog.field`.
/// Neither is a claim about the app that has been dropped; both are claims the
/// only harness available cannot answer.
@Suite("Dialog · coming up over a screen", .serialized)
@MainActor
struct FuelDialogPresentationTests {

    private static let palette = FuelPalette(theme: .light, accent: .blue)

    private static let question = FuelDialogCopy(
        title: "Delete this meal?",
        confirm: "Delete",
        cancel: "Keep"
    )

    private static let itemField = FuelDialogCopy(
        title: "Item",
        hint: "Write the item as you would say it, with the amount if you know it.",
        confirm: "Done",
        cancel: "Cancel"
    )

    @Test("the question comes up over the screen")
    func itComesUp() throws {
        let screen = try HostedScreen(DialogHost(copy: Self.question), palette: Self.palette)

        #expect(screen.sheet != nil)
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
        let plain = try HostedScreen(DialogHost(copy: Self.question), palette: Self.palette)
        let plainHeight = try #require(plain.sheet).frame.height

        let withField = try HostedScreen(
            DialogHost(copy: Self.itemField, wantsField: true),
            palette: Self.palette
        )
        let fieldHeight = try #require(withField.sheet).frame.height

        #expect(plainHeight < plain.window.bounds.height / 2, "the question came up \(plainHeight) tall")
        #expect(fieldHeight > plainHeight, "a question with a field in it is no taller than one without")
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
        let screen = try HostedScreen(DialogHost(copy: Self.question), palette: Self.palette)
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
        #expect(abs(measured - drawn) <= 2, "measured \(measured) against a drawn \(drawn)")
    }

    // MARK: - The field

    /// The field is the one the user types into: what goes into the text view
    /// on the screen comes out of the binding the caller handed in.
    @Test("what is typed into the field is what the caller is given")
    func theFieldWritesBack() throws {
        let typing = Typing()
        let screen = try HostedScreen(
            DialogHost(copy: Self.itemField, wantsField: true, typing: typing),
            palette: Self.palette
        )
        let editor = try #require(screen.editor)

        editor.insertText("Polenta 150 g")
        screen.settle()

        #expect(typing.text == "Polenta 150 g")
    }

    /// The field sits in the inset the export puts every body of a screen in,
    /// like everything else on the dialog.
    @Test("the field stands at the drawn inset")
    func theFieldStandsAtTheDrawnInset() throws {
        let screen = try HostedScreen(
            DialogHost(copy: Self.itemField, wantsField: true),
            palette: Self.palette
        )
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

        @Environment(\.fuelPalette) private var palette

        @State private var isPresented = true

        @State private var text = ""

        var body: some View {
            palette.background
                .ignoresSafeArea()
                .fuelDialog(
                    copy,
                    isPresented: $isPresented,
                    entry: wantsField ? FuelDialogEntry(text: written, prompt: "Polenta 150 g", accessibilityLabel: "Item") : nil,
                    onConfirm: {}
                )
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

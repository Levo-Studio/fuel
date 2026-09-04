import Foundation

// MARK: - Copy

/// Every word screen 07 prints, and the two labels that make a result screen
/// the photo one.
///
/// The analysis states and the failure states used to sit here too. They are
/// not camera words — the text mode walks the same four steps and can fail the
/// same three ways — so they live in `AnalysisCopy` beside the views that
/// print them.
///
/// Nothing here holds English text — each entry names a key in
/// `Localizable.xcstrings`. Where a value is already uppercase it is because
/// the export draws it uppercase and the style it is set in does *not*
/// transform: `FuelTypography.overlayCaption` says so. The keys whose style
/// does transform — `flowLabel`, `sectionLabel` — keep their natural case
/// here.
///
/// The keyless state and the accessibility labels have no counterpart in the
/// export and are marked `Not in the export` in the catalog, the way
/// Onboarding and Settings marked theirs. The export draws no disabled camera;
/// it is built in its visual language because the app has to answer for it.
nonisolated enum CameraCopy {

    // MARK: - Screen 07

    static var shutterLabel: String {
        String(localized: "camera.shutter.label")
    }

    static var shutterHint: String {
        String(localized: "camera.shutter.hint")
    }

    static var galleryLabel: String {
        String(localized: "camera.gallery.label")
    }

    static var noKeyTitle: String {
        String(localized: "camera.noKey.title")
    }

    static var noKeyHint: String {
        String(localized: "camera.noKey.hint")
    }

    // MARK: - The context line

    /// The examples the empty context field rotates through, in the order they
    /// are shown.
    ///
    /// **Not in the export**, which draws no field on screen 07 at all — see
    /// `CameraTabView.contextField` for whose call that is. The wording is
    /// therefore held to what the field is for rather than to a drawn string:
    /// each one names something a photograph cannot show. Screen 12's examples
    /// all name an *amount*, because the line above that field asks for
    /// amounts; this field has no such line and is not describing the meal, so
    /// repeating that rule here would teach the user to say twice what the
    /// picture already says once.
    static var contextExamples: [String] {
        [
            String(localized: "camera.context.example.oil"),
            String(localized: "camera.context.example.sauce"),
            String(localized: "camera.context.example.milk"),
            String(localized: "camera.context.example.portion"),
        ]
    }

    /// An example with the trailing ellipsis that makes it read as unfinished.
    ///
    /// Its own key rather than screen 12's, although the two currently hold the
    /// same `%@ …`: the ellipsis belongs to the screen that prints it, and one
    /// shared entry would mean a translator could not punctuate the two fields
    /// differently without changing both.
    static func contextLine(_ example: String) -> String {
        String(format: String(localized: "camera.context.placeholder.format"), example)
    }

    /// What VoiceOver calls the field. Screen 12's is the heading standing over
    /// it; this field has no heading, so it carries a label of its own.
    static var contextLabel: String {
        String(localized: "camera.context.label")
    }

    // MARK: - Screen 14

    /// `Photo entry`, the flow label top right. Screen 15's is `Text entry`
    /// and belongs to the text mode.
    static var resultFlow: String {
        String(localized: "result.photo.flow")
    }

    /// `Recognised`, because this list came from a photo. The text mode's
    /// heading is `Broken down`.
    static var resultItemsHeading: String {
        String(localized: "result.photo.heading")
    }

    /// The stand-in the export draws where the photo goes. Only shown when
    /// there is no photo to draw — a preview, or a frame that did not survive.
    static var resultPhotoCaption: String {
        String(localized: "result.photo.caption")
    }

    static var resultPhotoLabel: String {
        String(localized: "result.photo.label")
    }
}

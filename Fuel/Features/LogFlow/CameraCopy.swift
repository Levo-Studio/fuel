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

    /// The `▣` in the circle top right.
    static var galleryGlyph: String {
        String(localized: "camera.gallery.glyph")
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

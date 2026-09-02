import Foundation
import UIKit

// MARK: - Photo

/// A camera photo, compressed and ready to be put in a request body.
///
/// It exists in memory and is gone when the request is. **Nothing here writes
/// a temporary file**, and there is no cache: the compressed bytes are handed
/// straight to the client, base64-encoded into the body, and released. The only
/// place a meal's content is written down is its SwiftData entry, and that is
/// the store's job.
nonisolated struct MealPhoto: Sendable, Equatable {

    /// JPEG bytes.
    let jpegData: Data

    /// The media type both providers are told, and the only one this type can
    /// produce. JPEG rather than PNG because a photograph is exactly the case
    /// lossy compression is for — a PNG of the same meal is several times the
    /// size for detail no model reads.
    static let mediaType = "image/jpeg"

    /// The base64 payload the request bodies carry.
    ///
    /// Computed rather than stored so the encoded copy — roughly a third
    /// larger again than the bytes — lives only as long as the body being
    /// built, instead of doubling the photo's footprint for the whole call.
    var base64: String {
        jpegData.base64EncodedString()
    }
}

// MARK: - Compression

/// Turns a captured photo into something worth sending.
///
/// Compression happens on the device because **the user is paying for those
/// tokens.** It is their key and their credit; shipping a 12-megapixel camera
/// frame when the model will downscale it anyway is spending someone else's
/// money for nothing.
nonisolated enum MealPhotoCompressor {

    // MARK: - The numbers, and where they come from

    /// The long edge every photo is scaled down to.
    ///
    /// 1568 px is Anthropic's **standard** resolution tier: an image whose
    /// long edge is at or under it is passed through untouched, and anything
    /// larger is downscaled to fit before the model ever sees it. Sending more
    /// than this is paying to transfer pixels the provider then throws away.
    ///
    /// Claude Sonnet 5 is on Anthropic's *high-resolution* tier and would
    /// accept a 2576 px long edge — but that tier costs up to roughly three
    /// times as many visual tokens for the same photo, and it buys fidelity
    /// aimed at dense documents, screenshots and coordinate work. A plate of
    /// food is none of those. 1568 is the deliberate choice: the point where
    /// Anthropic stops charging for extra resolution, comfortably inside
    /// Mistral's own limits, and one number for both providers rather than a
    /// per-provider branch that would make two log modes behave differently.
    ///
    /// Sources, read rather than guessed:
    /// - Anthropic, *Vision* — resolution tiers (1568 px standard / 2576 px
    ///   high-resolution), 10 MB per base64 image on the Claude API, 32 MB per
    ///   request, and JPEG/PNG/GIF/WebP as the supported formats.
    /// - Mistral, *Vision* — 10 MB per image, and a hard rejection above
    ///   10000×10000 px.
    static let longEdge: CGFloat = 1568

    /// The JPEG quality a photo is first encoded at.
    ///
    /// 0.7 is where a downscaled photograph stops shrinking meaningfully and
    /// starts visibly degrading. Anthropic's own guidance warns that heavy
    /// lossy compression costs the model accuracy — the failure mode being
    /// exactly the fine detail that distinguishes one portion from another —
    /// so this is chosen to be the last quality above that cliff, not the
    /// smallest file achievable.
    static let initialQuality: CGFloat = 0.7

    /// The floor the retry ladder stops at rather than trading away any more
    /// accuracy. A photo that is still too large here is refused.
    static let minimumQuality: CGFloat = 0.4

    /// The ceiling a compressed photo has to fit under, in bytes of JPEG.
    ///
    /// 4 MB, against a limit of 10 MB per image at both providers. The gap is
    /// deliberate and is not caution for its own sake: the wire carries
    /// base64, which is about 4/3 the size of the bytes, so 4 MB of JPEG is
    /// roughly 5.5 MB of body — still half of the per-image allowance, with
    /// the prompt, the JSON envelope and any future second block fitting
    /// inside the same headroom. In practice a 1568 px JPEG at quality 0.7 is
    /// a few hundred kilobytes, so this ceiling is a guard against a pathological
    /// input rather than a routine constraint.
    static let maximumBytes = 4 * 1024 * 1024

    // MARK: - Entry point

    /// Compresses `image` for upload.
    ///
    /// Throws `AIError.imageTooLarge` when the result is still over
    /// `maximumBytes`. **Failing here is the point**: a photo that the
    /// provider would reject must not be sent, because the user pays for the
    /// upload either way and gets a provider error in place of an estimate.
    ///
    /// `ceiling` defaults to `maximumBytes` and is a parameter for one
    /// reason: the refusal above is the behaviour worth testing, and a real
    /// 1568 px JPEG is a few hundred kilobytes, so no photograph a camera can
    /// produce reaches 4 MB. A test that cannot reach the failing branch is
    /// not testing it.
    static func compress(_ image: UIImage, ceiling: Int = maximumBytes) throws -> MealPhoto {
        let scaled = scaledDown(image)

        // Quality is stepped down rather than searched: three encodes is a
        // bounded cost, and a binary search over quality would spend more time
        // on a case that essentially never happens once the long edge is
        // capped.
        var quality = initialQuality
        while quality >= minimumQuality {
            guard let data = scaled.jpegData(compressionQuality: quality) else {
                throw AIError.imageTooLarge
            }
            if data.count <= ceiling {
                return MealPhoto(jpegData: data)
            }
            quality -= 0.15
        }

        throw AIError.imageTooLarge
    }

    // MARK: - Scaling

    /// Scales `image` so its long edge is at most `longEdge` **pixels**,
    /// preserving the aspect ratio. An image already inside the limit is
    /// returned unchanged rather than round-tripped through a redraw that
    /// could only lose detail.
    ///
    /// Everything here is in pixels, which is why `scale` is multiplied in
    /// rather than ignored. `UIImage.size` is in points, and a photo carrying
    /// `scale == 3` measures 1568 points while being 4704 pixels wide — three
    /// times the resolution the providers charge for, waved through by a check
    /// that read the wrong unit. That was the first version of this function,
    /// and the test on the shorter path is what caught it.
    private static func scaledDown(_ image: UIImage) -> UIImage {
        let scale = max(image.scale, 1)
        let pixels = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let currentLongEdge = max(pixels.width, pixels.height)

        guard currentLongEdge > longEdge, currentLongEdge > 0 else {
            return image
        }

        let factor = longEdge / currentLongEdge
        let target = CGSize(width: pixels.width * factor, height: pixels.height * factor)

        // `scale: 1` so the target is read in pixels rather than points. On a
        // 3× device the default would render three times the requested edge
        // and undo the whole point of the resize.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

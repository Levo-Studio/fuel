import AVFoundation
import SwiftUI

// MARK: - Capture seam

/// The camera, reduced to the three things screen 07 asks of it.
///
/// A protocol rather than an `AVCaptureSession` held directly in the view,
/// because `AVCaptureDevice.default(_:for:position:)` returns `nil` on a
/// simulator and there is no way around that. Without a seam the viewfinder
/// could not be previewed, the shutter could not be exercised in a test, and
/// the whole log path from a frame to a stored entry would only ever run on a
/// physical device. `AVFoundationCamera` below is the only type in the feature
/// that touches a capture API.
@MainActor
protocol MealCamera: AnyObject {

    /// What the viewfinder should draw right now.
    var preview: MealCameraPreview { get }

    /// Brings the session up, asking for permission the first time.
    ///
    /// Does not throw: a refused permission and a device without a camera are
    /// the same thing to the screen, and both leave `preview` at
    /// `.unavailable`. Whether the shutter may be pressed is a question about
    /// the stored key, not about this.
    func start() async

    func stop()

    /// One frame, in memory.
    ///
    /// **Nothing is written to disk on the way here.** `AVCapturePhotoOutput`
    /// hands back the JPEG as `Data`, it becomes a `UIImage`, and it is
    /// released with the request it was sent in.
    func capturePhoto() async throws -> UIImage
}

// MARK: - What the viewfinder shows

/// Where the viewfinder's pixels come from.
nonisolated enum MealCameraPreview {

    case live(AVCaptureSession)

    /// No session to show: a simulator, a camera permission the user refused,
    /// a SwiftUI preview. The export's diagonal hatch stands in — which is
    /// what screen 07 itself draws, so this is the designed appearance rather
    /// than a fallback invented for the missing case.
    case unavailable
}

// MARK: - Failures

/// What can go wrong between the shutter and a frame.
///
/// Two cases, and neither carries a system message: `AVFoundation` errors are
/// as unfit for the interface as a provider's are. The flow maps both onto the
/// retry state, because trying again is the only useful advice for either.
nonisolated enum MealCameraError: Error, Equatable {

    /// There is no camera to capture from, or the session never came up.
    case unavailable

    /// The shutter fired and no usable image came back.
    case captureFailed
}

// MARK: - AVFoundation

/// The real camera.
///
/// Session work runs on its own queue rather than on the main actor.
/// `startRunning()` blocks until the first frame arrives, which is long enough
/// to be seen as a stall when the log flow opens, and Apple's own guidance is
/// that configuration and running belong off the main thread while the preview
/// layer stays on it. That split is why `session` is reached through
/// `nonisolated(unsafe)` below: the object is shared between this queue and the
/// preview layer by design, and `AVCaptureSession` documents its own locking
/// for exactly that arrangement.
@MainActor
final class AVFoundationCamera: MealCamera {

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "apps.levo-studio.Fuel.camera")

    /// Set once the session has an input and an output. Until then there is
    /// nothing worth handing to a preview layer.
    private var isConfigured = false

    /// Held for the length of one capture. `AVCapturePhotoOutput` does not
    /// retain its delegate, so dropping this would end the capture before the
    /// photo came back.
    private var pendingCapture: PhotoCaptureDelegate?

    var preview: MealCameraPreview {
        isConfigured ? .live(session) : .unavailable
    }

    // MARK: - Session

    func start() async {
        guard await Self.isAuthorised() else { return }
        guard configureIfNeeded() else { return }
        await onSessionQueue { $0.startRunning() }
    }

    func stop() {
        guard isConfigured else { return }
        Task { await onSessionQueue { $0.stopRunning() } }
    }

    /// Asks once, and answers the same way for "denied" and "restricted".
    private static func isAuthorised() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        default:
            return false
        }
    }

    /// Wires the back camera to a photo output. Idempotent, because the tab is
    /// left and re-entered without the object being rebuilt.
    private func configureIfNeeded() -> Bool {
        if isConfigured { return true }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input),
            session.canAddOutput(output)
        else {
            return false
        }

        session.beginConfiguration()
        session.sessionPreset = .photo
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        isConfigured = true
        return true
    }

    /// Runs `work` on the session queue and comes back when it is done.
    ///
    /// The session crosses an isolation boundary here on purpose — see the
    /// note on the type. It is passed rather than captured through `self` so
    /// the closure carries one shared object and nothing else.
    private func onSessionQueue(_ work: @escaping @Sendable (AVCaptureSession) -> Void) async {
        nonisolated(unsafe) let session = self.session
        await withCheckedContinuation { continuation in
            queue.async {
                work(session)
                continuation.resume()
            }
        }
    }

    // MARK: - Capture

    func capturePhoto() async throws -> UIImage {
        guard isConfigured else { throw MealCameraError.unavailable }

        let image = try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { result in
                continuation.resume(with: result)
            }
            pendingCapture = delegate
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
        pendingCapture = nil
        return image
    }
}

// MARK: - Capture delegate

/// Turns one `AVCapturePhotoOutput` callback into one continuation resume.
///
/// `nonisolated` and `@unchecked Sendable` because the callback arrives on a
/// queue of `AVFoundation`'s choosing. The only mutable state is the
/// continuation, and it is consumed exactly once — the delegate is used for a
/// single capture and dropped.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {

    private let finish: @Sendable (Result<UIImage, any Error>) -> Void

    init(finish: @escaping @Sendable (Result<UIImage, any Error>) -> Void) {
        self.finish = finish
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard
            error == nil,
            let data = photo.fileDataRepresentation(),
            let image = UIImage(data: data)
        else {
            // The provider's rule applies to the system too: whatever
            // `AVFoundation` wrote in that error, it is not something to put
            // on a screen.
            finish(.failure(MealCameraError.captureFailed))
            return
        }
        finish(.success(image))
    }
}

// MARK: - Stand-in

/// A camera that has none.
///
/// What the simulator, a SwiftUI preview and a test get. It draws the export's
/// hatch, exactly as screens 07 to 11 do, and refuses to capture rather than
/// handing back a blank frame that would then be sent to a provider and paid
/// for.
@MainActor
final class UnavailableCamera: MealCamera {

    var preview: MealCameraPreview { .unavailable }

    func start() async {}

    func stop() {}

    func capturePhoto() async throws -> UIImage {
        throw MealCameraError.unavailable
    }
}

// MARK: - Preview layer

/// Puts the running session on screen.
///
/// A `UIViewRepresentable` because `AVCaptureVideoPreviewLayer` is a
/// `CALayer`, and there is no SwiftUI view that renders one. It holds the
/// layer and nothing else: no controls, no gestures, no overlay. Everything
/// drawn on top of the viewfinder is a SwiftUI view above this one.
struct CameraPreviewLayer: UIViewRepresentable {

    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.previewLayer.session = session
    }

    /// A view whose backing layer *is* the preview layer, so the layer follows
    /// the view's bounds without a manual resize on every layout pass.
    final class PreviewView: UIView {

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        // Safe by construction: `layerClass` above guarantees the type.
        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

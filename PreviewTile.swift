import Cocoa
import CoreImage
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// A read-only live preview for one macOS window. It deliberately does not
/// forward input; `onActivate` lets the owner raise/focus the real window.
@available(macOS 12.3, *)
public final class OmacPreviewTileController: NSObject, NSWindowDelegate, SCStreamOutput, SCStreamDelegate {
    public enum PreviewTileError: Error {
        case targetUnavailable
        case captureUnavailable(Error)
    }
    public struct Diagnostics {
        public let received: Int
        public let displayed: Int
        public let dropped: Int
        public let rejected: Int
        public let pixelFormat: OSType?
    }

    public let targetWindowID: CGWindowID
    public var onActivate: (() -> Void)?
    public var onFailure: ((Error) -> Void)?
    public var onStatus: ((String) -> Void)?

    private var stream: SCStream?
    private let frameQueue = DispatchQueue(label: "com.richard.omac.preview.frames", qos: .userInitiated)
    private let pendingFrame = DispatchSemaphore(value: 1)
    private let imageView = PreviewImageView()
    private let statusLabel = NSTextField(labelWithString: "Preparing capture…")
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var previewWindow: NSWindow?
    private var receivedFrames = 0
    private var displayedFrames = 0
    private var droppedFrames = 0
    private var rejectedFrames = 0
    private var observedPixelFormat: OSType?

    public init(targetWindowID: CGWindowID, onActivate: (() -> Void)? = nil,
                onFailure: ((Error) -> Void)? = nil,
                onStatus: ((String) -> Void)? = nil) {
        self.targetWindowID = targetWindowID
        self.onActivate = onActivate
        self.onFailure = onFailure
        self.onStatus = onStatus
        super.init()
        imageView.onActivate = { [weak self] in self?.onActivate?() }
    }

    public var diagnostics: Diagnostics {
        Diagnostics(received: receivedFrames, displayed: displayedFrames,
                    dropped: droppedFrames, rejected: rejectedFrames,
                    pixelFormat: observedPixelFormat)
    }

    /// Starts capture after the caller has obtained Screen Recording access.
    /// ScreenCaptureKit performs the normal system permission check; this
    /// proof of concept never requests or prompts for permission itself.
    public func start() async throws {
        guard stream == nil else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                                onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == targetWindowID }) else {
                throw PreviewTileError.targetUnavailable
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            if #available(macOS 13.0, *) { configuration.capturesAudio = false }
            configuration.showsCursor = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.width = max(320, Int(window.frame.width))
            configuration.height = max(180, Int(window.frame.height))
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)

            let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
            try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
            stream = capture
            try await capture.startCapture()
            reportStatus("Capture started · BGRA · waiting for complete frames")
            await MainActor.run { self.showWindowIfNeeded() }
        } catch let error as PreviewTileError {
            onFailure?(error)
            throw error
        } catch {
            stream = nil
            let failure = PreviewTileError.captureUnavailable(error)
            onFailure?(failure)
            throw failure
        }
    }

    public func stop() {
        let capture = stream
        stream = nil
        if let capture { Task { try? await capture.stopCapture() } }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.previewWindow?.delegate = nil
            self.previewWindow?.close()
            self.previewWindow = nil
            self.imageView.image = nil
            self.reportStatus("Capture stopped")
        }
    }

    public func windowWillClose(_ notification: Notification) {
        stop()
        previewWindow = nil
    }

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        receivedFrames += 1
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete else {
            rejectedFrames += 1
            reportStatus("Frames \(receivedFrames) · rejected \(rejectedFrames) · incomplete")
            return
        }
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        observedPixelFormat = format
        guard format == kCVPixelFormatType_32BGRA else {
            rejectedFrames += 1
            reportStatus("Frames \(receivedFrames) · unsupported pixel format \(format)")
            return
        }
        guard pendingFrame.wait(timeout: .now()) == .success else {
            droppedFrames += 1
            reportStatus("Frames \(receivedFrames) · displayed \(displayedFrames) · dropped \(droppedFrames)")
            return
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let cgImage = context.createCGImage(image, from: image.extent)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        guard let cgImage else { pendingFrame.signal(); reportStatus("Frame conversion failed"); return }
        let gate = pendingFrame
        DispatchQueue.main.async { [weak self] in
            defer { gate.signal() }
            guard let self, self.stream != nil else { return }
            let imageSize = NSSize(width: cgImage.width, height: cgImage.height)
            self.imageView.image = NSImage(cgImage: cgImage, size: imageSize)
            self.displayedFrames += 1
            self.reportStatus("Frames \(self.receivedFrames) · displayed \(self.displayedFrames) · dropped \(self.droppedFrames)")
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        reportStatus("Capture stopped with error")
        onFailure?(PreviewTileError.captureUnavailable(error))
        DispatchQueue.main.async { [weak self] in self?.stop() }
    }

    @MainActor
    private func showWindowIfNeeded() {
        guard previewWindow == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 480, height: 280),
                              styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Omac Preview"
        statusLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [imageView, statusLabel])
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)
        window.contentView = stack
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        previewWindow = window
    }

    private func reportStatus(_ status: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel.stringValue = status
            self?.onStatus?(status)
        }
    }
}

@available(macOS 12.3, *)
private final class PreviewImageView: NSImageView {
    var onActivate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        imageScaling = .scaleProportionallyUpOrDown
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        onActivate?()
        super.mouseDown(with: event)
    }
}

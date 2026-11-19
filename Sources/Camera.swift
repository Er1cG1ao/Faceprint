import AppKit
import AVFoundation
import CoreImage

enum FillError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

struct CameraFrame {
    let id: UInt64
    let active: CaptureResolution
    let buffer: CVPixelBuffer
    var resolution: CaptureResolution {
        CaptureResolution(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }
    var sourceScale: CGFloat { active.sourceScale(delivered: resolution) }
    private static let context = CIContext(options: [.cacheIntermediates: false])
    var image: CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        return Self.context.createCGImage(image, from: image.extent)
    }

    func faceCrop(_ box: CGRect) -> CGImage? {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let crop = FaceDetector.coreImageCrop(box, imageSize: image.extent.size) else { return nil }
        return Self.context.createCGImage(image, from: crop)
    }
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.er1cg1ao.faceprint.camera")
    private let frameLock = NSLock()
    private let controlLock = NSLock()
    private var generation: UInt64 = 0
    private var acceptingFrames = false
    private var configuredResolution: CaptureResolution?
    private var frame: CameraFrame?
    private var frameID: UInt64 = 0
    private var configuredDevice: AVCaptureDevice?
    private weak var configuredOutput: AVCaptureVideoDataOutput?

    private func nextGeneration() -> UInt64 {
        controlLock.lock()
        defer { controlLock.unlock() }
        generation &+= 1
        return generation
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        controlLock.lock()
        defer { controlLock.unlock() }
        return token == generation
    }

    static var devices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    func latestFrame() -> CameraFrame? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return frame
    }

    static func size(of format: AVCaptureDevice.Format) -> CaptureResolution {
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return CaptureResolution(width: Int(dimensions.width), height: Int(dimensions.height))
    }

    private func configureResolution(_ requested: CaptureResolution, device: AVCaptureDevice) throws -> CaptureResolution {
        let formats = device.formats
        guard let selected = CaptureResolution.select(requested, from: formats.map(Self.size)),
              let format = formats.filter({ Self.size(of: $0) == selected }).max(by: {
                  preferredRate($0) < preferredRate($1)
              }) else { throw FillError.message("This camera has no usable video format.") }

        // On macOS the session preset can renegotiate the device format at commit.
        // Use a matching preset where available, and explicitly size the output below.
        let presets: [CaptureResolution: AVCaptureSession.Preset] = [
            .hd: .hd1920x1080, CaptureResolution.standard[1]: .hd1280x720,
            CaptureResolution.standard[0]: .vga640x480]
        if let preset = presets[selected], session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = format
        if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        }
        return selected
    }

    private func preferredRate(_ format: AVCaptureDevice.Format) -> Double {
        min(30, format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
    }

    func start(deviceID: String, requested: CaptureResolution) async throws {
        let token = nextGeneration()
        clearFrame()
        let allowed: Bool
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
        else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        try Task.checkCancellation()
        guard allowed else { throw FillError.message("Allow Camera access in System Settings, then try again.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in

            queue.async {

                var configuring = false
                do {
                    guard self.isCurrent(token) else { throw CancellationError() }
                    let device = (deviceID.isEmpty ? nil : AVCaptureDevice(uniqueID: deviceID)) ?? AVCaptureDevice.default(for: .video)
                    guard let device else { throw FillError.message("No camera is available.") }

                    self.acceptingFrames = false
                    if self.session.isRunning { self.session.stopRunning() }
                    self.clearFrame()
                    func beginDelivery() throws {

                        self.session.startRunning()

                        guard self.session.isRunning, self.isCurrent(token) else {
                            if !self.isCurrent(token) { throw CancellationError() }
                            throw FillError.message("Camera did not start.")
                        }
                        self.acceptingFrames = true
                    }
                    if self.configuredResolution == requested, self.configuredDevice?.uniqueID == device.uniqueID, !self.session.inputs.isEmpty {
                        try beginDelivery()
                        continuation.resume()
                        return
                    }
                    self.configuredDevice = nil
                    self.configuredOutput = nil
                    self.clearFrame()
                    self.session.beginConfiguration()
                    configuring = true
                    self.session.inputs.forEach { self.session.removeInput($0) }
                    self.session.outputs.forEach { self.session.removeOutput($0) }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else { throw FillError.message("Cannot use this camera.") }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { throw FillError.message("Cannot read camera frames.") }
                    self.session.addOutput(output)
                    let selected = try self.configureResolution(requested, device: device)
                    let native = CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)
                    let supported = output.availableVideoPixelFormatTypes
                    let choices = [native, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                   kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_32BGRA]
                    var settings: [String: Any] = [kCVPixelBufferWidthKey as String: selected.width,
                                                    kCVPixelBufferHeightKey as String: selected.height]
                    if let type = choices.first(where: supported.contains) {
                        settings[kCVPixelBufferPixelFormatTypeKey as String] = type
                    }
                    output.videoSettings = settings
                    self.session.commitConfiguration()
                    configuring = false
                    self.configuredResolution = requested
                    self.configuredDevice = device
                    self.configuredOutput = output
                    guard self.isCurrent(token) else { throw CancellationError() }
                    try beginDelivery()
                    continuation.resume()
                } catch {
                    if configuring { self.session.commitConfiguration() }
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func clearFrame() {
        frameLock.lock()
        frame = nil
        frameLock.unlock()
    }

    func stop() {
        let token = nextGeneration()
        clearFrame()
        queue.async {
            guard self.isCurrent(token) else { return }
            self.acceptingFrames = false
            if self.session.isRunning { self.session.stopRunning() }
            self.clearFrame()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard acceptingFrames, output === configuredOutput, let device = configuredDevice,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        frameLock.lock()
        frameID &+= 1
        frame = CameraFrame(id: frameID, active: Self.size(of: device.activeFormat), buffer: buffer)
        frameLock.unlock()
    }
}

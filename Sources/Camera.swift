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
    let firstArrival: TimeInterval
    let id: UInt64
    let requested: CaptureResolution
    let active: CaptureResolution
    let buffer: CVPixelBuffer
    let fps: Double?
    var resolution: CaptureResolution {
        CaptureResolution(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }
    var sourceScale: CGFloat { active.sourceScale(delivered: resolution) }
    private static let context = CIContext(options: [.cacheIntermediates: false])
    var image: CGImage? {
        let ci = CIImage(cvPixelBuffer: buffer)
        return Self.context.createCGImage(ci, from: ci.extent)
    }
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.er1cg1ao.faceprint.camera")
    private let frameLock = NSLock()
    private let controlLock = NSLock()
    private var generation: UInt64 = 0
    private var acceptingFrames = false
    private var firstArrival: TimeInterval?
    private var previousPTS: Double?
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

    @discardableResult
    func start(deviceID: String, requested: CaptureResolution) async throws -> CameraStartupTiming {
        let entered = ProcessInfo.processInfo.systemUptime
        let token = nextGeneration()
        clearFrame()
        let allowed: Bool
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { allowed = true }
        else { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        try Task.checkCancellation()
        guard allowed else { throw FillError.message("Allow Camera access in System Settings, then try again.") }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CameraStartupTiming, Error>) in
            let queued = ProcessInfo.processInfo.systemUptime
            queue.async {
                let dequeued = ProcessInfo.processInfo.systemUptime
                var configuring = false
                do {
                    guard self.isCurrent(token) else { throw CancellationError() }
                    let device = (deviceID.isEmpty ? nil : AVCaptureDevice(uniqueID: deviceID)) ?? AVCaptureDevice.default(for: .video)
                    guard let device else { throw FillError.message("No camera is available.") }
                    let deviceReady = ProcessInfo.processInfo.systemUptime
                    self.acceptingFrames = false
                    if self.session.isRunning { self.session.stopRunning() }
                    self.clearFrame()
                    func beginDelivery(reused: Bool) throws -> CameraStartupTiming {
                        let before = ProcessInfo.processInfo.systemUptime
                        self.session.startRunning()
                        let after = ProcessInfo.processInfo.systemUptime
                        guard self.session.isRunning, self.isCurrent(token) else {
                            if !self.isCurrent(token) { throw CancellationError() }
                            throw FillError.message("Camera did not start.")
                        }
                        self.acceptingFrames = true
                        return CameraStartupTiming(entered: entered, queued: queued, dequeued: dequeued,
                            deviceReady: deviceReady, startRunningAt: before, runningAt: after,
                            reused: reused)
                    }
                    self.previousPTS = nil
                    self.firstArrival = nil
                    if self.configuredResolution == requested, self.configuredDevice?.uniqueID == device.uniqueID, !self.session.inputs.isEmpty {
                        continuation.resume(returning: try beginDelivery(reused: true))
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
                    continuation.resume(returning: try beginDelivery(reused: false))
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
        let arrival = firstArrival ?? ProcessInfo.processInfo.systemUptime
        guard acceptingFrames, output === configuredOutput, let device = configuredDevice, let requested = configuredResolution,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let fps = previousPTS.flatMap { pts > $0 ? 1 / (pts - $0) : nil }
        previousPTS = pts
        frameLock.lock()
        frameID &+= 1
        firstArrival = arrival
        frame = CameraFrame(firstArrival: arrival, id: frameID, requested: requested, active: Self.size(of: device.activeFormat), buffer: buffer, fps: fps)
        frameLock.unlock()
    }
}

// Scalar measurements only. Kept in memory for the latest attempt.
struct DeveloperReadout {
    var requested: CaptureResolution?
    var active: CaptureResolution?
    var resolution: CaptureResolution?
    var fps: Double?
    var box: CGRect?
    var tier: AlignmentTier?
    var detection: Double?
    var alignment: Double?
    var inference: Double?
    var startupPhases: [(String, TimeInterval)] = []
    var firstFrame: Double?
    var recognition: Double?
    var delivery: Double?
    var similarity: Float?
    var result = "Waiting for scan"
    var reason: String?

    mutating func observe(_ frame: CameraFrame, _ scan: ScanMeasurement, score: Float?) {
        requested = frame.requested
        active = frame.active
        resolution = frame.resolution
        fps = frame.fps
        box = scan.box
        tier = scan.tier
        detection = scan.detection
        alignment = scan.alignment
        inference = scan.inference
        similarity = score
        reason = scan.reason ?? ((score ?? -1) < 0.66 ? "Identity mismatch" : nil)
        result = reason == nil ? "Awaiting confirmation" : "Frame rejected"
    }

    var rows: [(String, String)] {
        func ms(_ value: Double?) -> String { value.map { String(format: "%.1f ms", $0 * 1000) } ?? "—" }
        var rows: [(String, String)] = [
            ("Requested resolution", requested?.label ?? "—"),
            ("Active camera format", active?.label ?? "—"),
            ("Delivered resolution", resolution?.label ?? "—"),
            ("Actual FPS", fps.map { String(format: "%.1f", $0) } ?? "—"),
            ("Face bounding box (x, y, w, h)", box.map { String(format: "%.0f, %.0f, %.0f, %.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "—"),
            ("Face width", box.flatMap { b in resolution.map { String(format: "%.0f px · %.1f%%", b.width, 100 * b.width / CGFloat($0.width)) } } ?? "—"),
            ("Alignment tier", tier?.rawValue ?? "—"),
            ("Trigger to first frame", ms(firstFrame))
        ]
        rows.append(contentsOf: startupPhases.map { ($0.0, ms($0.1)) })
        rows.append(contentsOf: [
            ("Detection", ms(detection)), ("Alignment", ms(alignment)), ("ArcFace inference", ms(inference)),
            ("Trigger to recognition", ms(recognition)), ("Trigger to verified fill", ms(delivery)),
            ("Cosine similarity", similarity.map { String(format: "%.3f", $0) } ?? "—"),
            ("Recognition result", result), ("Rejection reason", reason ?? "—")
        ])
        return rows
    }
}

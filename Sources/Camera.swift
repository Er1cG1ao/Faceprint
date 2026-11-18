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
    let buffer: CVPixelBuffer
    let fps: Double?
    var resolution: CaptureResolution {
        CaptureResolution(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
    }
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
    private var firstArrival: TimeInterval?
    private var previousPTS: Double?
    private var configuredResolution: CaptureResolution?
    private var frame: CameraFrame?
    private var frameID: UInt64 = 0
    private var configuredDeviceID: String?

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

    private func configureResolution(_ requested: CaptureResolution, device: AVCaptureDevice) {
        let formats = device.formats
        if let selected = CaptureResolution.select(requested, from: formats.map(Self.size)),
           let format = formats.filter({ Self.size(of: $0) == selected }).max(by: {
               preferredRate($0) < preferredRate($1)
           }), (try? device.lockForConfiguration()) != nil {
            defer { device.unlockForConfiguration() }
            device.activeFormat = format
            if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            }
            return
        }
        let presets: [(CaptureResolution, AVCaptureSession.Preset)] = [
            (.hd, .hd1920x1080), (CaptureResolution.standard[1], .hd1280x720),
            (CaptureResolution.standard[0], .vga640x480)]
        if let preset = presets.first(where: { $0.0 <= requested && session.canSetSessionPreset($0.1) }) {
            session.sessionPreset = preset.1
        } else if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
    }

    private func preferredRate(_ format: AVCaptureDevice.Format) -> Double {
        min(30, format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0)
    }

    func start(deviceID: String) async throws {
        let token = nextGeneration()
        clearFrame()
        let requested = CaptureResolution.preference
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        try Task.checkCancellation()
        guard allowed else { throw FillError.message("Allow Camera access in System Settings, then try again.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                var configuring = false
                do {
                    guard self.isCurrent(token) else { throw CancellationError() }
                    let device = Self.devices.first { $0.uniqueID == deviceID } ?? AVCaptureDevice.default(for: .video)
                    guard let device else { throw FillError.message("No camera is available.") }
                    self.previousPTS = nil
                    self.firstArrival = nil
                    if self.configuredResolution == requested, self.configuredDeviceID == device.uniqueID, !self.session.inputs.isEmpty {
                        if !self.session.isRunning { self.session.startRunning() }
                        guard self.session.isRunning else { throw FillError.message("Camera did not start.") }
                        continuation.resume()
                        return
                    }
                    if self.session.isRunning { self.session.stopRunning() }
                    self.configuredDeviceID = nil
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
                    self.configureResolution(requested, device: device)
                    let native = CMFormatDescriptionGetMediaSubType(device.activeFormat.formatDescription)
                    let supported = output.availableVideoPixelFormatTypes
                    let choices = [native, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                   kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_32BGRA]
                    if let type = choices.first(where: supported.contains) {
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: type]
                    }
                    self.session.commitConfiguration()
                    configuring = false
                    self.configuredResolution = requested
                    self.configuredDeviceID = device.uniqueID
                    guard self.isCurrent(token) else { throw CancellationError() }
                    self.session.startRunning()
                    guard self.session.isRunning else { throw FillError.message("Camera did not start.") }
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
            self.session.stopRunning()
            self.frameLock.lock()
            self.frame = nil
            self.frameLock.unlock()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let fps = previousPTS.flatMap { pts > $0 ? 1 / (pts - $0) : nil }
        previousPTS = pts
        frameLock.lock()
        frameID &+= 1
        let first = firstArrival ?? ProcessInfo.processInfo.systemUptime
        firstArrival = first
        frame = CameraFrame(firstArrival: first, id: frameID, buffer: buffer, fps: fps)
        frameLock.unlock()
    }
}

extension Camera {
    func timedStart(deviceID: String) async throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        try await self.start(deviceID: deviceID)
        return ProcessInfo.processInfo.systemUptime - start
    }
}

// Scalar measurements only. Kept in memory for the latest attempt.
struct DeveloperReadout {
    var resolution: CaptureResolution?
    var fps: Double?
    var box: CGRect?
    var tier: AlignmentTier?
    var detection: Double?
    var alignment: Double?
    var inference: Double?
    var cameraStart: Double?
    var firstFrame: Double?
    var recognition: Double?
    var delivery: Double?
    var similarity: Float?
    var result = "Waiting for scan"
    var reason: String?

    mutating func observe(_ frame: CameraFrame, _ scan: ScanMeasurement, score: Float?) {
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
        return [
            ("Camera resolution", resolution?.label ?? "—"),
            ("Actual FPS", fps.map { String(format: "%.1f", $0) } ?? "—"),
            ("Face bounding box (x, y, w, h)", box.map { String(format: "%.0f, %.0f, %.0f, %.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "—"),
            ("Face width", box.flatMap { b in resolution.map { String(format: "%.0f px · %.1f%%", b.width, 100 * b.width / CGFloat($0.width)) } } ?? "—"),
            ("Alignment tier", tier?.rawValue ?? "—"),
            ("Camera startup", ms(cameraStart)), ("Trigger to first frame", ms(firstFrame)),
            ("Detection", ms(detection)), ("Alignment", ms(alignment)), ("ArcFace inference", ms(inference)),
            ("Trigger to recognition", ms(recognition)), ("Trigger to verified fill", ms(delivery)),
            ("Cosine similarity", similarity.map { String(format: "%.3f", $0) } ?? "—"),
            ("Recognition result", result), ("Rejection reason", reason ?? "—")
        ]
    }
}

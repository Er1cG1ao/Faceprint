import AppKit
import AVFoundation
import CoreImage

enum FillError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "io.github.er1cg1ao.faceprint.camera")
    private let frameLock = NSLock()
    private let controlLock = NSLock()
    private var generation: UInt64 = 0
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frame: (id: UInt64, image: CGImage)?
    private var frameID: UInt64 = 0

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

    func latestFrame() -> (id: UInt64, image: CGImage)? {
        frameLock.lock()
        defer { frameLock.unlock() }
        return frame
    }

    func start(deviceID: String) async throws {
        let token = nextGeneration()
        clearFrame()
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        try Task.checkCancellation()
        guard allowed else { throw FillError.message("Allow Camera access in System Settings, then try again.") }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                var configuring = false
                do {
                    guard self.isCurrent(token) else { throw CancellationError() }
                    if self.session.isRunning { self.session.stopRunning() }
                    self.clearFrame()
                    self.session.beginConfiguration()
                    configuring = true
                    self.session.sessionPreset = .vga640x480
                    self.session.inputs.forEach { self.session.removeInput($0) }
                    self.session.outputs.forEach { self.session.removeOutput($0) }
                    let device = Self.devices.first { $0.uniqueID == deviceID } ?? AVCaptureDevice.default(for: .video)
                    guard let device else { throw FillError.message("No camera is available.") }
                    let input = try AVCaptureDeviceInput(device: device)
                    guard self.session.canAddInput(input) else { throw FillError.message("Cannot use this camera.") }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else { throw FillError.message("Cannot read camera frames.") }
                    self.session.addOutput(output)
                    self.session.commitConfiguration()
                    configuring = false
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
        let image = CIImage(cvPixelBuffer: buffer)
        guard let rendered = context.createCGImage(image, from: image.extent) else { return }
        frameLock.lock()
        frameID &+= 1
        frame = (frameID, rendered)
        frameLock.unlock()
    }
}

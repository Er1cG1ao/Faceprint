import CoreVideo
import Foundation

enum VisionWarmup {
    static func run() async -> String {
        let started = ProcessInfo.processInfo.systemUptime
        let size = CaptureResolution.hd
        var pixelBuffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, size.width, size.height,
                                  kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                                  attributes, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer,
              CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else {
            return "Synthetic buffer unavailable"
        }
        // Video-range neutral black with neutral chroma. No camera input.
        for plane in 0..<CVPixelBufferGetPlaneCount(buffer) {
            if let bytes = CVPixelBufferGetBaseAddressOfPlane(buffer, plane) {
                memset(bytes, plane == 0 ? 16 : 128,
                       CVPixelBufferGetBytesPerRowOfPlane(buffer, plane) * CVPixelBufferGetHeightOfPlane(buffer, plane))
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let normalizedBox = CGRect(x: 0.4, y: 0.35, width: 0.2, height: 0.35)
        let box = FaceDetector.convertToImageSpace(normalizedBox,
                                                  imageSize: CGSize(width: size.width, height: size.height))
        let frame = CameraFrame(firstFrameTiming: FirstCameraFrameTiming(callbackAt: 0, presentationToCallback: nil),
                                id: 0, requested: size, active: size, buffer: buffer, fps: nil)
        async let vision = warmFaceRequests(buffer, normalizedBox: normalizedBox)
        async let photo = warmPhotoRequests(frame, box: box)
        let (faceRequests, photoRequests) = await (vision, photo)
        let incomplete = (faceRequests + photoRequests).filter { !$0.1 }.map { $0.0 }
        let duration = String(format: "%.1f ms", (ProcessInfo.processInfo.systemUptime - started) * 1000)
        return incomplete.isEmpty ? "Completed · \(duration)"
            : "Incomplete · \(incomplete.joined(separator: ", ")) · \(duration)"
    }

    private static func warmFaceRequests(_ buffer: CVPixelBuffer, normalizedBox: CGRect) -> [(String, Bool)] {
        let rectangles = (try? FaceDetector.detectFaces(in: buffer, includeQuality: true)) != nil
        let details = (try? FaceDetector.warmNonemptyPath(in: buffer, normalizedBox: normalizedBox)) != nil
        return [("face rectangles", rectangles), ("landmarks / quality", details)]
    }

    private static func warmPhotoRequests(_ frame: CameraFrame, box: CGRect) async -> [(String, Bool)] {
        async let bezel = (try? DeviceBezelDetector.detect(in: frame.buffer, faceBoundingBox: box)) != nil
        let glare = frame.faceCrop(box).flatMap { GlareCueExtractor.extract(faceCrop: $0) } != nil
        return [("device rectangles", await bezel), ("glare render", glare)]
    }
}

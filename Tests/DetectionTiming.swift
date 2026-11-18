// Run with Sources/Upstream/FaceDetector.swift. Same no-face input at each size.
// Measures detector overhead only. No camera, face samples or credentials.
import CoreVideo
import Foundation

@main
enum DetectionTiming {
    static func main() {
        do { try measure() } catch {
            fputs("Vision benchmark unavailable: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }
    static func measure() throws {
        for size in [(640, 480), (1280, 720), (1920, 1080), (2560, 1440)] {
            var output: CVPixelBuffer?
            guard CVPixelBufferCreate(nil, size.0, size.1, kCVPixelFormatType_32BGRA,
                                      nil, &output) == kCVReturnSuccess, let buffer = output else {
                throw CocoaError(.coderInvalidValue)
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetDataSize(buffer))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            var samples: [Double] = []
            for _ in 0..<11 {
                let before = ProcessInfo.processInfo.systemUptime
                let faces = try FaceDetector.detectFaces(in: buffer, includeQuality: false)
                guard faces.isEmpty else { throw CocoaError(.coderInvalidValue) }
                samples.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
            }
            let warm = samples.dropFirst().sorted()
            print(String(format: "%dx%d blank input: warm median %.1f ms", size.0, size.1, (warm[4] + warm[5]) / 2))
        }
    }
}

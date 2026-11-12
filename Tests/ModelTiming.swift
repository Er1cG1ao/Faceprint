// Component-only benchmark: synthetic input, no camera, face data or vault access.
// swift Tests/ModelTiming.swift Resources/ArcFace.mlmodelc
import Foundation
import CoreML
import CoreVideo

do {
let modelURL = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/ArcFace.mlmodelc")
let configuration = MLModelConfiguration()
configuration.computeUnits = .all
let start = ProcessInfo.processInfo.systemUptime
let model = try MLModel(contentsOf: modelURL, configuration: configuration)
let loaded = ProcessInfo.processInfo.systemUptime
var optional: CVPixelBuffer?
let status = CVPixelBufferCreate(nil, 112, 112, kCVPixelFormatType_32BGRA, nil, &optional)
guard status == kCVReturnSuccess else {
    fputs("Benchmark unavailable: cannot allocate pixel buffer (\(status))\n", stderr)
    exit(2)
}
let buffer = optional!
CVPixelBufferLockBaseAddress(buffer, [])
memset(CVPixelBufferGetBaseAddress(buffer), 0, CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer))
CVPixelBufferUnlockBaseAddress(buffer, [])
let input = try MLDictionaryFeatureProvider(dictionary: ["input_image": MLFeatureValue(pixelBuffer: buffer)])
var durations: [Double] = []
for _ in 0..<8 {
    let before = ProcessInfo.processInfo.systemUptime
    let result = try model.prediction(from: input)
    guard result.featureValue(for: "embedding")?.multiArrayValue?.count == 512 else {
        fputs("Benchmark unavailable: unexpected model output\n", stderr)
        exit(2)
    }
    durations.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
}
let warm = durations.dropFirst().sorted()
print(String(format: "model_load_ms=%.1f first_prediction_ms=%.1f warm_prediction_median_ms=%.1f", (loaded-start)*1000, durations[0], warm[warm.count/2]))
print("Synthetic Core ML component timing only; excludes camera, Vision, matching and AX operations.")

} catch {
    fputs("Benchmark unavailable: \(error.localizedDescription)\n", stderr)
    exit(2)
}

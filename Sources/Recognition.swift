import Foundation
import CoreGraphics

struct FaceRecognitionResult {
    let embedding: [Float]
    let alignmentTier: AlignmentTier
    let face: DetectedFace
}

struct FaceTemplate: Codable, Sendable {
    let modelIdentifier: String
    let samples: [[Float]]
    let poses: [String]?

    init(modelIdentifier: String, samples: [[Float]], poses: [String]? = nil) {
        self.modelIdentifier = modelIdentifier
        self.samples = samples
        self.poses = poses
    }

    func matches(_ embedding: [Float]) -> Bool {
        guard modelIdentifier == "arcface-w600k_mbf-v1",
              samples.count >= 12,
              embedding.count == 512,
              samples.allSatisfy({ $0.count == 512 && $0.allSatisfy(\.isFinite) }) else { return false }
        let centroid = FaceEmbedding.l2Normalized((0..<512).map { index in
            samples.reduce(Float(0)) { $0 + $1[index] } / Float(samples.count)
        })
        let best = samples.map { FaceEmbedding.cosineSimilarity($0, embedding) }.max() ?? 0
        return FaceEmbedding.cosineSimilarity(centroid, embedding) >= 0.66 && best >= 0.66
    }
}

enum SecureFaceStore {
    static func save(_ template: FaceTemplate) throws {
        var data = try JSONEncoder().encode(template)
        defer { data.resetBytes(in: 0..<data.count) }
        try SecureCredentialManager.saveFaceData(data)
    }

    static func load() throws -> FaceTemplate? {
        guard var data = try SecureCredentialManager.readFaceData() else { return nil }
        defer { data.resetBytes(in: 0..<data.count) }
        return try JSONDecoder().decode(FaceTemplate.self, from: data)
    }
}

final class Recognizer: @unchecked Sendable {
    private let embedder: ArcFaceEmbedder
    init() throws {
        embedder = try ArcFaceEmbedder()
        // Warm Core ML's first prediction before a real camera frame is needed.
        // This blank input is discarded; it is never a face template or match.
        let size = FaceAligner.outputSize
        if let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
            bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let image = context.makeImage() {
            _ = try embedder.embedding(for: image)
        }
    }

    func recognize(_ image: CGImage, minimumFaceWidth: CGFloat = 0.21, includeQuality: Bool = true) throws -> FaceRecognitionResult? {
        let faces = try FaceDetector.detectFaces(in: image, includeQuality: includeQuality)
        let candidates = faces.filter { $0.normalizedBoundingBox.width >= minimumFaceWidth }
        guard candidates.count == 1, let face = candidates.first,
              let aligned = FaceAligner.align(face, from: image) else { return nil }
        let embedding = try embedder.embedding(for: aligned.image)
        guard embedding.count == 512, embedding.allSatisfy(\.isFinite) else { return nil }
        return FaceRecognitionResult(embedding: embedding, alignmentTier: aligned.tier, face: face)
    }
}

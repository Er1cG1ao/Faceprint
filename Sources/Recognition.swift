import CoreVideo
import Foundation
import CoreGraphics
import AppKit

struct FaceRecognitionResult {
    let embedding: [Float]
    let alignmentTier: AlignmentTier
    let face: DetectedFace
}

struct FaceTemplate: Codable, Sendable {
    let modelIdentifier: String
    let samples: [[Float]]
    let poses: [String]?
    let qualities: [Float?]?

    init(modelIdentifier: String, samples: [[Float]], poses: [String]? = nil, qualities: [Float?]? = nil) {
        self.modelIdentifier = modelIdentifier
        self.samples = samples
        self.poses = poses
        self.qualities = qualities
    }

    struct Matcher: Sendable {
        let samples: [[Float]]
        let centroid: [Float]

        func score(_ embedding: [Float]) -> Float? {
            guard embedding.count == 512, embedding.allSatisfy(\.isFinite) else { return nil }
            let best = samples.map { FaceEmbedding.cosineSimilarity($0, embedding) }.max() ?? 0
            return min(FaceEmbedding.cosineSimilarity(centroid, embedding), best)
        }
    }

    func prepareMatcher() -> Matcher? {
        guard modelIdentifier == "arcface-w600k_mbf-v1",
              samples.count >= 12,
              samples.allSatisfy({ $0.count == 512 && $0.allSatisfy(\.isFinite) }) else { return nil }
        let centroid = FaceEmbedding.l2Normalized((0..<512).map { index in
            samples.reduce(Float(0)) { $0 + $1[index] } / Float(samples.count)
        })
        return Matcher(samples: samples, centroid: centroid)
    }

    func score(_ embedding: [Float]) -> Float? { prepareMatcher()?.score(embedding) }

    func matches(_ embedding: [Float]) -> Bool { (score(embedding) ?? -1) >= 0.66 }

}

struct FaceIdentity: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var template: FaceTemplate

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, template: FaceTemplate) {
        self.id = id; self.name = name; self.isEnabled = isEnabled; self.template = template
    }
}

struct FaceIdentityCollection: Codable, Sendable {
    let version: Int
    var identities: [FaceIdentity]
    init(identities: [FaceIdentity]) { version = 1; self.identities = identities }

    static func decode(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        if let collection = try? decoder.decode(Self.self, from: data) {
            guard collection.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            return collection
        }
        let legacy = try decoder.decode(FaceTemplate.self, from: data)
        return Self(identities: [FaceIdentity(name: NSFullUserName(), template: legacy)])
    }

    func prepareMatchers() -> [FaceTemplate.Matcher] {
        identities.filter(\.isEnabled).compactMap { $0.template.prepareMatcher() }
    }

    func matches(_ embedding: [Float]) -> Bool {
        identities.contains { $0.isEnabled && $0.template.matches(embedding) }
    }
}

enum SecureFaceStore {
    static func saveIdentities(_ identities: [FaceIdentity]) throws {
        var data = try JSONEncoder().encode(FaceIdentityCollection(identities: identities))
        defer { data.resetBytes(in: 0..<data.count) }
        try SecureCredentialManager.saveFaceData(data)
    }

    static func loadIdentities() throws -> [FaceIdentity] {
        guard var data = try SecureCredentialManager.readFaceData() else { return [] }
        defer { data.resetBytes(in: 0..<data.count) }
        return try FaceIdentityCollection.decode(data).identities
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

    func recognize(_ buffer: CVPixelBuffer, sourceScale: CGFloat, enrollment: Bool = false,
                   includeQuality: Bool = true) throws -> FaceRecognitionResult? {
        let faces = try FaceDetector.detectFaces(in: buffer, includeQuality: includeQuality)
        guard DistancePolicy.faceCountRejection(faces.count) == nil, let face = faces.first,
              let aligned = FaceAligner.align(face, from: buffer) else { return nil }
        if !enrollment {
            let eyes = face.landmarks.flatMap { LandmarkGeometry.interocularDistance(from: $0, imageSize: face.imageSize) }
            guard DistancePolicy.rejection(width: face.boundingBox.width * sourceScale,
                fraction: face.normalizedBoundingBox.width, quality: face.quality, tier: aligned.tier,
                eyeDistance: eyes.map { $0 * sourceScale }) == nil else { return nil }
        }
        let embedding = try embedder.embedding(for: aligned.image)
        guard embedding.count == 512, embedding.allSatisfy(\.isFinite) else { return nil }
        return FaceRecognitionResult(embedding: embedding, alignmentTier: aligned.tier, face: face)
    }
}

enum DistancePolicy {
    static func faceCountRejection(_ count: Int) -> String? {
        switch count {
        case 1: return nil
        case 0: return "No face"
        default: return "Multiple faces"
        }
    }

    static func rejection(width: CGFloat, fraction: CGFloat, quality: Float?, tier: AlignmentTier, eyeDistance: CGFloat?) -> String? {
        // At VGA the old 21% gate required about 134 source pixels.
        guard width >= 112 else { return "Too few source pixels" }
        if fraction >= 0.21 { return nil }
        // Below the 10% target, require at least the old VGA pixel budget.
        guard fraction >= 0.10 || width >= 135 else { return "Too few pixels for a distant face" }
        guard let quality, quality >= 0.30 else { return "Low capture quality" }
        guard tier == .fivePoint, let eyeDistance, eyeDistance >= 30 else { return "Unreliable landmarks" }
        return nil
    }
}

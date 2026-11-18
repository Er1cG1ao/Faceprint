//
//  FaceAligner.swift
//  glance
//
//  ArcFace requires faces warped into a canonical pose (eyes level, fixed positions) — a loose crop tanks its accuracy.
//  Solves the 2D similarity transform mapping 5 detected landmarks onto the standard ArcFace template, then warps.
//

import CoreImage
import Vision
import CoreGraphics

struct AlignedFace {
    let image: CGImage   // 112x112, canonically aligned
    let tier: AlignmentTier
}

enum AlignmentTier: String {
    case fivePoint = "5-point"
    case twoPoint = "2-point (eyes only)"
    case paddedCrop = "padded crop (no alignment)"
}

nonisolated enum FaceAligner {
    static let outputSize = 112

    /// Standard ArcFace 112x112 template: left eye, right eye, nose, left mouth, right mouth. "Left"/"right" are
    /// on-screen, not anatomical — see the ordering fix in `fivePoints(from:imageSize:)`.
    private static let referencePoints: [CGPoint] = [
        CGPoint(x: 38.2946, y: 51.6963),
        CGPoint(x: 73.5318, y: 51.5014),
        CGPoint(x: 56.0252, y: 71.7366),
        CGPoint(x: 41.5493, y: 92.3655),
        CGPoint(x: 70.7299, y: 92.2041),
    ]
    private static let eyeReferencePoints = Array(referencePoints[0...1])

    /// Best-effort: 5-point landmarks, falling back to 2-point (eyes only), falling back to a padded crop.
    private static let context = CIContext(options: [.cacheIntermediates: false])
    static func align(_ face: DetectedFace, from buffer: CVPixelBuffer) -> AlignedFace? {
        let input = CIImage(cvPixelBuffer: buffer)
        let size = input.extent.size
        if let landmarks = face.landmarks {
            if let points = fivePoints(from: landmarks, imageSize: size),
               let image = warp(input, points, referencePoints) { return AlignedFace(image: image, tier: .fivePoint) }
            if let eyes = twoPoints(from: landmarks, imageSize: size),
               let image = warp(input, eyes, eyeReferencePoints) { return AlignedFace(image: image, tier: .twoPoint) }
        }
        let box = face.boundingBox.insetBy(dx: -face.boundingBox.width * 0.2, dy: -face.boundingBox.height * 0.2)
        let rect = CGRect(x: box.minX, y: size.height - box.maxY, width: box.width, height: box.height)
            .intersection(input.extent)
        guard !rect.isEmpty else { return nil }
        let crop = input.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
        let scale = CGAffineTransform(scaleX: CGFloat(outputSize) / rect.width, y: CGFloat(outputSize) / rect.height)
        guard let image = render(crop, scale) else { return nil }
        return AlignedFace(image: image, tier: .paddedCrop)
    }

    // MARK: - Landmark extraction
    //
    // Point/centroid/eye-center/transform math lives in `LandmarkGeometry`, shared with the liveness analyzer.

    private static func fivePoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let eyeA = LandmarkGeometry.eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let eyeB = LandmarkGeometry.eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize),
              let nose = landmarks.nose, let noseCenter = LandmarkGeometry.centroid(of: nose, imageSize: imageSize),
              let outerLips = landmarks.outerLips else { return nil }

        // Vision's leftEye/rightEye are anatomical, not on-screen — sort by x instead of trusting either label.
        let imageLeftEye = eyeA.x <= eyeB.x ? eyeA : eyeB
        let imageRightEye = eyeA.x <= eyeB.x ? eyeB : eyeA

        let lipPoints = LandmarkGeometry.imagePoints(of: outerLips, imageSize: imageSize)
        guard let imageLeftMouth = lipPoints.min(by: { $0.x < $1.x }),
              let imageRightMouth = lipPoints.max(by: { $0.x < $1.x }) else { return nil }

        return [imageLeftEye, imageRightEye, noseCenter, imageLeftMouth, imageRightMouth]
    }

    private static func twoPoints(from landmarks: VNFaceLandmarks2D, imageSize: CGSize) -> [CGPoint]? {
        guard let eyeA = LandmarkGeometry.eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize),
              let eyeB = LandmarkGeometry.eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize) else { return nil }
        return eyeA.x <= eyeB.x ? [eyeA, eyeB] : [eyeB, eyeA]
    }

    // MARK: - Warp

    private static func warp(_ input: CIImage, _ source: [CGPoint], _ destination: [CGPoint]) -> CGImage? {
        let src = source.map { CGPoint(x: $0.x, y: input.extent.height - $0.y) }
        let dst = destination.map { CGPoint(x: $0.x, y: CGFloat(outputSize) - $0.y) }
        guard let transform = LandmarkGeometry.solveSimilarityTransform(from: src, to: dst) else { return nil }
        return render(input, transform)
    }

    private static func render(_ image: CIImage, _ transform: CGAffineTransform) -> CGImage? {
        let aligned = image.transformed(by: transform, highQualityDownsample: true)
        return context.createCGImage(aligned, from: CGRect(x: 0, y: 0, width: outputSize, height: outputSize),
                                     format: .BGRA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }
}

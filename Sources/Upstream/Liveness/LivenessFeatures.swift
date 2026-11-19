//
//  LivenessFeatures.swift
//  glance
//
//  Vision-facing half of liveness: turns a `FaceRecognitionResult` into a plain,
//  Vision-free `LivenessFrame` — keeps the decision logic compilable standalone.
//

import Vision
import CoreGraphics

nonisolated enum LivenessFeatureExtractor {
    /// Check the full frame for a device bezel and the native-sized face
    /// region for glare. Both branches read the same immutable camera frame.
    static func extract(from result: FaceRecognitionResult, frame: CameraFrame) async throws -> LivenessFrame {
        let face = result.face
        async let bezel = DeviceBezelDetector.detect(in: frame.buffer, faceBoundingBox: face.boundingBox)
        async let glareSample = glare(in: frame, box: face.boundingBox)
        let (device, glare) = try await (bezel, glareSample)
        try Task.checkCancellation()
        let deviceOverlap = device.faceOverlapFraction
        let timestamp = Date()

        guard let landmarks = face.landmarks else {
            return LivenessFrame(
                timestamp: timestamp, landmarks: [], interocularDistance: nil,
                yaw: face.yaw,
                leftEyeAspectRatio: nil, rightEyeAspectRatio: nil,
                noseOffsetRatio: nil,
                hasReliableLandmarks: false,
                deviceOverlapFraction: deviceOverlap,
                glare: glare
            )
        }

        let imageSize = face.imageSize
        let points = LandmarkGeometry.allPoints(from: landmarks, imageSize: imageSize)
        let interocular = LandmarkGeometry.interocularDistance(from: landmarks, imageSize: imageSize)
        let leftEAR = landmarks.leftEye.flatMap { LandmarkGeometry.eyeAspectRatio(of: $0, imageSize: imageSize) }
        let rightEAR = landmarks.rightEye.flatMap { LandmarkGeometry.eyeAspectRatio(of: $0, imageSize: imageSize) }

        let eyeLeft = LandmarkGeometry.eyeCenter(pupil: landmarks.leftPupil, eye: landmarks.leftEye, imageSize: imageSize)
        let eyeRight = LandmarkGeometry.eyeCenter(pupil: landmarks.rightPupil, eye: landmarks.rightEye, imageSize: imageSize)

        var noseOffsetRatio: CGFloat?
        if let interocular, interocular > 0, let eyeLeft, let eyeRight,
           let nose = landmarks.nose, let noseCenter = LandmarkGeometry.centroid(of: nose, imageSize: imageSize) {
            let eyeMidX = (eyeLeft.x + eyeRight.x) / 2
            noseOffsetRatio = (noseCenter.x - eyeMidX) / interocular
        }

        return LivenessFrame(
            timestamp: timestamp,
            landmarks: points,
            interocularDistance: interocular,
            yaw: face.yaw,
            leftEyeAspectRatio: leftEAR, rightEyeAspectRatio: rightEAR,
            noseOffsetRatio: noseOffsetRatio,
            hasReliableLandmarks: result.alignmentTier == .fivePoint,
            deviceOverlapFraction: deviceOverlap,
            glare: glare
        )
    }
    private static func glare(in frame: CameraFrame, box: CGRect) throws -> GlareSample? {
        guard let crop = frame.faceCrop(box) else {
            throw FillError.message("Photo check frame unavailable.")
        }
        return GlareCueExtractor.extract(faceCrop: crop)
    }
}

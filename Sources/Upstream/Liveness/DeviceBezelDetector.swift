//
//  DeviceBezelDetector.swift
//  glance
//
//  Looks for a device bezel (phone/tablet) around the face via
//  VNDetectRectanglesRequest. Plausible rectangles request additional active
//  checks in Faceprint; a rectangle alone does not decide liveness.
//

import Vision
import CoreGraphics

struct DeviceBezelObservation {
    /// Largest device-plausible rectangle found this frame, same pixel space as `DetectedFace.boundingBox`.
    let rectangle: CGRect?
    /// Fraction of the face's bounding box area that falls inside `rectangle`.
    let faceOverlapFraction: CGFloat?

    nonisolated static let none = DeviceBezelObservation(rectangle: nil, faceOverlapFraction: nil)
}

nonisolated enum DeviceBezelDetector {
    /// First-pass estimates, not validated against real footage — tune here if false positives/negatives show up.
    private static func makeRequest() -> VNDetectRectanglesRequest {
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = 0.85
        // Normalized minimum rectangle side length.
        request.minimumSize = 0.15
        request.maximumObservations = 8
        // Covers phone-in-portrait (0.35) through near-square tablet crop (1.0).
        request.minimumAspectRatio = 0.35
        request.maximumAspectRatio = 1.0
        // Generous so a phone held at a slight angle still registers.
        request.quadratureTolerance = 30

        return request
    }

    /// Synchronous and CPU-bound — call from a background task, same as `FaceDetector.detectFaces`.
    static func detect(in image: CGImage, faceBoundingBox: CGRect) -> DeviceBezelObservation {
        let request = makeRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let results = request.results, !results.isEmpty
        else { return .none }

        let imageSize = CGSize(width: image.width, height: image.height)
        let candidates = results.map { FaceDetector.convertToImageSpace($0.boundingBox, imageSize: imageSize) }
            .filter { isPlausibleDevice($0, enclosing: faceBoundingBox, imageSize: imageSize) }
        guard let largest = candidates.max(by: { $0.width * $0.height < $1.width * $1.height }) else {
            return .none
        }

        let faceArea = faceBoundingBox.width * faceBoundingBox.height
        guard faceArea > 0 else { return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: nil) }
        let intersection = largest.intersection(faceBoundingBox)
        let overlap = (intersection.width * intersection.height) / faceArea
        return DeviceBezelObservation(rectangle: largest, faceOverlapFraction: overlap)
    }

    /// Background windows and frames can overlap the face in a webcam image.
    /// Require a mostly enclosed face and a device-sized rectangle before using
    /// this as a reason to ask for additional motion checks.
    static func isPlausibleDevice(_ rectangle: CGRect, enclosing face: CGRect, imageSize: CGSize) -> Bool {
        let rectangleArea = rectangle.width * rectangle.height
        let faceArea = face.width * face.height
        let imageArea = imageSize.width * imageSize.height
        guard rectangleArea > 0, faceArea > 0, imageArea > 0 else { return false }
        let overlap = rectangle.intersection(face)
        guard !overlap.isNull, !overlap.isEmpty else { return false }
        let faceContainment = overlap.width * overlap.height / faceArea
        let faceFraction = faceArea / rectangleArea
        let frameFraction = rectangleArea / imageArea
        return faceContainment >= 0.9 && (0.15...0.8).contains(faceFraction) && frameFraction <= 0.6
    }
}


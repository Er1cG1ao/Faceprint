import Foundation
import Observation
import SwiftUI

/// Enrollment-only adapter for Glance's original notch, tick ring, circular
/// camera view, directional sweeps, and completion-checkmark views.
@Observable
@MainActor
final class OnboardingController {
    let camera: Camera
    private(set) var step = OnboardingStep.enroll
    var faceName = ""
    private var nameContinuation: CheckedContinuation<String, Error>?
    private var nameRequestID: UUID?
    private let sweepWindow = EnrollmentSweepWindowController()
    var onCancel: (() -> Void)?
    private(set) var currentPoseIndex = 0
    private(set) var capturedPoses: Set<EnrollmentPose> = []
    private(set) var centerPulseTick = 0
    private(set) var enrollmentComplete = false
    private(set) var guideVisible = false
    private(set) var cameraPreviewVisible = true
    private(set) var showCheckmark = false
    private(set) var isTooFar = false
    private(set) var faceDetected = false
    private(set) var currentYaw: Float?
    private(set) var currentPitch: Float?
    private(set) var excessiveTurn = false

    init(camera: Camera) { self.camera = camera }

    var currentPose: EnrollmentPose? { EnrollmentPose(rawValue: currentPoseIndex) }
    var panelSize: CGSize {
        let geometry = NotchGeometry.preferredScreen().map(NotchGeometry.forScreen) ?? NotchGeometry.forMainScreen()
        return OnboardingMetrics.panelSize(for: step, style: geometry.style)
    }
    var panelBottomRadius: CGFloat { OnboardingMetrics.panelBottomRadius(for: step) }

    var enrollmentInstruction: String {
        if enrollmentComplete { return "Face captured" }
        if !faceDetected { return "Look straight at the camera" }
        if isTooFar { return "Bring your face closer" }
        if excessiveTurn { return "Turn a little less" }
        return currentPose?.instruction ?? ""
    }

    struct HeadTurn: Equatable {
        let angle: Double
        let progress: Double
    }

    var headTurn: HeadTurn? {
        guard !enrollmentComplete, faceDetected, !isTooFar, !excessiveTurn,
              let pose = currentPose, pose != .center,
              let yaw = currentYaw, let pitch = currentPitch else { return nil }
        let x = Double(-yaw / (0.24 / pose.matchLeniency))
        let y = Double(-pitch / (0.17 / pose.matchLeniency))
        let magnitude = hypot(x, y)
        guard magnitude > 0.15 else { return nil }
        let angle = atan2(x, y) * 180 / .pi
        return HeadTurn(angle: angle < 0 ? angle + 360 : angle, progress: min(magnitude, 1))
    }

    func back() {
        if step == .name {
            nameContinuation?.resume(throwing: EnrollmentNameAction.recapture)
            nameContinuation = nil; nameRequestID = nil
        } else { onCancel?() }
    }
    func saveName() {
        let trimmed = faceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nameContinuation?.resume(returning: String(trimmed.prefix(80)))
        nameContinuation = nil; nameRequestID = nil
    }

    func nameCapturedFace(suggestedName: String) async throws -> String {
        try Task.checkCancellation()
        camera.stop()
        faceName = suggestedName
        let request = UUID()
        nameRequestID = request
        withAnimation(OnboardingMetrics.stepAnimation) { step = .name }
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { nameContinuation = continuation }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                guard let self, self.nameRequestID == request else { return }
                self.nameContinuation?.resume(throwing: CancellationError())
                self.nameContinuation = nil; self.nameRequestID = nil
            }
        })
    }

    func dismiss() {
        nameContinuation?.resume(throwing: CancellationError())
        nameContinuation = nil; nameRequestID = nil
        sweepWindow.dismiss()
        NotchOverlayController.shared.dismissOnboarding()
    }

    func capture(using recognizer: Recognizer, deviceID: String) async throws -> FaceTemplate {
        withAnimation(OnboardingMetrics.stepAnimation) { step = .enroll }
        currentPoseIndex = 0
        capturedPoses = []
        centerPulseTick = 0
        enrollmentComplete = false
        guideVisible = false
        cameraPreviewVisible = true
        showCheckmark = false
        faceDetected = false
        currentYaw = nil
        currentPitch = nil
        excessiveTurn = false
        isTooFar = false
        NotchOverlayController.shared.presentOnboarding(self)
        try await camera.start(deviceID: deviceID)
        try Task.checkCancellation()
        guideVisible = true
        sweepWindow.present(for: self)
        let captureReadyAt = Date().addingTimeInterval(1.5)
        var poseStartedAt = Date()
        var heldSince: Date?
        var matchStreak = 0
        var capturedForPose = 0
        var samples: [[Float]] = []
        var poses: [String] = []
        var qualities: [Float?] = []
        var lastFrame: UInt64?

        while let pose = currentPose {
            try Task.checkCancellation()
            guard Date().timeIntervalSince(poseStartedAt) < 60 else {
                throw FillError.message("This direction timed out. Start enrollment again when ready.")
            }
            guard let frame = camera.latestFrame(), frame.id != lastFrame else {
                try await Task.sleep(nanoseconds: 30_000_000)
                continue
            }
            lastFrame = frame.id
            let result = try await Task.detached {
                try recognizer.recognize(frame.image, minimumFaceWidth: 0.05)
            }.value
            try Task.checkCancellation()
            guard let result, let yaw = result.face.yaw, let pitch = result.face.pitch else {
                faceDetected = false
                heldSince = nil
                matchStreak = 0
                continue
            }
            faceDetected = true
            currentYaw = yaw
            currentPitch = pitch
            isTooFar = result.face.normalizedBoundingBox.width < 0.2
            excessiveTurn = abs(yaw) >= 0.51 || abs(pitch) >= 0.37
            let poseOK = EnrollmentPoseMatcher.matches(yaw: yaw, pitch: pitch, pose: pose,
                                                       widened: Date().timeIntervalSince(poseStartedAt) > 12)
            guard Date() >= captureReadyAt, !isTooFar, !excessiveTurn, poseOK,
                  result.alignmentTier == .fivePoint, (result.face.quality ?? 1) >= 0.2 else {
                heldSince = nil
                matchStreak = 0
                continue
            }
            if heldSince == nil { heldSince = Date() }
            guard Date().timeIntervalSince(heldSince!) >= 0.5 else { continue }
            matchStreak += 1
            guard matchStreak >= 3 else { continue }
            matchStreak = 0
            samples.append(result.embedding)
            qualities.append(result.face.quality)
            poses.append(pose.name)
            capturedForPose += 1
            if capturedForPose == 2 {
                if pose == .center { centerPulseTick += 1 }
                else { capturedPoses.insert(pose) }
                currentPoseIndex += 1
                capturedForPose = 0
                poseStartedAt = Date()
                heldSince = nil
            }
            try await Task.sleep(nanoseconds: 60_000_000)
        }

        try Task.checkCancellation()
        enrollmentComplete = true
        guideVisible = false
        sweepWindow.dismiss()
        try await Task.sleep(for: .seconds(OnboardingMetrics.guideOverlayFadeOut))
        cameraPreviewVisible = false
        try await Task.sleep(for: .seconds(OnboardingMetrics.previewFadeOut + OnboardingMetrics.checkmarkDelay))
        showCheckmark = true
        let elapsed = OnboardingMetrics.guideOverlayFadeOut + OnboardingMetrics.previewFadeOut + OnboardingMetrics.checkmarkDelay
        try await Task.sleep(for: .seconds(max(OnboardingMetrics.cameraCompleteToNameDelay - elapsed, 0)))
        try Task.checkCancellation()
        return FaceTemplate(modelIdentifier: "arcface-w600k_mbf-v1", samples: samples, poses: poses, qualities: qualities)
    }
}

enum EnrollmentNameAction: Error { case recapture }

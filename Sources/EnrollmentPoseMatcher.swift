import Foundation

/// Uses Glance's nine poses and the same angular bands and capture timing.
enum EnrollmentPoseMatcher {
    static func matches(yaw: Float, pitch: Float, pose: EnrollmentPose, widened: Bool) -> Bool {
        let factor: Float = (widened ? 1.25 : 1) * pose.matchLeniency
        let yawOK: Bool
        switch pose.yawBand {
        case .none: yawOK = abs(yaw) < 0.18 * factor
        case .left: yawOK = yaw > 0.24 / factor && yaw < 0.51
        case .right: yawOK = yaw < -0.24 / factor && yaw > -0.51
        }
        let pitchOK: Bool
        switch pose.pitchBand {
        case .none: pitchOK = abs(pitch) < 0.15 * factor
        case .up: pitchOK = pitch < -0.17 / factor && pitch > -0.37
        case .down: pitchOK = pitch > 0.17 / factor && pitch < 0.37
        }
        return yawOK && pitchOK
    }
}


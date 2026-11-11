import Foundation

enum InputActionPolicy {
    static func canEnable(sessionUnlocked: Bool, hasFace: Bool, hasPassword: Bool, busy: Bool) -> Bool {
        sessionUnlocked && hasFace && hasPassword && !busy
    }

    static func shouldPressReturn(enabled: Bool, verified: Bool) -> Bool {
        enabled && verified
    }
}

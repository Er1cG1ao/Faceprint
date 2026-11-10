import Foundation

enum InputActionPolicy {
    static func shouldPressReturn(enabled: Bool, testMode: Bool, verified: Bool) -> Bool {
        enabled && !testMode && verified
    }
}

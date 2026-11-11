import Foundation

struct SettingsAccessState {
    private(set) var isUnlocked = false
    private var revision: UInt64 = 0

    mutating func beginAuthorization() -> UInt64 {
        revision &+= 1
        isUnlocked = false
        return revision
    }
    func accepts(_ ticket: UInt64) -> Bool { ticket == revision }
    @discardableResult mutating func completeAuthorization(_ ticket: UInt64) -> Bool {
        guard accepts(ticket) else { return false }
        isUnlocked = true
        return true
    }
    mutating func lock() { revision &+= 1; isUnlocked = false }
}

enum InputActionPolicy {
    static func canEnable(dataSessionReady: Bool, hasFace: Bool, hasPassword: Bool, busy: Bool) -> Bool {
        dataSessionReady && hasFace && hasPassword && !busy
    }
    static func canChangeSettings(settingsUnlocked: Bool, busy: Bool) -> Bool {
        settingsUnlocked && !busy
    }
    static func shouldPressReturn(enabled: Bool, verified: Bool) -> Bool { enabled && verified }
}

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

/// Password-card animations can expose a field before keyboard input is ready.
/// Require the same empty, focused field to settle, including an initial grace.
struct PasswordFieldReadiness {
    private var stableSince: TimeInterval?
    mutating func observe(sameField: Bool, focusedAndEmpty: Bool, now: TimeInterval) -> Bool {
        guard focusedAndEmpty else { stableSince = nil; return false }
        if !sameField || stableSince == nil { stableSince = now }
        return now >= 0.75 && now - (stableSince ?? now) >= 0.5
    }
}

/// The biometric and password stages are one attempt even if AX recreates fields.
/// A short animation gap must not authorize a second automatic face scan.
struct PromptAttemptGate {
    private var attempted: String?
    private var absentSince: TimeInterval?
    mutating func mark(_ key: String) { attempted = key; absentSince = nil }
    mutating func reset() { attempted = nil; absentSince = nil }
    mutating func observe(_ key: String?, now: TimeInterval) -> Bool {
        guard let key else {
            if absentSince == nil { absentSince = now }
            if now - (absentSince ?? now) >= 2 { reset() }
            return false
        }
        absentSince = nil
        return key != attempted
    }
}

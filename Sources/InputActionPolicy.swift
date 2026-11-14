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
    static func canEnable(dataSessionReady: Bool, hasFace: Bool, hasPassword: Bool) -> Bool {
        dataSessionReady && hasFace && hasPassword
    }
    static func canChangeSettings(settingsUnlocked: Bool, authenticating: Bool) -> Bool {
        settingsUnlocked && !authenticating
    }
    static func secureFieldLength(characterCount: Int?, value: String?) -> Int? {
        let counts = [characterCount, value?.utf16.count].compactMap { $0 }.filter { $0 >= 0 }
        return counts.max()
    }
    static func shouldPressReturn(enabledAtStart: Bool, enabledNow: Bool, verified: Bool) -> Bool {
        enabledAtStart && enabledNow && verified
    }
}

/// Password-card animations can expose a field before keyboard input is ready.
/// Require a fresh confirmation of the same empty, focused field, without a fixed animation delay.
struct PasswordFieldReadiness {
    private var stableSince: TimeInterval?
    mutating func observe(sameField: Bool, focusedAndEmpty: Bool, now: TimeInterval) -> Bool {
        guard focusedAndEmpty else { stableSince = nil; return false }
        if !sameField || stableSince == nil { stableSince = now }
        return now - (stableSince ?? now) >= 0.04
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

/// Run synchronous AX and keyboard work away from UI rendering, while preserving
/// cancellation when filling is disabled, the screen locks or the user switches.
func performPromptWork<T>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
    let task = Task.detached(priority: .userInitiated) {
        try Task.checkCancellation()
        return try await work()
    }
    return try await withTaskCancellationHandler(operation: { try await task.value }, onCancel: { task.cancel() })
}

struct FaceMatchGate {
    private var lastFrame: UInt64?
    private var consecutive = 0
    mutating func observe(frame: UInt64, matched: Bool) -> Bool {
        guard frame != lastFrame else { return false }
        lastFrame = frame
        consecutive = matched ? consecutive + 1 : 0
        return consecutive >= 2
    }
}

/// One automatic retry per visible authentication request. Manual retry starts
/// a new budget; a retry never reuses a face match or retries password delivery.
struct AutomaticRetryBudget {
    private var request: String?
    private var spent = false
    private var absentSince: TimeInterval?
    mutating func observe(_ key: String) {
        absentSince = nil
        if request != key { request = key; spent = false }
    }
    mutating func observeAbsence(now: TimeInterval) {
        if absentSince == nil { absentSince = now }
        if now - (absentSince ?? now) >= 2 { reset() }
    }
    mutating func reset() { request = nil; spent = false; absentSince = nil }
    mutating func claim(for key: String, enabled: Bool, recognitionFailed: Bool) -> Bool {
        observe(key)
        guard enabled, recognitionFailed, !spent else { return false }
        spent = true
        return true
    }
}

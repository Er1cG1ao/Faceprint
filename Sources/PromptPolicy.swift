import Foundation

enum PromptPolicy {
    static let privacyBundleID = "com.apple.settings.PrivacySecurity.extension"
    static let autofillBundleIDs: Set<String> = [
        "com.apple.Passwords",
        "com.apple.LocalAuthentication.UIAgent",
        "com.apple.LocalAuthenticationRemoteService"
    ]

    static let authenticationBundleIDs: Set<String> = [
        "com.apple.SecurityAgent", "com.apple.securityagent",
        "com.apple.LocalAuthentication.UIAgent", "com.apple.LocalAuthenticationRemoteService"
    ]
    static func supportsOwner(_ bundleID: String) -> Bool {
        bundleID == privacyBundleID || bundleID == "com.apple.systempreferences"
            || bundleID == "com.apple.finder" || autofillBundleIDs.contains(bundleID)
            || authenticationBundleIDs.contains(bundleID)
    }

    /// Shared context between biometric and password stages. Host identity is
    /// independently verified with Apple's code signature before any action.
    static func systemDialogContext(in strings: [String], ownerBundleID: String) -> String? {
        let normalized = strings.map(canonical)
        let text = normalized.joined(separator: " ")
        guard !text.contains("faceprint"), normalized.contains("cancel") else { return nil }
        if ownerBundleID == privacyBundleID || ownerBundleID == "com.apple.systempreferences"
            || authenticationBundleIDs.contains(ownerBundleID) {
            if text.contains("privacy & security"),
               text.contains("to continue with privacy & security"),
               text.contains("modify your system settings") || text.contains("unlock system settings") {
                return "privacy"
            }
        }
        if ownerBundleID == "com.apple.finder" || authenticationBundleIDs.contains(ownerBundleID) {
            guard text.contains("to continue with \"finder\"") else { return nil }
            if text.contains("finder wants to make changes.") { return "finder-changes" }
            guard let heading = normalized.first(where: {
                      $0.hasPrefix("finder wants to move ") && $0.hasSuffix(" to the trash.")
                  }) else { return nil }
            // Include the exact request heading: another file operation cannot
            // be mistaken for the continuation of the enrolled-face scan.
            return "finder-trash:" + heading
        }
        return nil
    }

    static func canonical(_ text: String) -> String {
        text.replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }

    /// A native Passwords authentication prompt contains this heading, the
    /// current account, and explicit Passwords continuation text. This rejects
    /// Faceprint's own session-authentication prompt and unrelated dialogs.
    static func autofillContext(in strings: [String], accountNames: [String]) -> String? {
        let normalized = strings.map(canonical)
        let text = normalized.joined(separator: " ")
        guard normalized.contains("ok"), normalized.contains("cancel"),
              text.contains("to continue with passwords"),
              accountNames.filter({ !$0.isEmpty }).contains(where: {
                  text.contains("enter the password for the user \"\(canonical($0))\"")
              }), let start = text.range(of: "autofill for \"") else { return nil }
        let suffix = text[start.upperBound...]
        guard let closing = suffix.firstIndex(of: "\""), closing > suffix.startIndex else { return nil }
        return "autofill:" + suffix[..<closing]
    }
}

extension PromptPolicy {
    static func isPasswordFallbackButton(_ title: String) -> Bool {
        let label = canonical(title).replacingOccurrences(of: "…", with: "...")
        return label == "use password" || label == "use password..."
    }

    /// Touch ID stage only. Unrelated LocalAuthentication requests, including
    /// Faceprint's own settings/data authentication, must not trigger a scan.
    static func biometricContext(in strings: [String], ownerBundleID: String) -> String? {
        let normalized = strings.map(canonical)
        let text = normalized.joined(separator: " ")
        guard normalized.contains(where: isPasswordFallbackButton), normalized.contains("cancel"),
              text.contains("touch id"), !text.contains("faceprint") else { return nil }
        if let context = systemDialogContext(in: strings, ownerBundleID: ownerBundleID) { return context }
        guard autofillBundleIDs.contains(ownerBundleID), text.contains("passwords"),
              let start = text.range(of: "autofill for \"") else { return nil }
        let suffix = text[start.upperBound...]
        guard let end = suffix.firstIndex(of: "\""), end > suffix.startIndex else { return nil }
        return "autofill:" + suffix[..<end]
    }

    /// The ordinary fallback route stays bound to one process and context.
    /// Cross-host continuation additionally requires permitsHostHandoff evidence.
    static func isSameFallbackRequest(originalPID: Int32, passwordPID: Int32,
                                      originalBundleID: String, passwordBundleID: String,
                                      originalContext: String, passwordContext: String) -> Bool {
        originalPID == passwordPID && originalBundleID == passwordBundleID
            && originalContext == passwordContext
    }
}

extension PromptPolicy {
    static func requestHeading(in strings: [String]) -> String? {
        var headings = Set<String>()
        for string in strings.map(canonical) {
            for heading in ["privacy & security is trying to modify your system settings.",
                            "privacy & security is trying to unlock system settings.",
                            "finder wants to make changes."] where string.contains(heading) {
                headings.insert(heading)
            }
            if let start = string.range(of: "finder wants to move "),
               let end = string.range(of: " to the trash.", range: start.upperBound..<string.endIndex) {
                headings.insert(String(string[start.lowerBound..<end.upperBound]))
            }
            if let start = string.range(of: "autofill for \""),
               let end = string[start.upperBound...].firstIndex(of: "\"") {
                headings.insert(String(string[start.lowerBound...end]))
            }
        }
        return headings.count == 1 ? headings.first : nil
    }

    /// A replacement authentication host needs independent evidence linking it
    /// to the original card; shared text alone is insufficient.
    static func permitsHostHandoff(sameContext: Bool, sameHeading: Bool,
                                   sameWindow: Bool, matchingFrame: Bool,
                                   originalBiometricGone: Bool, appleSigned: Bool) -> Bool {
        sameContext && sameHeading && appleSigned
            && (sameWindow || (matchingFrame && originalBiometricGone))
    }
}

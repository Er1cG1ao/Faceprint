import Foundation

enum PromptPolicy {
    static let privacyBundleID = "com.apple.settings.PrivacySecurity.extension"
    static let autofillBundleIDs: Set<String> = [
        "com.apple.Passwords",
        "com.apple.LocalAuthentication.UIAgent",
        "com.apple.LocalAuthenticationRemoteService"
    ]

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
        if ownerBundleID == privacyBundleID {
            guard text.contains("privacy & security"),
                  (text.contains("modify your system settings") || text.contains("unlock system settings")) else { return nil }
            return "privacy"
        }
        guard autofillBundleIDs.contains(ownerBundleID), text.contains("passwords"),
              let start = text.range(of: "autofill for \"") else { return nil }
        let suffix = text[start.upperBound...]
        guard let end = suffix.firstIndex(of: "\""), end > suffix.startIndex else { return nil }
        return "autofill:" + suffix[..<end]
    }

    /// Bind fallback to the same app process and request. A password field in
    /// a different process/context is never a continuation of this attempt.
    static func isSameFallbackRequest(originalPID: Int32, passwordPID: Int32,
                                      originalBundleID: String, passwordBundleID: String,
                                      originalContext: String, passwordContext: String) -> Bool {
        originalPID == passwordPID && originalBundleID == passwordBundleID
            && originalContext == passwordContext
    }
}

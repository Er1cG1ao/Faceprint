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

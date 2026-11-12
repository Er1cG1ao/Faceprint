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
        bundleID.hasPrefix("com.apple.settings.") && bundleID.hasSuffix(".extension")
            || bundleID == privacyBundleID || bundleID == "com.apple.systempreferences"
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
            if text.contains("privacy & security") || text.contains("system settings"),
               text.contains("to continue with privacy & security") || text.contains("to continue with system settings")
                || text.contains("to continue with \"privacy & security\"") || text.contains("to continue with \"system settings\""),
               text.contains("modify your system settings") || text.contains("unlock system settings") {
                return "privacy"
            }
        }
        if (ownerBundleID == "com.apple.finder" || authenticationBundleIDs.contains(ownerBundleID)),
           text.contains("to continue with \"finder\"") {
            if text.contains("finder wants to make changes.") { return "finder-changes" }
            if let heading = normalized.first(where: {
                $0.hasPrefix("finder wants to move ") && $0.hasSuffix(" to the trash.")
            }) { return "finder-trash:" + heading }
        }
        return nativeAuthenticationContext(in: strings, ownerBundleID: ownerBundleID)
    }

    /// General macOS account authentication hosted by system agents. Never
    /// interpret website/app login, Apple Account, keychain or disk secrets as
    /// the saved Mac account password.
    static func nativeAuthenticationContext(in strings: [String], ownerBundleID: String) -> String? {
        guard authenticationBundleIDs.contains(ownerBundleID) || ownerBundleID == "com.apple.finder" || ownerBundleID == "com.apple.Passwords"
            || ownerBundleID == "com.apple.systempreferences"
            || (ownerBundleID.hasPrefix("com.apple.settings.") && ownerBundleID.hasSuffix(".extension")) else { return nil }
        let text = canonical(strings.joined(separator: " "))
        let excluded = ["faceprint", "keychain", "apple id", "apple account", "apple pay", "passcode", "verification code", "recovery key", "disk password", "filevault", "ssh", "remote login"]
        guard !excluded.contains(where: text.contains), strings.map(canonical).contains("cancel"),
              text.contains("enter your password") || text.contains("enter the password for the user")
                || text.contains("administrator") && text.contains("name and password"),
              let heading = nativeRequestHeading(in: strings) else { return nil }
        guard let subject = requester(in: heading) else { return nil }
        if ownerBundleID.hasPrefix("com.apple.settings.") {
            func compact(_ text: String) -> String { text.filter(\.isLetter).lowercased() }
            let pane = ownerBundleID.replacingOccurrences(of: "com.apple.settings.", with: "").replacingOccurrences(of: ".extension", with: "")
            guard compact(subject) == compact(pane) || subject == "system settings" else { return nil }
        }
        if text.contains("to continue with \"\(subject)\"") || text.contains("to continue with \(subject)")
                || text.contains("administrator") && text.contains("name and password")
                || text.contains("enter your password to allow this") {
            return "native:" + heading
        }
        return nil
    }

    static func nativeRequestHeading(in strings: [String]) -> String? {
        var headings = Set<String>()
        for text in strings.map(canonical) {
            for pattern in [#"^(.+? (?:wants to|is trying to) .+?\.)(?:$|\s)"#, #"^(autofill for ".+?")"#] {
                if let range = text.range(of: pattern, options: .regularExpression) {
                    headings.insert(String(text[range]).trimmingCharacters(in: .whitespaces))
                }
            }
        }
        if headings.count == 1 { return headings.first }
        guard headings.isEmpty else { return nil }
        // Some native cards expose only a service name and a continuation
        // sentence rather than a wants-to/is-trying-to headline.
        var subjects = Set<String>()
        for text in strings.map(canonical) {
            guard let start = text.range(of: "to continue with ") else { continue }
            var subject = String(text[start.upperBound...]).trimmingCharacters(in: .whitespaces)
            if subject.hasPrefix("\"") {
                subject.removeFirst()
                guard let end = subject.firstIndex(of: "\"") else { continue }
                subject = String(subject[..<end])
            } else { subject = subject.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }
            if !subject.isEmpty, subject.count <= 100,
               !["cancel", "use password", "enter your password"].contains(where: subject.contains) { subjects.insert(subject) }
        }
        return subjects.count == 1 ? "macos account authentication for " + subjects.first! : nil
    }

    static func requester(in heading: String) -> String? {
        let prefix = "macos account authentication for "
        if heading.hasPrefix(prefix) { return String(heading.dropFirst(prefix.count)) }
        for separator in [" wants to ", " is trying to "] {
            if let range = heading.range(of: separator) { return String(heading[..<range.lowerBound]).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        }
        return nil
    }

    static func compatibleHeadings(_ lhs: String?, _ rhs: String?, context: String) -> Bool {
        guard let lhs, let rhs else { return false }
        if lhs == rhs { return true }
        // Settings changes its wording from unlock to modify between stages.
        let privacy = ["privacy & security is trying to modify your system settings.", "privacy & security is trying to unlock system settings."]
        let a = lhs.replacingOccurrences(of: "system settings is trying to", with: "privacy & security is trying to")
        let b = rhs.replacingOccurrences(of: "system settings is trying to", with: "privacy & security is trying to")
        return context == "privacy" && privacy.contains(a) && privacy.contains(b)
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
        return ["use password", "use password...", "enter password", "enter password...", "use login password", "use login password..."].contains(label)
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
        return headings.count == 1 ? headings.first : (headings.isEmpty ? nativeRequestHeading(in: strings) : nil)
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

extension PromptPolicy {
    /// System Settings hosts the biometric card, then delegates password entry
    /// to the dedicated Privacy & Security extension. XPC AX windows are not
    /// necessarily comparable across those hosts. Accept only this directed
    /// delegation after an explicit, verified fallback action; never generalize
    /// the exception to arbitrary authentication agents or unfocused fields.
    static func permitsSettingsDelegateHandoff(originalBundleID: String, passwordBundleID: String,
                                               originalContext: String, passwordContext: String,
                                               fallbackSelected: Bool, focusedEmptyField: Bool,
                                               appleSigned: Bool, foregroundBundleID: String?, foregroundUnchanged: Bool = false) -> Bool {
        originalBundleID == "com.apple.systempreferences" && passwordBundleID == privacyBundleID
            && originalContext == "privacy" && passwordContext == "privacy"
            && fallbackSelected && focusedEmptyField && appleSigned
            && (["com.apple.systempreferences", privacyBundleID].contains(foregroundBundleID ?? "") || foregroundUnchanged)
    }
}

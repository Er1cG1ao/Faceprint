import AppKit
import ApplicationServices
import Security

struct PromptTarget {
    let field: AXUIElement
    let pid: pid_t
    let ownerBundleID: String
    let contextID: String

    var confirmationButton: String { contextID == "privacy" ? "Modify Settings" : "OK" }
    var description: String { contextID == "privacy" ? "Privacy & Security" : "Passwords AutoFill" }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    private static func focusedSecureField(requireEmpty: Bool) -> (field: AXUIElement, pid: pid_t, app: NSRunningApplication)? {
        guard AXIsProcessTrusted(),
              let focused = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let field = focused as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(field, &pid) == .success,
              let application = NSRunningApplication(processIdentifier: pid),
              attribute(field, kAXRoleAttribute) as? String == kAXTextFieldRole,
              (attribute(field, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
               || attribute(field, kAXRoleDescriptionAttribute) as? String == "secure text field"),
              attribute(field, kAXEnabledAttribute) as? Bool != false else { return nil }
        if requireEmpty {
            guard let value = attribute(field, kAXValueAttribute) as? String, value.isEmpty else { return nil }
        }
        return (field, pid, application)
    }

    static func diagnosticSummary() -> String? {
        guard let focused = focusedSecureField(requireEmpty: false) else { return nil }
        return "Focused password field owner: \(focused.app.bundleIdentifier ?? "unknown")"
    }

    static func current(requireEmpty: Bool = true) -> PromptTarget? {
        guard let focused = focusedSecureField(requireEmpty: requireEmpty),
              let bundleID = focused.app.bundleIdentifier,
              focused.app.bundleURL?.path.hasPrefix("/System/") == true else { return nil }
        let contextID: String
        if bundleID == PromptPolicy.privacyBundleID {
            contextID = "privacy"
        } else {
            guard PromptPolicy.autofillBundleIDs.contains(bundleID),
                  let context = autofillContext(for: focused.field) else { return nil }
            contextID = context
        }
        return PromptTarget(field: focused.field, pid: focused.pid, ownerBundleID: bundleID, contextID: contextID)
    }

    private static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = attribute(element, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    private static func dialogText(_ root: AXUIElement) -> [String] {
        var strings: [String] = []
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var inspected = 0
        while let (element, depth) = pending.popLast(), inspected < 180 {
            inspected += 1
            let role = attribute(element, kAXRoleAttribute) as? String
            guard role != kAXApplicationRole else { continue }
            for name in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = attribute(element, name) as? String { strings.append(text) }
            }
            // Values of input fields are excluded. Only static prompt text is read.
            if role == kAXStaticTextRole, let text = attribute(element, kAXValueAttribute) as? String {
                strings.append(text)
            }
            if depth < 6, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
            }
        }
        return strings
    }

    private static func autofillContext(for field: AXUIElement) -> String? {
        let accounts = [NSUserName(), NSFullUserName()]
        if let topLevel = elementAttribute(field, kAXTopLevelUIElementAttribute),
           let context = PromptPolicy.autofillContext(in: dialogText(topLevel), accountNames: accounts) {
            return context
        }
        var ancestor: AXUIElement? = field
        for _ in 0..<7 {
            guard let element = ancestor,
                  attribute(element, kAXRoleAttribute) as? String != kAXApplicationRole else { break }
            if let context = PromptPolicy.autofillContext(in: dialogText(element), accountNames: accounts) {
                return context
            }
            ancestor = elementAttribute(element, kAXParentAttribute)
        }
        return nil
    }

    func isCurrent(requireEmpty: Bool = false) -> Bool {
        guard let current = Self.focusedSecureField(requireEmpty: requireEmpty) else { return false }
        return pid == current.pid && ownerBundleID == current.app.bundleIdentifier && CFEqual(field, current.field)
    }

    func verifyAppleSignature() -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        let rule = "anchor apple and identifier \"\(ownerBundleID)\"" as CFString
        guard SecRequirementCreateWithString(rule, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func maskedLength() -> Int? {
        guard let value = Self.attribute(field, kAXValueAttribute) as? String else { return nil }
        return value.utf16.count
    }

    func pressReturn() throws {
        guard let current = Self.current(requireEmpty: false), current.pid == pid,
              current.contextID == contextID, CFEqual(current.field, field),
              verifyAppleSignature(), let count = maskedLength(), count > 0 else {
            throw FillError.message("Password filled. Automatic Return stopped because the prompt changed.")
        }
        let source = contextID == "privacy" ? nil : CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            throw FillError.message("Password filled. Return could not be sent.")
        }
        down.flags = []
        up.flags = []
        post(down, up)
    }

    private func post(_ down: CGEvent, _ up: CGEvent) {
        if contextID == "privacy" {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        } else {
            down.postToPid(pid)
            up.postToPid(pid)
        }
    }

    /// Privacy & Security's extension does not reliably receive process-targeted
    /// events. Use Glance/Hammerspoon's HID delivery there and preserve the working
    /// direct-to-process route for Passwords AutoFill.
    func type(_ bytes: Data) async throws -> Bool {
        guard let current = Self.current(), current.pid == pid,
              current.contextID == contextID, CFEqual(current.field, field), verifyAppleSignature(),
              let text = String(data: bytes, encoding: .utf8),
              !text.isEmpty, !text.contains(where: { $0.isNewline || $0 == "\t" }) else {
            throw FillError.message("The verified empty system password field is no longer focused.")
        }
        let source = contextID == "privacy" ? nil : CGEventSource(stateID: .privateState)
        let chunks = KeyboardText.batches(text, maximumUTF16Units: contextID == "privacy" ? 1 : 20)
        let events = try chunks.map { chunk -> (CGEvent, CGEvent) in
            try chunk.withUnsafeBufferPointer { buffer in
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false),
                      let base = buffer.baseAddress else { throw FillError.message("Cannot create keyboard events.") }
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                down.flags = []
                up.flags = []
                return (down, up)
            }
        }
        for (down, up) in events {
            try Task.checkCancellation()
            guard isCurrent() else { throw FillError.message("Focus changed. Review the password field before retrying.") }
            post(down, up)
            try await Task.sleep(for: .milliseconds(12))
        }
        let expectedLengths = Set([text.count, text.utf16.count])
        for _ in 0..<8 {
            try Task.checkCancellation()
            guard isCurrent() else { throw FillError.message("Focus changed before filling could be verified. Check the field.") }
            if let count = maskedLength(), expectedLengths.contains(count) { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard let count = maskedLength() else { return false }
        if count == 0 { throw FillError.message("The password field is still empty. Hover the Dynamic Island to retry.") }
        throw FillError.message("The field appears partially filled. Clear it before retrying.")
    }
}

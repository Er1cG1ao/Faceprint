import AppKit
import ApplicationServices
import Security

struct PromptTarget {
    let field: AXUIElement
    let pid: pid_t
    let ownerBundleID: String
    let contextID: String
    var discoveryFrontmostPID: pid_t? = nil
    var dialogRoot: AXUIElement? = nil

    var confirmationButton: String { contextID == "privacy" ? "the confirmation button" : "OK" }
    var description: String { contextID == "privacy" ? "Privacy & Security" : (contextID.hasPrefix("finder-") ? "Finder authorization" : (contextID.hasPrefix("native:") ? "macOS account authorization" : "Passwords AutoFill")) }

    fileprivate static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    fileprivate static func focusedElement() -> (element: AXUIElement, pid: pid_t, app: NSRunningApplication)? {
        guard AXIsProcessTrusted(),
              let focused = attribute(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { return nil }
        return (element, pid, app)
    }

    fileprivate static func fieldLength(_ field: AXUIElement) -> Int? {
        InputActionPolicy.secureFieldLength(
            characterCount: (attribute(field, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue,
            value: attribute(field, kAXValueAttribute) as? String)
    }

    private static func focusedSecureField(requireEmpty: Bool) -> (field: AXUIElement, pid: pid_t, app: NSRunningApplication)? {
        guard let focused = focusedElement() else { return nil }
        let field = focused.element
        guard attribute(field, kAXRoleAttribute) as? String == kAXTextFieldRole,
              (attribute(field, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
               || attribute(field, kAXRoleDescriptionAttribute) as? String == "secure text field"),
              attribute(field, kAXEnabledAttribute) as? Bool != false else { return nil }
        if requireEmpty {
            guard fieldLength(field) == 0 else { return nil }
        }
        return (field, focused.pid, focused.app)
    }

    static func diagnosticSummary() -> String? {
        guard let focused = focusedElement(), let bundle = focused.app.bundleIdentifier,
              focused.app.bundleURL?.path.hasPrefix("/System/") == true else { return nil }
        let role = attribute(focused.element, kAXRoleAttribute) as? String ?? "unknown role"
        return "System prompt owner: \(bundle) (\(role)); no supported request matched."
    }

    static func current(requireEmpty: Bool = true) -> PromptTarget? {
        guard let focused = focusedSecureField(requireEmpty: requireEmpty) else { return nil }
        return candidate(focused.field, requireEmpty: requireEmpty)
    }

    /// Classify a specific secure field without requiring keyboard focus. This
    /// never reads credentials: the AX value is used only to require emptiness.
    fileprivate static func candidate(_ field: AXUIElement, requireEmpty: Bool) -> PromptTarget? {
        guard attribute(field, kAXRoleAttribute) as? String == kAXTextFieldRole,
              attribute(field, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
                || attribute(field, kAXRoleDescriptionAttribute) as? String == "secure text field",
              attribute(field, kAXEnabledAttribute) as? Bool != false,
              attribute(field, "AXHidden") as? Bool != true else { return nil }
        if requireEmpty {
            guard fieldLength(field) == 0 else { return nil }
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(field, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier,
              app.bundleURL?.path.hasPrefix("/System/") == true, PromptPolicy.supportsOwner(bundleID) else { return nil }
        let descriptor = dialogDescriptor(for: field, bundleID: bundleID)
        let contextID: String
        if let descriptor { contextID = descriptor.context }
        else if bundleID == PromptPolicy.privacyBundleID { contextID = "privacy" }
        else { return nil }
        var target = PromptTarget(field: field, pid: pid, ownerBundleID: bundleID, contextID: contextID)
        target.dialogRoot = descriptor?.root
        return target
    }

    fileprivate func focusForContinuation() {
        let window = Self.elementAttribute(field, kAXWindowAttribute)
            ?? Self.elementAttribute(field, kAXTopLevelUIElementAttribute)
        if let window { AXUIElementPerformAction(window, kAXRaiseAction as CFString) }
        AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    fileprivate static func authenticationRoots(of application: AXUIElement) -> [AXUIElement] {
        AXUIElementSetMessagingTimeout(application, 0.15)
        var windows = attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? []
        if let window = elementAttribute(application, kAXFocusedWindowAttribute),
           !windows.contains(where: { CFEqual($0, window) }) { windows.insert(window, at: 0) }
        var result: [AXUIElement] = []
        for window in windows.prefix(12) {
            var sheets = attribute(window, "AXSheets") as? [AXUIElement] ?? []
            let children = attribute(window, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children.prefix(60) {
                if attribute(child, kAXRoleAttribute) as? String == kAXSheetRole
                    || attribute(child, kAXSubroleAttribute) as? String == kAXDialogSubrole {
                    if !sheets.contains(where: { CFEqual($0, child) }) { sheets.append(child) }
                }
            }
            // An attached modal sheet owns authentication; do not traverse the
            // large, inactive Settings page behind it or collect its fields.
            let roots = sheets.isEmpty ? [window] : Array(sheets.prefix(12))
            for root in roots where !result.contains(where: { CFEqual($0, root) }) { result.append(root) }
        }
        return result
    }

    static func discover() -> PromptTarget? {
        let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var matches: [PromptTarget] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundle = app.bundleIdentifier, PromptPolicy.supportsOwner(bundle),
                  app.bundleURL?.path.hasPrefix("/System/") == true else { continue }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            for window in authenticationRoots(of: application) where BiometricPromptTarget.visible(window, pid: app.processIdentifier) {
                var pending: [(AXUIElement, Int)] = [(window, 0)]
                var count = 0
                var windowMatches: [PromptTarget] = []
                while let (element, depth) = pending.popLast(), count < 180 {
                    count += 1
                    guard attribute(element, "AXHidden") as? Bool != true else { continue }
                    if var target = candidate(element, requireEmpty: true), target.verifyAppleSignature(),
                       !windowMatches.contains(where: { CFEqual($0.field, target.field) }) {
                        target.discoveryFrontmostPID = foreground
                        windowMatches.append(target)
                    }
                    if depth < 8, let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                        pending.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
                    }
                }
                guard pending.isEmpty else { continue }
                for target in windowMatches where !matches.contains(where: { CFEqual($0.field, target.field) }) { matches.append(target) }
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    func availableForRecognition() -> Bool {
        guard let discoveryFrontmostPID else { return isCurrent(requireEmpty: true) }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == discoveryFrontmostPID,
              let candidate = Self.candidate(field, requireEmpty: true), candidate.pid == pid,
              candidate.contextID == contextID,
              let window = Self.elementAttribute(field, kAXWindowAttribute) ?? Self.elementAttribute(field, kAXTopLevelUIElementAttribute) else { return false }
        return BiometricPromptTarget.visible(window, pid: pid)
    }

    func prepareForInput(progress: @Sendable (String) -> Void) async throws -> PromptTarget {
        if isCurrent(requireEmpty: true) { return self }
        guard availableForRecognition(), verifyAppleSignature() else { throw CancellationError() }
        progress("Focusing the password field (\(ownerBundleID))")
        focusForContinuation()
        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline {
            try Task.checkCancellation()
            if isCurrent(requireEmpty: true) {
                try await Task.sleep(for: .milliseconds(40))
                if isCurrent(requireEmpty: true) { return self }
            }
            try await Task.sleep(for: .milliseconds(16))
        }
        throw FillError.message("The password field could not receive keyboard focus. Choose Retry current prompt.")
    }

    fileprivate static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let result = attribute(element, name), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }

    fileprivate static func dialogText(_ root: AXUIElement) -> [String] {
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

    fileprivate static func dialogDescriptor(for field: AXUIElement, bundleID: String) -> (context: String, root: AXUIElement)? {
        let accounts = [NSUserName(), NSFullUserName()]
        func context(_ element: AXUIElement) -> String? {
            let text = dialogText(element)
            if let system = PromptPolicy.systemDialogContext(in: text, ownerBundleID: bundleID) { return system }
            guard PromptPolicy.autofillBundleIDs.contains(bundleID) else { return nil }
            return PromptPolicy.autofillContext(in: text, accountNames: accounts)
        }
        var ancestor: AXUIElement? = field
        for _ in 0..<7 {
            guard let element = ancestor,
                  attribute(element, kAXRoleAttribute) as? String != kAXApplicationRole else { break }
            if let context = context(element) {
                return (context, element)
            }
            ancestor = elementAttribute(element, kAXParentAttribute)
        }
        if let topLevel = elementAttribute(field, kAXTopLevelUIElementAttribute),
           let context = context(topLevel) {
            return (context, topLevel)
        }
        return nil
    }

    func isCurrent(requireEmpty: Bool = false) -> Bool {
        guard let current = Self.focusedSecureField(requireEmpty: requireEmpty) else { return false }
        return pid == current.pid && ownerBundleID == current.app.bundleIdentifier && CFEqual(field, current.field)
    }

    func verifyAppleSignature() -> Bool {
        Self.verifyAppleSignature(pid: pid, bundleID: ownerBundleID)
    }

    fileprivate static func verifyAppleSignature(pid: pid_t, bundleID: String) -> Bool {
        var code: SecCode?
        let attributes = [kSecGuestAttributePid as String: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        let rule = "anchor apple and identifier \"\(bundleID)\"" as CFString
        guard SecRequirementCreateWithString(rule, [], &requirement) == errSecSuccess else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    private func maskedLength() -> Int? {
        Self.fieldLength(field)
    }

    func pressReturn() throws {
        guard let current = Self.current(requireEmpty: false), current.pid == pid,
              current.contextID == contextID, CFEqual(current.field, field),
              verifyAppleSignature(), let count = maskedLength(), count > 0 else {
            throw FillError.message("Password filled. Automatic Return stopped because the prompt changed.")
        }
        let source = !contextID.hasPrefix("autofill:") ? nil : CGEventSource(stateID: .privateState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false) else {
            throw FillError.message("Password filled. Return could not be sent.")
        }
        down.flags = []
        up.flags = []
        post(down, up)
    }

    private func post(_ down: CGEvent, _ up: CGEvent) {
        if !contextID.hasPrefix("autofill:") {
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
    func type(_ bytes: Data, progress: @Sendable (String) -> Void) async throws -> Bool {
        try Task.checkCancellation()
        guard let current = Self.current(), current.pid == pid, current.contextID == contextID,
              CFEqual(current.field, field), verifyAppleSignature(),
              let text = String(data: bytes, encoding: .utf8), !text.isEmpty,
              !text.contains(where: { $0.isNewline || $0 == "\t" }) else {
            throw FillError.message("The verified empty system password field is no longer focused.")
        }
        let expected = Set([text.count, text.utf16.count])
        var settable = DarwinBoolean(false)
        let canSet = AXUIElementIsAttributeSettable(field, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
        try Task.checkCancellation()
        if canSet && AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFString) == .success {
            progress("Password assigned to secure field; checking delivery")
        } else {
            guard isCurrent(requireEmpty: true) else { throw FillError.message("Password field changed before input.") }
            let source = !contextID.hasPrefix("autofill:") ? nil : CGEventSource(stateID: .privateState)
            // Settings' HID compatibility path stays character-based, without
            // artificial per-character sleeps. Other prompts use Unicode batches.
            let settingsHID = contextID == "privacy" || ownerBundleID.hasPrefix("com.apple.settings.") || ownerBundleID == "com.apple.systempreferences"
            let chunks = KeyboardText.batches(text, maximumUTF16Units: settingsHID ? 1 : 20)
            for chunk in chunks {
                try Task.checkCancellation()
                guard isCurrent() else { throw FillError.message("Focus changed during input. Review the field.") }
                try chunk.withUnsafeBufferPointer { buffer in
                    guard let base = buffer.baseAddress,
                          let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                          let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                        throw FillError.message("Cannot create keyboard events.")
                    }
                    down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                    up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: base)
                    down.flags = []; up.flags = []
                    post(down, up)
                }
            }
            progress("Keyboard input sent; checking delivery")
        }
        // No fixed post-fill settling period: the first matching sample wins.
        // Unknown or partial delivery never triggers Return or a second write.
        let deadline = Date().addingTimeInterval(0.18)
        repeat {
            try Task.checkCancellation()
            guard isCurrent() else { throw FillError.message("Focus changed before input could be verified.") }
            if let count = maskedLength(), expected.contains(count) { return true }
            try await Task.sleep(for: .milliseconds(8))
        } while Date() < deadline
        guard let count = maskedLength() else { return false }
        if count == 0 { throw FillError.message("The password field is still empty. Choose Retry current prompt.") }
        throw FillError.message("Input length did not match. Review or clear the field before retrying.")
    }

}

private struct PasswordFallbackAnchor {
    let window: AXUIElement
    let frame: CGRect?
    let heading: String?

    init(root: AXUIElement, button: AXUIElement, ownerBundleID: String) {
        let card = PromptTarget.dialogDescriptor(for: button, bundleID: ownerBundleID)?.root ?? root
        window = PromptTarget.elementAttribute(button, kAXWindowAttribute)
            ?? PromptTarget.elementAttribute(button, kAXTopLevelUIElementAttribute) ?? root
        frame = Self.frame(of: card) ?? Self.frame(of: window)
        heading = PromptPolicy.requestHeading(in: PromptTarget.dialogText(card))
            ?? PromptPolicy.requestHeading(in: PromptTarget.dialogText(window))
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let position = PromptTarget.attribute(element, kAXPositionAttribute),
              let size = PromptTarget.attribute(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    func canContain(_ element: AXUIElement) -> Bool {
        if CFEqual(window, element) { return true }
        guard let frame, let rect = Self.frame(of: element) else { return false }
        return abs(frame.midX - rect.midX) <= 24 && abs(frame.midY - rect.midY) <= 96
            && abs(frame.width - rect.width) <= 32 && rect.height / frame.height < 2
            && frame.height / rect.height < 2
    }

    func matches(_ candidate: PromptTarget, context: String, originalBiometricGone: Bool) -> Bool {
        let candidateWindow = PromptTarget.elementAttribute(candidate.field, kAXWindowAttribute)
            ?? PromptTarget.elementAttribute(candidate.field, kAXTopLevelUIElementAttribute)
        guard let candidateWindow else { return false }
        let card = candidate.dialogRoot ?? candidateWindow
        let text = PromptTarget.dialogText(card)
        let candidateHeading = PromptPolicy.requestHeading(in: text)
        let rect = Self.frame(of: card) ?? Self.frame(of: candidateWindow)
        // Password cards can grow vertically around their original center.
        let matchingFrame: Bool
        if let frame, let rect {
            matchingFrame = abs(frame.midX - rect.midX) <= 24 && abs(frame.midY - rect.midY) <= 96
                && abs(frame.width - rect.width) <= 32 && rect.height / frame.height < 2
                && frame.height / rect.height < 2
        } else { matchingFrame = false }
        return PromptPolicy.permitsHostHandoff(sameContext: candidate.contextID == context,
            sameHeading: PromptPolicy.compatibleHeadings(heading, candidateHeading, context: context),
            sameWindow: CFEqual(window, candidateWindow), matchingFrame: matchingFrame,
            originalBiometricGone: originalBiometricGone, appleSigned: candidate.verifyAppleSignature())
    }
}

/// A visible Touch ID card and its explicit password-fallback control. No
/// keyboard Return is sent to discover the password stage or confirm a request.
struct BiometricPromptTarget {
    let root: AXUIElement
    let button: AXUIElement
    let pid: pid_t
    let ownerBundleID: String
    let contextID: String

    // Preserve the user's app choice during a scan of a nonfocused card.
    let discoveryFrontmostPID: pid_t?

    var description: String { contextID == "privacy" ? "Privacy & Security Touch ID" : (contextID.hasPrefix("finder-") ? "Finder Touch ID" : (contextID.hasPrefix("native:") ? "macOS account Touch ID" : "Passwords AutoFill Touch ID")) }

    private static func focused() -> BiometricPromptTarget? {
        guard let focused = PromptTarget.focusedElement(), let bundleID = focused.app.bundleIdentifier,
              focused.app.bundleURL?.path.hasPrefix("/System/") == true,
              PromptPolicy.supportsOwner(bundleID) else { return nil }
        var ancestor: AXUIElement? = focused.element
        var roots: [AXUIElement] = []
        for _ in 0..<8 {
            guard let element = ancestor,
                  PromptTarget.attribute(element, kAXRoleAttribute) as? String != kAXApplicationRole else { break }
            roots.append(element)
            ancestor = PromptTarget.elementAttribute(element, kAXParentAttribute)
        }
        if let top = PromptTarget.elementAttribute(focused.element, kAXTopLevelUIElementAttribute),
           !roots.contains(where: { CFEqual($0, top) }) { roots.append(top) }
        for root in roots {
            guard let button = fallbackButton(in: root) else { continue }
            var ownerPID: pid_t = 0
            guard AXUIElementGetPid(button, &ownerPID) == .success,
                  let owner = NSRunningApplication(processIdentifier: ownerPID),
                  let ownerID = owner.bundleIdentifier, PromptPolicy.supportsOwner(ownerID),
                  owner.bundleURL?.path.hasPrefix("/System/") == true,
                  let context = PromptPolicy.biometricContext(in: PromptTarget.dialogText(root), ownerBundleID: ownerID) else { continue }
            return BiometricPromptTarget(root: root, button: button, pid: ownerPID,
                                         ownerBundleID: ownerID, contextID: context, discoveryFrontmostPID: nil)
        }
        return nil
    }

    static func current() -> BiometricPromptTarget? {
        if let target = focused() { return target }
        guard AXIsProcessTrusted() else { return nil }
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var candidates: [BiometricPromptTarget] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  PromptPolicy.supportsOwner(bundleID),
                  app.bundleURL?.path.hasPrefix("/System/") == true else { continue }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            for window in PromptTarget.authenticationRoots(of: application) where visible(window, pid: app.processIdentifier) {
                guard let button = fallbackButton(in: window) else { continue }
                // An XPC child may belong to the extension/agent rather than
                // the application whose AXWindows exposed the card.
                var buttonPID: pid_t = 0
                guard AXUIElementGetPid(button, &buttonPID) == .success,
                      let owner = NSRunningApplication(processIdentifier: buttonPID),
                      let ownerID = owner.bundleIdentifier, PromptPolicy.supportsOwner(ownerID),
                      owner.bundleURL?.path.hasPrefix("/System/") == true,
                      let context = PromptPolicy.biometricContext(in: PromptTarget.dialogText(window), ownerBundleID: ownerID) else { continue }
                let candidate = BiometricPromptTarget(root: window, button: button, pid: buttonPID,
                    ownerBundleID: ownerID, contextID: context, discoveryFrontmostPID: frontmostPID)
                if !candidates.contains(where: { CFEqual($0.button, button) }) { candidates.append(candidate) }
            }
        }
        // Never choose between multiple simultaneous authentication requests.
        return candidates.count == 1 ? candidates[0] : nil
    }

    fileprivate static func visible(_ window: AXUIElement, pid: pid_t) -> Bool {
        guard PromptTarget.attribute(window, kAXMinimizedAttribute) as? Bool != true,
              PromptTarget.attribute(window, "AXHidden") as? Bool != true,
              let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        var axFrame: CGRect?
        if let position = PromptTarget.attribute(window, kAXPositionAttribute),
           let size = PromptTarget.attribute(window, kAXSizeAttribute),
           CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() {
            var origin = CGPoint.zero
            var dimensions = CGSize.zero
            if AXValueGetValue(position as! AXValue, .cgPoint, &origin),
               AXValueGetValue(size as! AXValue, .cgSize, &dimensions), dimensions.width > 0, dimensions.height > 0 {
                axFrame = CGRect(origin: origin, size: dimensions)
            }
        }
        return windows.contains { info in
            guard (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return false }
            if (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid { return true }
            // XPC-hosted Settings cards can be drawn by System Settings rather
            // than their AX owner. Require matching on-screen window geometry.
            guard let axFrame, let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
            return abs(frame.minX - axFrame.minX) <= 12 && abs(frame.minY - axFrame.minY) <= 12
                && abs(frame.width - axFrame.width) <= 24 && abs(frame.height - axFrame.height) <= 24
        }
    }

    private static func fallbackButton(in root: AXUIElement) -> AXUIElement? {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var inspected = 0
        var buttons: [AXUIElement] = []
        while let (element, depth) = pending.popLast(), inspected < 180 {
            inspected += 1
            let role = PromptTarget.attribute(element, kAXRoleAttribute) as? String
            guard role != kAXApplicationRole else { continue }
            if role == kAXTextFieldRole,
               (PromptTarget.attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
                || PromptTarget.attribute(element, kAXRoleDescriptionAttribute) as? String == "secure text field"),
               PromptTarget.attribute(element, "AXHidden") as? Bool != true { return nil }
            if role == kAXButtonRole, PromptTarget.attribute(element, kAXEnabledAttribute) as? Bool != false,
               PromptTarget.attribute(element, "AXHidden") as? Bool != true,
               let title = (PromptTarget.attribute(element, kAXTitleAttribute) as? String)
                    ?? (PromptTarget.attribute(element, kAXDescriptionAttribute) as? String),
               PromptPolicy.isPasswordFallbackButton(title) { buttons.append(element) }
            if depth < 6, let children = PromptTarget.attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
            }
        }
        // Ambiguous or truncated trees are not a safe target for a fallback click.
        guard pending.isEmpty, buttons.count == 1 else { return nil }
        return buttons[0]
    }

    func isCurrent() -> Bool {
        guard PromptTarget.attribute(button, kAXEnabledAttribute) as? Bool == true,
              PromptTarget.attribute(button, "AXHidden") as? Bool != true,
              let title = (PromptTarget.attribute(button, kAXTitleAttribute) as? String)
                  ?? (PromptTarget.attribute(button, kAXDescriptionAttribute) as? String),
              PromptPolicy.isPasswordFallbackButton(title) else { return false }
        if let discoveryFrontmostPID {
            return NSWorkspace.shared.frontmostApplication?.processIdentifier == discoveryFrontmostPID
                && Self.visible(root, pid: pid)
        }
        guard let focused = PromptTarget.focusedElement() else { return false }
        var element: AXUIElement? = focused.element
        for _ in 0..<9 {
            guard let current = element else { break }
            if CFEqual(current, root) { return true }
            element = PromptTarget.elementAttribute(current, kAXParentAttribute)
        }
        return false
    }

    func verifyAppleSignature() -> Bool {
        PromptTarget.verifyAppleSignature(pid: pid, bundleID: ownerBundleID)
    }

    func openPasswordField(progress: @Sendable (String) -> Void) async throws -> PromptTarget {
        try Task.checkCancellation()
        guard isCurrent(), verifyAppleSignature(),
              PromptPolicy.biometricContext(in: PromptTarget.dialogText(root), ownerBundleID: ownerBundleID) == contextID else {
            throw FillError.message("Touch ID prompt changed. Password fallback was not selected.")
        }
        // Only raise the authenticated card after the enrolled face matches.
        // Input remains forbidden until macOS confirms the expected focused card.
        if discoveryFrontmostPID != nil {
            NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            AXUIElementPerformAction(root, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(button, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        progress("Selecting the verified Use Password control")
        let anchor = PasswordFallbackAnchor(root: root, button: button, ownerBundleID: ownerBundleID)
        guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            throw FillError.message("Use Password could not be selected. Open the password field manually.")
        }
        let transitionStarted = Date()
        let transitionFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let deadline = transitionStarted.addingTimeInterval(3)
        var lastField: AXUIElement?
        var readiness = PasswordFieldReadiness()
        var lastPhase = ""
        func report(_ phase: String) { if phase != lastPhase { lastPhase = phase; progress(phase) } }
        while Date() < deadline {
            try Task.checkCancellation()
            // The original host may exit after handing the card to another
            // Apple agent. Every discovered target is independently verified.
            // A newly mounted password card may initially focus its user-name
            // field or no field at all. Find its secure field within this request.
            if let target = continuationField(anchor: anchor, originalForegroundPID: transitionFrontmostPID) {
                let sameField = lastField.map { CFEqual($0, target.field) } ?? false
                if !sameField { lastField = target.field }
                guard let length = PromptTarget.fieldLength(target.field) else {
                    throw FillError.message("The secure field exposes neither a character count nor a readable length. Input was not started.")
                }
                guard length == 0 else { throw FillError.message("The password field is not empty. No password was entered.") }
                let focused = target.isCurrent(requireEmpty: true)
                if ownerBundleID == "com.apple.systempreferences", target.ownerBundleID == PromptPolicy.privacyBundleID {
                    report("Settings password delegate linked (PrivacySecurity.extension); confirming empty-field focus")
                } else {
                    report("Password field found (\(target.ownerBundleID)); \(focused ? "confirming focus" : "requesting focus")")
                }
                if !focused {
                    let foreground = NSWorkspace.shared.frontmostApplication
                    let expectedRequester = contextID == "privacy" ? "com.apple.systempreferences"
                        : (contextID.hasPrefix("finder-") ? "com.apple.finder" : "")
                    let isExpectedRequester = !expectedRequester.isEmpty && foreground?.bundleIdentifier == expectedRequester
                        && foreground.map { PromptTarget.verifyAppleSignature(pid: $0.processIdentifier, bundleID: expectedRequester) } == true
                    if let active = foreground?.processIdentifier, !isExpectedRequester,
                       active != pid, active != target.pid, active != discoveryFrontmostPID, active != transitionFrontmostPID,
                       active != NSRunningApplication.current.processIdentifier {
                        throw FillError.message("The active app changed during password fallback. No password was entered.")
                    }
                    target.focusForContinuation()
                }
                if readiness.observe(sameField: sameField, focusedAndEmpty: focused,
                    now: Date().timeIntervalSince(transitionStarted)), target.verifyAppleSignature() {
                    return target
                }
            } else {
                if let focused = PromptTarget.focusedElement() {
                    let role = PromptTarget.attribute(focused.element, kAXRoleAttribute) as? String ?? "unknown"
                    report("Waiting for password link; focused owner \(focused.app.bundleIdentifier ?? "unknown") (\(role)); foreground \(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown")")
                } else { report("Waiting for password link; no focused AX element") }
                _ = readiness.observe(sameField: false, focusedAndEmpty: false,
                    now: Date().timeIntervalSince(transitionStarted))
            }
            try await Task.sleep(for: .milliseconds(16))
        }
        if let observed = PromptTarget.current(requireEmpty: false),
           observed.pid != pid || observed.ownerBundleID != ownerBundleID {
            throw FillError.message("Password handoff not accepted: \(ownerBundleID) → \(observed.ownerBundleID); contextMatches=\(observed.contextID == contextID), focusedEmpty=\(observed.isCurrent(requireEmpty: true)), appleSigned=\(observed.verifyAppleSignature()), foreground=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"). Choose Retry current prompt.")
        }
        throw FillError.message("The password field did not become ready. Focus it and choose Retry current prompt.")
    }

    /// Search the original host and supported replacement hosts. Cross-host
    /// matches require the captured card anchor, not a general process allowlist.
    private func continuationField(anchor: PasswordFallbackAnchor, originalForegroundPID: pid_t?) -> PromptTarget? {
        let originalBiometricGone = Self.fallbackButton(in: root) == nil
            || PromptPolicy.biometricContext(in: PromptTarget.dialogText(root), ownerBundleID: ownerBundleID) != contextID
        func accepts(_ candidate: PromptTarget) -> Bool {
            guard candidate.contextID == contextID, candidate.verifyAppleSignature() else { return false }
            return PromptPolicy.isSameFallbackRequest(originalPID: pid, passwordPID: candidate.pid,
                originalBundleID: ownerBundleID, passwordBundleID: candidate.ownerBundleID,
                originalContext: contextID, passwordContext: candidate.contextID)
                || anchor.matches(candidate, context: contextID, originalBiometricGone: originalBiometricGone)
        }
        // An already focused, verified field is authoritative and avoids walking
        // large unrelated Settings trees. It must still pass the settling gate.
        if let current = PromptTarget.current(requireEmpty: false) {
            let foreground = NSWorkspace.shared.frontmostApplication
            let foregroundPID = foreground?.processIdentifier
            let foregroundUnchanged = foregroundPID != nil
                && (foregroundPID == originalForegroundPID || foregroundPID == discoveryFrontmostPID)
            let settingsDelegate = PromptPolicy.permitsSettingsDelegateHandoff(
                originalBundleID: ownerBundleID, passwordBundleID: current.ownerBundleID,
                originalContext: contextID, passwordContext: current.contextID,
                fallbackSelected: true, // This method is entered only after successful AXPress.
                focusedEmptyField: current.isCurrent(requireEmpty: true),
                appleSigned: current.verifyAppleSignature(),
                foregroundBundleID: foreground?.bundleIdentifier, foregroundUnchanged: foregroundUnchanged)
            if settingsDelegate || accepts(current) { return current }
        }
        var roots = [root]
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier, PromptPolicy.supportsOwner(bundleID),
                  app.bundleURL?.path.hasPrefix("/System/") == true else { continue }
            let application = AXUIElementCreateApplication(app.processIdentifier)
            roots.append(contentsOf: PromptTarget.authenticationRoots(of: application).filter { anchor.canContain($0) })
        }
        if let focused = PromptTarget.focusedElement() {
            roots.append(PromptTarget.elementAttribute(focused.element, kAXTopLevelUIElementAttribute) ?? focused.element)
        }
        var matches: [PromptTarget] = []
        var visitedRoots: [AXUIElement] = []
        for root in roots {
            guard !visitedRoots.contains(where: { CFEqual($0, root) }) else { continue }
            visitedRoots.append(root)
            var pending: [(AXUIElement, Int)] = [(root, 0)]
            var inspected = 0
            var rootMatches: [PromptTarget] = []
            while let (element, depth) = pending.popLast(), inspected < 240 {
                inspected += 1
                guard PromptTarget.attribute(element, "AXHidden") as? Bool != true else { continue }
                if let candidate = PromptTarget.candidate(element, requireEmpty: false), candidate.contextID == contextID {
                    if accepts(candidate), !rootMatches.contains(where: { CFEqual($0.field, candidate.field) }) {
                        rootMatches.append(candidate)
                    }
                }
                if depth < 10, let children = PromptTarget.attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                    pending.append(contentsOf: children.prefix(60).map { ($0, depth + 1) })
                }
            }
            guard pending.isEmpty else { continue }
            for candidate in rootMatches where !matches.contains(where: { CFEqual($0.field, candidate.field) }) { matches.append(candidate) }
        }
        return matches.count == 1 ? matches[0] : nil
    }
}

enum FillTrigger {
    case password(PromptTarget)
    case biometric(BiometricPromptTarget)

    static func current(allowBiometric: Bool) -> FillTrigger? {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.15)
        if let target = PromptTarget.current() { return .password(target) }
        if allowBiometric, let target = BiometricPromptTarget.current() { return .biometric(target) }
        if let target = PromptTarget.discover() { return .password(target) }
        return nil
    }
    var requestKey: String {
        switch self {
        // This key only suppresses repeat scans; it never authorizes a fill.
        // A host change must not cause an automatic second face scan either.
        case .password(let target): return target.contextID
        case .biometric(let target): return target.contextID
        }
    }
    var element: AXUIElement {
        switch self { case .password(let target): return target.field; case .biometric(let target): return target.button }
    }
    var description: String {
        switch self { case .password(let target): return target.description; case .biometric(let target): return target.description }
    }
    var isBiometric: Bool { if case .biometric = self { return true }; return false }
    func isCurrent() -> Bool {
        switch self { case .password(let target): return target.availableForRecognition(); case .biometric(let target): return target.isCurrent() }
    }
    func verifyAppleSignature() -> Bool {
        switch self { case .password(let target): return target.verifyAppleSignature(); case .biometric(let target): return target.verifyAppleSignature() }
    }
    func passwordTargetAfterRecognition(progress: @Sendable (String) -> Void) async throws -> PromptTarget {
        switch self {
        case .password(let target):
            return try await target.prepareForInput(progress: progress)
        case .biometric(let target): return try await target.openPasswordField(progress: progress)
        }
    }
}
